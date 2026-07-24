import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

import { AuthContext } from "./authContext";
import { supabase } from "../services/supabaseClient";

const STAFF_ROLE_SLUGS = [
  "HR_SITE_CONNECT",
  "HR_SITE_CONNECT_LEAD",
  "HR_EXECUTIVE",
  "HR_EXECUTIVE_LEAD",
  "HR_LEAD",
  "FOUNDERS_OFFICE",
  "ADMIN",
];

const PERFORMANCE_DASHBOARD_ROLE_SLUGS = [
  "HR_SITE_CONNECT",
  "HR_SITE_CONNECT_LEAD",
  "HR_EXECUTIVE",
  "HR_EXECUTIVE_LEAD",
  "HR_LEAD",
];

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const normalizeCandidateId = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value) ? value : null;

const INITIAL_AUTH_STATE = {
  session: null,
  user: null,
  loading: true,
  isActiveAppUser: false,
  hasStaffAccess: false,
  hasPerformanceDashboardAccess: false,
  hasCandidateRole: false,
  candidateId: null,
  hasCandidateAccess: false,
  authorizationError: null,
};

const NO_SESSION_KEY = "NO_SESSION";
const AUTHORIZATION_ERROR_MESSAGE =
  "We could not verify your workspace access. Please try again or contact an administrator.";

export function AuthProvider({ children }) {
  const [authState, setAuthState] = useState(INITIAL_AUTH_STATE);
  const [isPasswordRecovery, setIsPasswordRecovery] = useState(false);
  const passwordRecoveryRef = useRef(false);
  const sessionRef = useRef(null);
  const requestIdRef = useRef(0);
  const completedSessionKeyRef = useRef(null);
  const authorizationResultRef = useRef(null);
  const inFlightAuthorizationRef = useRef(null);

  const updatePasswordRecoveryState = useCallback((isRecovery) => {
    passwordRecoveryRef.current = isRecovery;
    setIsPasswordRecovery(isRecovery);
  }, []);

  const synchronizeSession = useCallback((nextSession, force = false) => {
    const sessionKey = nextSession?.access_token || NO_SESSION_KEY;

    if (!force && inFlightAuthorizationRef.current?.key === sessionKey) {
      return inFlightAuthorizationRef.current.promise;
    }

    if (
      !force &&
      completedSessionKeyRef.current === sessionKey &&
      authorizationResultRef.current
    ) {
      return Promise.resolve(authorizationResultRef.current);
    }

    const requestId = ++requestIdRef.current;

    const authorizationPromise = (async () => {
      sessionRef.current = nextSession;

      if (!nextSession) {
        updatePasswordRecoveryState(false);

        const result = {
          isActiveAppUser: false,
          hasStaffAccess: false,
          hasPerformanceDashboardAccess: false,
          hasCandidateRole: false,
          candidateId: null,
          hasCandidateAccess: false,
          authorizationError: null,
        };

        setAuthState({
          session: null,
          user: null,
          loading: false,
          ...result,
        });
        completedSessionKeyRef.current = sessionKey;
        authorizationResultRef.current = result;
        return result;
      }

      setAuthState({
        session: nextSession,
        user: nextSession.user,
        loading: true,
        isActiveAppUser: false,
        hasStaffAccess: false,
        hasPerformanceDashboardAccess: false,
        hasCandidateRole: false,
        candidateId: null,
        hasCandidateAccess: false,
        authorizationError: null,
      });

      let result;

      try {
        const [
          activeUserResult,
          staffRoleResult,
          performanceDashboardRoleResult,
          candidateRoleResult,
          candidateIdResult,
        ] = await Promise.all([
          supabase.rpc("current_user_is_active"),
          supabase.rpc("current_user_has_any_role", {
            p_role_slugs: STAFF_ROLE_SLUGS,
          }),
          supabase.rpc("current_user_has_any_role", {
            p_role_slugs: PERFORMANCE_DASHBOARD_ROLE_SLUGS,
          }),
          supabase.rpc("current_user_has_role", {
            p_role_slug: "CANDIDATE",
          }),
          supabase.rpc("current_candidate_id"),
        ]);

        if (
          activeUserResult.error ||
          staffRoleResult.error ||
          performanceDashboardRoleResult.error ||
          candidateRoleResult.error ||
          candidateIdResult.error
        ) {
          throw new Error("Authorization verification failed.");
        }

        const candidateId = normalizeCandidateId(candidateIdResult.data);
        const hasCandidateRole = candidateRoleResult.data === true;
        const isActiveAppUser = activeUserResult.data === true;

        result = {
          isActiveAppUser,
          hasStaffAccess: staffRoleResult.data === true,
          hasPerformanceDashboardAccess:
            isActiveAppUser && performanceDashboardRoleResult.data === true,
          hasCandidateRole,
          candidateId,
          hasCandidateAccess: isActiveAppUser && hasCandidateRole && Boolean(candidateId),
          authorizationError: null,
        };
      } catch {
        result = {
          isActiveAppUser: false,
          hasStaffAccess: false,
          hasPerformanceDashboardAccess: false,
          hasCandidateRole: false,
          candidateId: null,
          hasCandidateAccess: false,
          authorizationError: AUTHORIZATION_ERROR_MESSAGE,
        };
      }

      if (requestId !== requestIdRef.current) {
        return {
          isActiveAppUser: false,
          hasStaffAccess: false,
          hasPerformanceDashboardAccess: false,
          hasCandidateRole: false,
          candidateId: null,
          hasCandidateAccess: false,
          authorizationError: AUTHORIZATION_ERROR_MESSAGE,
        };
      }

      setAuthState({
        session: nextSession,
        user: nextSession.user,
        loading: false,
        ...result,
      });
      completedSessionKeyRef.current = sessionKey;
      authorizationResultRef.current = result;
      return result;
    })();

    inFlightAuthorizationRef.current = {
      key: sessionKey,
      promise: authorizationPromise,
    };

    void authorizationPromise.finally(() => {
      if (inFlightAuthorizationRef.current?.promise === authorizationPromise) {
        inFlightAuthorizationRef.current = null;
      }
    });

    return authorizationPromise;
  }, [updatePasswordRecoveryState]);

  useEffect(() => {
    let isSubscribed = true;

    const initializeSession = async () => {
      const { data, error } = await supabase.auth.getSession();

      if (!isSubscribed) {
        return;
      }

      if (error) {
        requestIdRef.current += 1;
        sessionRef.current = null;
        updatePasswordRecoveryState(false);
        setAuthState({
          ...INITIAL_AUTH_STATE,
          loading: false,
          authorizationError:
            "We could not initialize authentication. Please refresh and try again.",
        });
        return;
      }

      await synchronizeSession(data.session);
    };

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (event === "PASSWORD_RECOVERY") {
        updatePasswordRecoveryState(true);
      } else if (
        event === "SIGNED_OUT" ||
        (event === "SIGNED_IN" && !passwordRecoveryRef.current)
      ) {
        updatePasswordRecoveryState(false);
      }

      void Promise.resolve().then(() => {
        if (isSubscribed) {
          void synchronizeSession(nextSession);
        }
      });
    });

    void initializeSession();

    return () => {
      isSubscribed = false;
      requestIdRef.current += 1;
      inFlightAuthorizationRef.current = null;
      completedSessionKeyRef.current = null;
      authorizationResultRef.current = null;
      subscription.unsubscribe();
    };
  }, [synchronizeSession, updatePasswordRecoveryState]);

  const signIn = useCallback(
    async (email, password) => {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) {
        throw error;
      }

      updatePasswordRecoveryState(false);
      const authorization = await synchronizeSession(data.session);
      return { ...data, ...authorization };
    },
    [synchronizeSession, updatePasswordRecoveryState],
  );

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut();

    if (error) {
      throw error;
    }

    updatePasswordRecoveryState(false);
    await synchronizeSession(null, true);
  }, [synchronizeSession, updatePasswordRecoveryState]);

  const refreshAuthorization = useCallback(
    () => synchronizeSession(sessionRef.current, true),
    [synchronizeSession],
  );

  const requestPasswordReset = useCallback(async (email) => {
    const { data, error } = await supabase.auth.resetPasswordForEmail(
      email.trim(),
      {
        redirectTo: `${window.location.origin}/reset-password`,
      },
    );

    if (error) {
      throw error;
    }

    return data;
  }, []);

  const updatePassword = useCallback(async (newPassword) => {
    const { data, error } = await supabase.auth.updateUser({
      password: newPassword,
    });

    if (error) {
      throw error;
    }

    return data;
  }, []);

  const completePasswordRecovery = useCallback(() => {
    updatePasswordRecoveryState(false);
  }, [updatePasswordRecoveryState]);

  const value = useMemo(
    () => ({
      ...authState,
      isPasswordRecovery,
      signIn,
      signOut,
      refreshAuthorization,
      requestPasswordReset,
      updatePassword,
      completePasswordRecovery,
    }),
    [
      authState,
      completePasswordRecovery,
      isPasswordRecovery,
      refreshAuthorization,
      requestPasswordReset,
      signIn,
      signOut,
      updatePassword,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

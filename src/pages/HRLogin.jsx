import { useState } from "react";
import { LoaderCircle, LockKeyhole, LogIn, LogOut } from "lucide-react";
import { Link, Navigate, useLocation, useNavigate } from "react-router-dom";

import { useAuth } from "../context/authContext";

export default function HRLogin() {
  const navigate = useNavigate();
  const location = useLocation();
  const {
    session,
    loading,
    isActiveAppUser,
    hasStaffAccess,
    hasPerformanceDashboardAccess,
    hasLeadReviewAccess,
    hasCandidateAccess,
    authorizationError,
    signIn,
    signOut,
  } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState("");
  const [logoutLoading, setLogoutLoading] = useState(false);

  const requestedPath = location.state?.from?.pathname || "/";
  const isCandidatePath = requestedPath.startsWith("/portal");
  const isLeadReviewPath = requestedPath.startsWith("/lead-reviews");
  const isPerformancePath = requestedPath.startsWith("/performance-dashboard");

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setFormError("");

    try {
      const result = await signIn(email, password);

      if (
        isPerformancePath &&
        result.isActiveAppUser &&
        result.hasPerformanceDashboardAccess
      ) {
        navigate(requestedPath, { replace: true });
      } else if (
        isLeadReviewPath &&
        result.isActiveAppUser &&
        result.hasLeadReviewAccess
      ) {
        navigate(requestedPath, { replace: true });
      } else if (isCandidatePath && result.hasCandidateAccess) {
        navigate(requestedPath, { replace: true });
      } else if (
        !isCandidatePath &&
        !isLeadReviewPath &&
        !isPerformancePath &&
        result.isActiveAppUser &&
        result.hasStaffAccess
      ) {
        navigate(requestedPath, { replace: true });
      } else if (result.isActiveAppUser && result.hasStaffAccess) {
        navigate("/", { replace: true });
      } else if (
        result.isActiveAppUser &&
        result.hasPerformanceDashboardAccess
      ) {
        navigate("/performance-dashboard", { replace: true });
      } else if (
        result.isActiveAppUser &&
        result.hasLeadReviewAccess
      ) {
        navigate("/lead-reviews", { replace: true });
      } else if (result.hasCandidateAccess) {
        navigate("/portal", { replace: true });
      }
    } catch {
      setFormError(
        "Unable to sign in. Check your email and password and try again.",
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handleLogout = async () => {
    setLogoutLoading(true);
    setFormError("");

    try {
      await signOut();
    } catch {
      setFormError("Unable to log out. Please try again.");
      setLogoutLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="auth-state-screen" role="status" aria-live="polite">
        <LoaderCircle className="auth-spinner" aria-hidden="true" />
        <p>Checking workspace access...</p>
      </div>
    );
  }

  if (session) {
    if (
      isPerformancePath &&
      isActiveAppUser &&
      hasPerformanceDashboardAccess
    ) {
      return <Navigate to={requestedPath} replace />;
    }

    if (
      isLeadReviewPath &&
      isActiveAppUser &&
      hasLeadReviewAccess
    ) {
      return <Navigate to={requestedPath} replace />;
    }

    if (isCandidatePath && hasCandidateAccess) {
      return <Navigate to={requestedPath} replace />;
    }

    if (
      !isCandidatePath &&
      !isLeadReviewPath &&
      !isPerformancePath &&
      isActiveAppUser &&
      hasStaffAccess
    ) {
      return <Navigate to={requestedPath} replace />;
    }

    if (isActiveAppUser && hasStaffAccess) {
      return <Navigate to="/" replace />;
    }

    if (isActiveAppUser && hasPerformanceDashboardAccess) {
      return <Navigate to="/performance-dashboard" replace />;
    }

    if (isActiveAppUser && hasLeadReviewAccess) {
      return <Navigate to="/lead-reviews" replace />;
    }

    if (hasCandidateAccess) {
      return <Navigate to="/portal" replace />;
    }

    let message = "This account does not have access to an available workspace.";

    if (authorizationError) {
      message = authorizationError;
    } else if (!isActiveAppUser) {
      message = "Your application user account is inactive.";
    }

    return (
      <div className="auth-login-page">
        <section className="auth-access-card" aria-labelledby="login-denied-title">
          <LockKeyhole aria-hidden="true" />
          <h1 id="login-denied-title">Access denied</h1>
          <p>{message}</p>
          {formError && (
            <p className="auth-inline-error" role="alert">
              {formError}
            </p>
          )}
          <button
            className="auth-logout-button"
            type="button"
            onClick={handleLogout}
            disabled={logoutLoading}
          >
            <LogOut size={17} aria-hidden="true" />
            {logoutLoading ? "Logging out..." : "Logout"}
          </button>
        </section>
      </div>
    );
  }

  return (
    <div className="auth-login-page">
      <section className="auth-login-card" aria-labelledby="hr-login-title">
        <div className="auth-login-icon" aria-hidden="true">
          <LockKeyhole />
        </div>
        <h1 id="hr-login-title">Workspace Sign In</h1>

        <form className="auth-login-form" onSubmit={handleSubmit}>
          <div className="auth-form-field">
            <label htmlFor="hr-login-email">Email</label>
            <input
              id="hr-login-email"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="email"
              required
              disabled={submitting}
            />
          </div>

          <div className="auth-form-field">
            <label htmlFor="hr-login-password">Password</label>
            <input
              id="hr-login-password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete="current-password"
              required
              disabled={submitting}
            />
          </div>

          <Link className="auth-forgot-link" to="/forgot-password">
            Forgot password?
          </Link>

          {formError && (
            <p className="auth-inline-error" role="alert">
              {formError}
            </p>
          )}

          <button
            className="auth-submit-button"
            type="submit"
            disabled={submitting}
          >
            {submitting ? (
              <LoaderCircle className="auth-spinner" size={18} aria-hidden="true" />
            ) : (
              <LogIn size={18} aria-hidden="true" />
            )}
            {submitting ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </section>
    </div>
  );
}

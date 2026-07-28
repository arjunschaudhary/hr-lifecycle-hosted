import { useState } from "react";
import { LoaderCircle, LogOut, ShieldAlert } from "lucide-react";
import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useAuth } from "../context/authContext";

function LeadReviewAuthLoadingScreen() {
  return (
    <div className="auth-state-screen" role="status" aria-live="polite">
      <LoaderCircle className="auth-spinner" aria-hidden="true" />
      <p>Checking Lead Review workspace access...</p>
    </div>
  );
}

export default function LeadReviewProtectedRoute() {
  const location = useLocation();
  const {
    session,
    user,
    loading,
    isActiveAppUser,
    hasLeadReviewAccess,
    authorizationError,
    signOut,
  } = useAuth();
  const [logoutLoading, setLogoutLoading] = useState(false);
  const [logoutError, setLogoutError] = useState("");

  const handleLogout = async () => {
    setLogoutLoading(true);
    setLogoutError("");

    try {
      await signOut();
    } catch {
      setLogoutError("Unable to log out. Please try again.");
      setLogoutLoading(false);
    }
  };

  if (loading) {
    return <LeadReviewAuthLoadingScreen />;
  }

  if (!session) {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  if (authorizationError || !isActiveAppUser || !hasLeadReviewAccess) {
    let message =
      "Your account does not have access to the Lead Review workspace.";

    if (authorizationError) {
      message = authorizationError;
    } else if (!isActiveAppUser) {
      message = "Your application user account is inactive.";
    }

    return (
      <div className="auth-state-screen">
        <section className="auth-access-card" aria-labelledby="access-denied-title">
          <ShieldAlert aria-hidden="true" />
          <h1 id="access-denied-title">Access denied</h1>
          <p>{message}</p>
          <p className="auth-session-email">
            Signed in as <strong>{user?.email || "Unknown account"}</strong>
          </p>
          {logoutError && (
            <p className="auth-inline-error" role="alert">
              {logoutError}
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
    <div className="auth-protected-shell">
      <header className="auth-session-bar">
        <span className="auth-session-email" title={user?.email}>
          Signed in as <strong>{user?.email || "Unknown account"}</strong>
        </span>
        <button
          className="auth-logout-button auth-logout-button--compact"
          type="button"
          onClick={handleLogout}
          disabled={logoutLoading}
        >
          <LogOut size={16} aria-hidden="true" />
          {logoutLoading ? "Logging out..." : "Logout"}
        </button>
        {logoutError && (
          <span className="auth-session-error" role="alert">
            {logoutError}
          </span>
        )}
      </header>
      <div className="auth-protected-content">
        <Outlet />
      </div>
    </div>
  );
}

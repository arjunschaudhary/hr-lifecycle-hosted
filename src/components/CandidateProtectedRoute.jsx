import { useState } from "react";
import { LoaderCircle, LogOut, ShieldAlert } from "lucide-react";
import { Link, Navigate, Outlet, useLocation } from "react-router-dom";

import { useAuth } from "../context/authContext";

function CandidateAuthLoadingScreen() {
  return (
    <div className="auth-state-screen" role="status" aria-live="polite">
      <LoaderCircle className="auth-spinner" aria-hidden="true" />
      <p>Checking candidate portal access...</p>
    </div>
  );
}

export default function CandidateProtectedRoute() {
  const location = useLocation();
  const {
    session,
    user,
    loading,
    isActiveAppUser,
    hasStaffAccess,
    hasPerformanceDashboardAccess,
    hasLeadReviewAccess,
    hasCandidateAccess,
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
    return <CandidateAuthLoadingScreen />;
  }

  if (!session) {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  if (authorizationError || !isActiveAppUser || !hasCandidateAccess) {
    let message =
      "Your candidate portal account is not active or is not linked to a candidate record.";

    if (authorizationError) {
      message = authorizationError;
    } else if (!isActiveAppUser) {
      message = "Your application user account is inactive.";
    }

    return (
      <div className="auth-login-page">
        <section
          className="auth-access-card"
          aria-labelledby="candidate-access-denied-title"
        >
          <ShieldAlert aria-hidden="true" />
          <h1 id="candidate-access-denied-title">Candidate portal unavailable</h1>
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
        <span>
          Signed in as <strong>{user?.email || "Unknown account"}</strong>
        </span>
        {hasStaffAccess && (
          <Link
            to="/"
            className="auth-logout-button auth-logout-button--compact auth-link-button"
          >
            HR Workspace
          </Link>
        )}
        {hasPerformanceDashboardAccess && (
          <Link
            to="/performance-dashboard"
            className="auth-logout-button auth-logout-button--compact auth-link-button"
          >
            Performance Dashboard
          </Link>
        )}
        {hasLeadReviewAccess && (
          <Link
            to="/lead-reviews"
            className="auth-logout-button auth-logout-button--compact auth-link-button"
          >
            Lead Reviews
          </Link>
        )}
        <button
          className="auth-logout-button auth-logout-button--compact"
          type="button"
          onClick={handleLogout}
          disabled={logoutLoading}
        >
          <LogOut size={17} aria-hidden="true" />
          {logoutLoading ? "Logging out..." : "Logout"}
        </button>
      </header>
      {logoutError && (
        <p className="auth-inline-error auth-shell-error" role="alert">
          {logoutError}
        </p>
      )}
      <div className="auth-protected-content">
        <Outlet />
      </div>
    </div>
  );
}

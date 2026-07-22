import { useState } from "react";
import {
  CircleAlert,
  CircleCheck,
  KeyRound,
  LoaderCircle,
  Save,
} from "lucide-react";
import { Link } from "react-router-dom";

import { useAuth } from "../context/authContext";

export default function ResetPassword() {
  const {
    session,
    loading,
    isPasswordRecovery,
    updatePassword,
    completePasswordRecovery,
    signOut,
  } = useAuth();
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [finishingReset, setFinishingReset] = useState(false);
  const [error, setError] = useState("");
  const [passwordChanged, setPasswordChanged] = useState(false);
  const [logoutWarning, setLogoutWarning] = useState("");

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");

    if (newPassword.length < 8) {
      setError("Password must be at least 8 characters long.");
      return;
    }

    if (newPassword !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setSubmitting(true);

    try {
      await updatePassword(newPassword);
    } catch {
      setError(
        "Unable to change your password. The reset link may be expired; request a new link and try again.",
      );
      setSubmitting(false);
      return;
    }

    setNewPassword("");
    setConfirmPassword("");
    setFinishingReset(true);
    completePasswordRecovery();

    try {
      await signOut();
    } catch {
      setLogoutWarning(
        "Your password was changed, but automatic logout was unsuccessful. Close this browser session before signing in again.",
      );
    }

    setPasswordChanged(true);
    setFinishingReset(false);
    setSubmitting(false);
  };

  if (loading || finishingReset) {
    return (
      <div className="auth-state-screen" role="status" aria-live="polite">
        <LoaderCircle className="auth-spinner" aria-hidden="true" />
        <p>Checking password reset link...</p>
      </div>
    );
  }

  if (passwordChanged) {
    return (
      <div className="auth-login-page">
        <section className="auth-success-card" aria-labelledby="password-changed-title">
          <CircleCheck aria-hidden="true" />
          <h1 id="password-changed-title">Password changed</h1>
          <p>Your password was changed successfully. You can now sign in.</p>
          {logoutWarning && <p role="status">{logoutWarning}</p>}
          <Link className="auth-submit-button auth-link-button" to="/login">
            Go to login
          </Link>
        </section>
      </div>
    );
  }

  if (!session || !isPasswordRecovery) {
    return (
      <div className="auth-login-page">
        <section className="auth-access-card" aria-labelledby="invalid-reset-title">
          <CircleAlert aria-hidden="true" />
          <h1 id="invalid-reset-title">Reset link unavailable</h1>
          <p>This password reset link is expired or invalid.</p>
          <Link className="auth-secondary-link auth-secondary-link--center" to="/forgot-password">
            Request a new reset link
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="auth-login-page">
      <section className="auth-login-card" aria-labelledby="new-password-title">
        <div className="auth-login-icon" aria-hidden="true">
          <KeyRound />
        </div>
        <h1 id="new-password-title">Set new password</h1>

        <form className="auth-login-form auth-reset-form" onSubmit={handleSubmit}>
          <div className="auth-form-field">
            <label htmlFor="new-password">New password</label>
            <input
              id="new-password"
              type="password"
              value={newPassword}
              onChange={(event) => setNewPassword(event.target.value)}
              autoComplete="new-password"
              required
              minLength={8}
              disabled={submitting}
            />
          </div>

          <div className="auth-form-field">
            <label htmlFor="confirm-new-password">Confirm password</label>
            <input
              id="confirm-new-password"
              type="password"
              value={confirmPassword}
              onChange={(event) => setConfirmPassword(event.target.value)}
              autoComplete="new-password"
              required
              minLength={8}
              disabled={submitting}
            />
          </div>

          {error && (
            <p className="auth-inline-error" role="alert">
              {error}
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
              <Save size={18} aria-hidden="true" />
            )}
            {submitting ? "Changing password..." : "Change password"}
          </button>
        </form>
      </section>
    </div>
  );
}

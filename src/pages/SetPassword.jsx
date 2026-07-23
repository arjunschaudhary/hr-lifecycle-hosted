import { useState } from "react";
import {
  CircleAlert,
  CircleCheck,
  KeyRound,
  LoaderCircle,
  Save,
} from "lucide-react";

import { useAuth } from "../context/authContext";

export default function SetPassword() {
  const { session, loading, updatePassword, signOut } = useAuth();
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [setupComplete, setSetupComplete] = useState(false);
  const [logoutWarning, setLogoutWarning] = useState("");

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");
    setLogoutWarning("");

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
      setError("Unable to create your password. Please try again.");
      setSubmitting(false);
      return;
    }

    setNewPassword("");
    setConfirmPassword("");
    setSetupComplete(true);

    try {
      await signOut();
    } catch {
      setLogoutWarning(
        "Automatic sign-out was unsuccessful. Close this browser tab before signing in again.",
      );
    }

    setSubmitting(false);
  };

  if (loading) {
    return (
      <div className="auth-state-screen" role="status" aria-live="polite">
        <LoaderCircle className="auth-spinner" aria-hidden="true" />
        <p>Checking invitation link...</p>
      </div>
    );
  }

  if (setupComplete) {
    return (
      <div className="auth-login-page">
        <section
          className="auth-success-card"
          aria-labelledby="account-setup-complete-title"
        >
          <CircleCheck aria-hidden="true" />
          <h1 id="account-setup-complete-title">Account setup complete</h1>
          <p>Your password has been created successfully.</p>
          <p>
            Candidate portal access will be available from the sign-in page once
            the candidate workspace is enabled.
          </p>
          {logoutWarning && (
            <p className="auth-inline-error" role="status">
              {logoutWarning}
            </p>
          )}
        </section>
      </div>
    );
  }

  if (!session) {
    return (
      <div className="auth-login-page">
        <section
          className="auth-access-card"
          aria-labelledby="invitation-link-unavailable-title"
        >
          <CircleAlert aria-hidden="true" />
          <h1 id="invitation-link-unavailable-title">
            Invitation link unavailable
          </h1>
          <p>This invitation link is invalid or has expired.</p>
          <p>Contact HR to request a new invitation.</p>
        </section>
      </div>
    );
  }

  const errorId = "set-password-error";

  return (
    <div className="auth-login-page">
      <section className="auth-login-card" aria-labelledby="set-password-title">
        <div className="auth-login-icon" aria-hidden="true">
          <KeyRound />
        </div>
        <h1 id="set-password-title">Set your password</h1>

        <form
          className="auth-login-form auth-reset-form"
          onSubmit={handleSubmit}
          aria-busy={submitting}
        >
          <div className="auth-form-field">
            <label htmlFor="set-password-new">New password</label>
            <input
              id="set-password-new"
              type="password"
              value={newPassword}
              onChange={(event) => setNewPassword(event.target.value)}
              autoComplete="new-password"
              minLength={8}
              required
              disabled={submitting}
              aria-invalid={Boolean(error)}
              aria-describedby={error ? errorId : undefined}
            />
          </div>

          <div className="auth-form-field">
            <label htmlFor="set-password-confirm">Confirm password</label>
            <input
              id="set-password-confirm"
              type="password"
              value={confirmPassword}
              onChange={(event) => setConfirmPassword(event.target.value)}
              autoComplete="new-password"
              minLength={8}
              required
              disabled={submitting}
              aria-invalid={Boolean(error)}
              aria-describedby={error ? errorId : undefined}
            />
          </div>

          {error && (
            <p id={errorId} className="auth-inline-error" role="alert">
              {error}
            </p>
          )}

          <button
            className="auth-submit-button"
            type="submit"
            disabled={submitting}
            aria-busy={submitting}
          >
            {submitting ? (
              <LoaderCircle className="auth-spinner" size={18} aria-hidden="true" />
            ) : (
              <Save size={18} aria-hidden="true" />
            )}
            {submitting ? "Creating password..." : "Create password"}
          </button>
        </form>
      </section>
    </div>
  );
}

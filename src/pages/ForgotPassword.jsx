import { useState } from "react";
import { ArrowLeft, KeyRound, LoaderCircle, Send } from "lucide-react";
import { Link } from "react-router-dom";

import { useAuth } from "../context/authContext";

const RESET_REQUEST_SUCCESS_MESSAGE =
  "If an account exists for that email, a password reset link has been sent.";

export default function ForgotPassword() {
  const { requestPasswordReset } = useAuth();
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    setSuccessMessage("");

    try {
      await requestPasswordReset(email);
      setSuccessMessage(RESET_REQUEST_SUCCESS_MESSAGE);
    } catch {
      setError("Unable to request a password reset right now. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="auth-login-page">
      <section className="auth-login-card" aria-labelledby="reset-password-title">
        <div className="auth-login-icon" aria-hidden="true">
          <KeyRound />
        </div>
        <h1 id="reset-password-title">Reset password</h1>

        <form className="auth-login-form" onSubmit={handleSubmit}>
          <div className="auth-form-field">
            <label htmlFor="password-reset-email">Email</label>
            <input
              id="password-reset-email"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="email"
              required
              disabled={submitting}
            />
          </div>

          {error && (
            <p className="auth-inline-error" role="alert">
              {error}
            </p>
          )}

          {successMessage && (
            <p className="auth-success-message" role="status">
              {successMessage}
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
              <Send size={18} aria-hidden="true" />
            )}
            {submitting ? "Sending reset link..." : "Send reset link"}
          </button>
        </form>

        <Link className="auth-secondary-link" to="/login">
          <ArrowLeft size={16} aria-hidden="true" />
          Back to login
        </Link>
      </section>
    </div>
  );
}

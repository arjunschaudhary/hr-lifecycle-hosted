/**
 * ExitErrorState.jsx
 * Error state for the exit form.
 */

import { ShieldAlert } from "lucide-react";

export default function ExitErrorState({ message, onRetry }) {
  return (
    <section
      className="card card-danger"
      role="alert"
      aria-labelledby="exit-error-title"
      style={{ maxWidth: 640, margin: "40px auto", padding: 32, textAlign: "center" }}
    >
      <ShieldAlert size={36} color="#dc2626" aria-hidden="true" style={{ marginBottom: 12 }} />
      <h2 id="exit-error-title" style={{ marginTop: 0 }}>
        Something went wrong
      </h2>
      <p style={{ color: "#64748b", marginBottom: 24 }}>
        {message || "Unable to load the exit questionnaire. Please try again."}
      </p>
      {onRetry && (
        <button className="btn btn-primary" type="button" onClick={onRetry}>
          Retry
        </button>
      )}
    </section>
  );
}

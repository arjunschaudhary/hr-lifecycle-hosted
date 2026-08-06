/**
 * ExitSuccess.jsx
 * Shown after successful questionnaire submission.
 */

import { CheckCircle } from "lucide-react";
import { Link } from "react-router-dom";

export default function ExitSuccess({
  title = "Feedback Submitted",
  message = "Thank you for completing the exit questionnaire. Your responses have been recorded. Our HR team will be in touch if needed.",
  linkText = "← Return to Portal",
  linkPath = "/portal",
}) {
  return (
    <section
      className="card card-success"
      role="status"
      aria-live="polite"
      aria-labelledby="exit-success-title"
      style={{ maxWidth: 560, margin: "60px auto", padding: 40, textAlign: "center" }}
    >
      <CheckCircle
        size={48}
        color="#16a34a"
        aria-hidden="true"
        style={{ marginBottom: 16 }}
      />
      <h1 id="exit-success-title" style={{ marginTop: 0, fontSize: 24 }}>
        {title}
      </h1>
      <p style={{ color: "#64748b", lineHeight: 1.6, marginBottom: 28 }}>
        {message}
      </p>
      <Link className="btn btn-secondary" to={linkPath}>
        {linkText}
      </Link>
    </section>
  );
}

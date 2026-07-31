/**
 * ExitLoading.jsx
 * Loading state for the exit form — reuses .card and .auth-state-screen patterns.
 */

import { LoaderCircle } from "lucide-react";

export default function ExitLoading() {
  return (
    <div className="auth-state-screen" role="status" aria-live="polite">
      <LoaderCircle className="auth-spinner" size={32} aria-hidden="true" />
      <p>Loading your exit questionnaire…</p>
    </div>
  );
}

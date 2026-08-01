/**
 * HRExitSuccess.jsx
 * Dedicated success view shown after HR completes an intern exit evaluation.
 */

import ExitSuccess from "./ExitSuccess";

export default function HRExitSuccess() {
  return (
    <ExitSuccess
      title="HR Exit Evaluation Completed"
      message="The HR evaluation for this intern exit case has been successfully submitted and marked as COMPLETED."
      linkText="← Return to HR Dashboard"
      linkPath="/"
    />
  );
}

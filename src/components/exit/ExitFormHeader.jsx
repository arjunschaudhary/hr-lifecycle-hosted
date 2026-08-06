/**
 * ExitFormHeader.jsx
 * Page-level header for the candidate exit questionnaire.
 * Matches the page-header-modern + page-icon pattern used across the project.
 */

import { ClipboardList } from "lucide-react";

export default function ExitFormHeader() {
  return (
    <header className="page-header-modern">
      <div className="page-icon" aria-hidden="true">
        <ClipboardList size={28} />
      </div>
      <div>
        <h1 className="page-title-modern" style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>
          Exit Questionnaire
        </h1>
        <p className="page-subtitle" style={{ margin: "4px 0 0", color: "#64748b" }}>
          Your responses are confidential and help us improve the intern experience.
        </p>
      </div>
    </header>
  );
}

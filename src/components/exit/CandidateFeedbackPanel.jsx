/**
 * CandidateFeedbackPanel.jsx
 * Read-only collapsible reference panel displaying the candidate's submitted exit questionnaire feedback.
 */

import { useState } from "react";
import { ChevronDown, ChevronUp, FileText, Star, AlertCircle } from "lucide-react";

export default function CandidateFeedbackPanel({ feedback, profile }) {
  const [isOpen, setIsOpen] = useState(true);

  if (!feedback) {
    return (
      <div
        className="card"
        style={{
          marginBottom: 24,
          padding: 16,
          background: "#f8fafc",
          border: "1px solid #e2e8f0",
          borderRadius: 8,
          color: "#64748b",
          fontSize: 14,
        }}
      >
        <p style={{ margin: 0, display: "flex", alignItems: "center", gap: 8 }}>
          <AlertCircle size={16} />
          No candidate exit questionnaire feedback found for this exit case.
        </p>
      </div>
    );
  }

  const formatList = (arr) => (Array.isArray(arr) && arr.length > 0 ? arr.join(", ") : "None");
  const formatValue = (val) => (val !== null && val !== undefined && val !== "" ? String(val) : "—");

  return (
    <div
      className="card"
      style={{
        marginBottom: 24,
        border: "1px solid #cbd5e1",
        borderRadius: 12,
        background: "#ffffff",
        boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
      }}
    >
      <div
        onClick={() => setIsOpen(!isOpen)}
        style={{
          padding: "16px 20px",
          background: "#f1f5f9",
          borderBottom: isOpen ? "1px solid #e2e8f0" : "none",
          borderTopLeftRadius: 12,
          borderTopRightRadius: 12,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          cursor: "pointer",
          userSelect: "none",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <FileText size={20} color="#2563eb" />
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Candidate Exit Feedback Reference ({profile?.fullName || "Candidate"})
          </h3>
          <span
            style={{
              fontSize: 12,
              fontWeight: 600,
              padding: "2px 8px",
              borderRadius: 12,
              background: "#dbeafe",
              color: "#1e40af",
            }}
          >
            Read Only
          </span>
        </div>
        <button
          type="button"
          aria-label={isOpen ? "Collapse feedback" : "Expand feedback"}
          style={{ background: "none", border: "none", cursor: "pointer", color: "#64748b" }}
        >
          {isOpen ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
        </button>
      </div>

      {isOpen && (
        <div style={{ padding: "20px" }}>
          {/* Summary Ratings Grid */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
              gap: 12,
              marginBottom: 20,
              padding: 16,
              background: "#f8fafc",
              borderRadius: 10,
              border: "1px solid #e2e8f0",
            }}
          >
            <div>
              <span style={{ fontSize: 12, color: "#64748b", display: "block" }}>Overall Experience</span>
              <strong style={{ fontSize: 18, color: "#0f172a", display: "flex", alignItems: "center", gap: 4 }}>
                <Star size={16} fill="#f59e0b" color="#f59e0b" />
                {formatValue(feedback.overall_experience_rating)} / 5
              </strong>
            </div>

            <div>
              <span style={{ fontSize: 12, color: "#64748b", display: "block" }}>NPS Recommendation</span>
              <strong style={{ fontSize: 18, color: "#0f172a" }}>
                {formatValue(feedback.nps_score)} / 10
              </strong>
            </div>

            <div>
              <span style={{ fontSize: 12, color: "#64748b", display: "block" }}>Learning Rating</span>
              <strong style={{ fontSize: 18, color: "#0f172a" }}>
                {formatValue(feedback.learning_rating)} / 5
              </strong>
            </div>

            <div>
              <span style={{ fontSize: 12, color: "#64748b", display: "block" }}>Mentorship Guidance</span>
              <strong style={{ fontSize: 18, color: "#0f172a" }}>
                {formatValue(feedback.guidance_rating)} / 5
              </strong>
            </div>
          </div>

          {/* Key Responses Grid */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 16 }}>
            <div>
              <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#64748b", textTransform: "uppercase" }}>
                Exit Context
              </h4>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Completed Full Term:</strong> {feedback.completed_full_duration ? "Yes" : "No"}
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Primary Reason:</strong> {formatValue(feedback.primary_exit_reason)}
              </p>
              {feedback.other_exit_reasons && (
                <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                  <strong>Other Reasons:</strong> {formatList(feedback.other_exit_reasons)}
                </p>
              )}
              {feedback.other_reason_text && (
                <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                  <strong>Reason Details:</strong> {feedback.other_reason_text}
                </p>
              )}
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Preventable Exit:</strong> {formatValue(feedback.preventable_exit)}
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Wanted Extension:</strong> {formatValue(feedback.wanted_extension)}
              </p>
            </div>

            <div>
              <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#64748b", textTransform: "uppercase" }}>
                Mentorship & Team Feedback
              </h4>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Psychological Safety:</strong> {formatValue(feedback.psychological_safety_rating)} / 5
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Valued Contributor:</strong> {formatValue(feedback.valued_contributor_rating)} / 5
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Work Distribution:</strong> {formatValue(feedback.work_distribution_rating)} / 5
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Pod Culture:</strong> {formatValue(feedback.pod_culture_rating)} / 5
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Feedback Frequency:</strong> {formatValue(feedback.feedback_frequency)}
              </p>
            </div>

            <div>
              <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#64748b", textTransform: "uppercase" }}>
                Suggestions & Safety
              </h4>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Rejoin Interest:</strong> {formatValue(feedback.rejoin_interest)}
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>HR Issues:</strong> {formatList(feedback.hr_communication_issues)}
              </p>
              <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                <strong>Improvements Suggested:</strong> {formatList(feedback.improvement_suggestions)}
              </p>
              {feedback.safety_issue === "yes" && (
                <div style={{ marginTop: 8, padding: 8, background: "#fef2f2", borderRadius: 6, border: "1px solid #fca5a5" }}>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "#dc2626" }}>Safety Issue Reported</span>
                  <p style={{ margin: "4px 0 0 0", fontSize: 13, color: "#7f1d1d" }}>
                    {feedback.safety_issue_details || "Confidential safety issue reported."}
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

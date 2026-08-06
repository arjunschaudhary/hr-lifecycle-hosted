/**
 * CandidateFeedbackPanel.jsx
 * Read-only collapsible reference panel displaying the candidate's submitted exit questionnaire feedback.
 */

import { useState } from "react";
import { ChevronDown, ChevronUp, FileText, Star, AlertCircle } from "lucide-react";

export default function CandidateFeedbackPanel({ feedback, profile, handoverItems = [] }) {
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

  // Extract KT details from feedback or handoverItems
  const personBriefed = handoverItems.find((i) => i.successor_name)?.successor_name || "—";
  const docsToTransfer = handoverItems.find((i) => i.transfer_documents)?.transfer_documents || "—";
  const accessRevoke = handoverItems.find((i) => i.access_to_revoke)?.access_to_revoke || "—";
  const timeSensitive = handoverItems.find((i) => i.time_sensitive_notes)?.time_sensitive_notes || "—";
  const repoLinks = handoverItems.find((i) => i.repository_link)?.repository_link || "—";

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
        <div style={{ padding: "20px", display: "flex", flexDirection: "column", gap: 20 }}>
          {/* Section: Personal & Internship Info */}
          <div
            style={{
              padding: 14,
              background: "#f8fafc",
              borderRadius: 8,
              border: "1px solid #e2e8f0",
            }}
          >
            <h4 style={{ margin: "0 0 10px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
              Personal & Internship Info
            </h4>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, fontSize: 14 }}>
              <div>
                <span style={{ color: "#64748b", fontSize: 12, display: "block" }}>Full Name</span>
                <strong>{formatValue(profile?.fullName)}</strong>
              </div>
              <div>
                <span style={{ color: "#64748b", fontSize: 12, display: "block" }}>Email</span>
                <strong>{formatValue(profile?.email)}</strong>
              </div>
              <div>
                <span style={{ color: "#64748b", fontSize: 12, display: "block" }}>Mobile Phone</span>
                <strong>{formatValue(profile?.phone)}</strong>
              </div>
              <div>
                <span style={{ color: "#64748b", fontSize: 12, display: "block" }}>Department / Pod</span>
                <strong>{formatValue(profile?.podName || profile?.department)}</strong>
              </div>
              <div>
                <span style={{ color: "#64748b", fontSize: 12, display: "block" }}>Internship Duration</span>
                <strong>
                  {profile?.internshipDurationMonths
                    ? `${profile.internshipDurationMonths} Month${profile.internshipDurationMonths === 1 ? "" : "s"}`
                    : "—"}
                </strong>
              </div>
            </div>
          </div>

          {/* Summary Ratings Grid */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
              gap: 12,
              padding: 14,
              background: "#f8fafc",
              borderRadius: 8,
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

          {/* Detailed Responses Grid */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 16 }}>
            {/* Column 1: Exit Context & Reason */}
            <div>
              <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                1. Basic Info & Exit Reasons
              </h4>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Completed Full Duration:</strong> {feedback.completed_full_duration ? "Yes, completed full term" : "No, left early"}
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Primary Exit Reason:</strong> {formatValue(feedback.primary_exit_reason)}
              </p>
              {feedback.other_exit_reasons && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>Other Exit Reasons:</strong> {formatList(feedback.other_exit_reasons)}
                </p>
              )}
              {feedback.other_reason_text && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>Other Reason Details:</strong> {feedback.other_reason_text}
                </p>
              )}
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Preventable Exit:</strong> {formatValue(feedback.preventable_exit)}
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Wanted Extension:</strong> {formatValue(feedback.wanted_extension)}
              </p>
              {feedback.extension_reason && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>Extension Reason:</strong> {formatValue(feedback.extension_reason)}
                </p>
              )}
            </div>

            {/* Column 2: Learning & Experience */}
            <div>
              <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                2. Learning, Growth & Experience
              </h4>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Expectation Match:</strong> {formatValue(feedback.expectation_match)}
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Meaningful Work:</strong> {formatValue(feedback.meaningful_work)}
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Missing Exposure:</strong> {formatList(feedback.missing_exposure)}
              </p>
              {feedback.missing_exposure_other && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>Missing Exposure Details:</strong> {feedback.missing_exposure_other}
                </p>
              )}
            </div>

            {/* Column 3: Mentorship & Team Culture */}
            <div>
              <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                3. Mentorship & Pod Culture
              </h4>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Feedback Frequency:</strong> {formatValue(feedback.feedback_frequency)}
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Psychological Safety:</strong> {formatValue(feedback.psychological_safety_rating)} / 5
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Valued Contributor:</strong> {formatValue(feedback.valued_contributor_rating)} / 5
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Work Distribution:</strong> {formatValue(feedback.work_distribution_rating)} / 5
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Pod Culture Rating:</strong> {formatValue(feedback.pod_culture_rating)} / 5
              </p>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Safety Issue Observed:</strong> {formatValue(feedback.safety_issue)}
              </p>
              {feedback.safety_issue === "yes" && (
                <div style={{ marginTop: 6, padding: 8, background: "#fef2f2", borderRadius: 6, border: "1px solid #fca5a5" }}>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "#dc2626" }}>Confidential Safety Details</span>
                  <p style={{ margin: "4px 0 0 0", fontSize: 13, color: "#7f1d1d" }}>
                    {feedback.safety_issue_details || "Confidential safety issue reported."}
                  </p>
                </div>
              )}
              <p style={{ margin: "6px 0 6px 0", fontSize: 14 }}>
                <strong>HR Communication Issues:</strong> {formatList(feedback.hr_communication_issues)}
              </p>
              {feedback.hr_communication_other && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>HR Communication Details:</strong> {feedback.hr_communication_other}
                </p>
              )}
            </div>

            {/* Column 4: Final Open Feedback */}
            <div>
              <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                4. Final Feedback & Rejoin
              </h4>
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Improvement Suggestions:</strong> {formatList(feedback.improvement_suggestions)}
              </p>
              {feedback.improvement_other && (
                <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                  <strong>Improvement Details:</strong> {feedback.improvement_other}
                </p>
              )}
              <p style={{ margin: "0 0 6px 0", fontSize: 14 }}>
                <strong>Rejoin Interest:</strong> {formatValue(feedback.rejoin_interest)}
              </p>
            </div>
          </div>

          {/* Section: Knowledge Transfer & Handover Details */}
          <div
            style={{
              padding: 14,
              background: "#f8fafc",
              borderRadius: 8,
              border: "1px solid #e2e8f0",
            }}
          >
            <h4 style={{ margin: "0 0 10px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
              5. Knowledge Transfer & Handover
            </h4>

            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12, marginBottom: 14, fontSize: 14 }}>
              <div>
                <strong style={{ color: "#64748b", fontSize: 12, display: "block" }}>Person Briefed</strong>
                <span>{personBriefed}</span>
              </div>
              <div>
                <strong style={{ color: "#64748b", fontSize: 12, display: "block" }}>Documents / Files to Transfer</strong>
                <span>{docsToTransfer}</span>
              </div>
              <div>
                <strong style={{ color: "#64748b", fontSize: 12, display: "block" }}>Accounts / Access to Revoke</strong>
                <span>{accessRevoke}</span>
              </div>
              <div>
                <strong style={{ color: "#64748b", fontSize: 12, display: "block" }}>Time-Sensitive Items</strong>
                <span>{timeSensitive}</span>
              </div>
              <div>
                <strong style={{ color: "#64748b", fontSize: 12, display: "block" }}>Repository / Drive Links</strong>
                <span>{repoLinks}</span>
              </div>
            </div>

            {/* Ongoing Tasks Table */}
            <div>
              <strong style={{ color: "#475569", fontSize: 13, display: "block", marginBottom: 6 }}>
                Ongoing Tasks & Projects:
              </strong>
              {handoverItems.length === 0 ? (
                <p style={{ margin: 0, fontSize: 13, color: "#94a3b8", fontStyle: "italic" }}>
                  No individual tasks submitted.
                </p>
              ) : (
                <div style={{ overflowX: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, textAlign: "left" }}>
                    <thead>
                      <tr style={{ background: "#e2e8f0", color: "#334155" }}>
                        <th style={{ padding: "6px 10px" }}>Task / Project Name</th>
                        <th style={{ padding: "6px 10px" }}>Status</th>
                        <th style={{ padding: "6px 10px" }}>Next Steps</th>
                      </tr>
                    </thead>
                    <tbody>
                      {handoverItems.map((item, idx) => (
                        <tr key={idx} style={{ borderBottom: "1px solid #e2e8f0" }}>
                          <td style={{ padding: "6px 10px", fontWeight: 600 }}>{formatValue(item.task_name)}</td>
                          <td style={{ padding: "6px 10px" }}>
                            <span
                              style={{
                                padding: "2px 8px",
                                borderRadius: 4,
                                fontSize: 11,
                                fontWeight: 700,
                                background: item.task_status === "COMPLETED" ? "#dcfce7" : "#fef3c7",
                                color: item.task_status === "COMPLETED" ? "#15803d" : "#b45309",
                              }}
                            >
                              {formatValue(item.task_status)}
                            </span>
                          </td>
                          <td style={{ padding: "6px 10px" }}>{formatValue(item.next_steps)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

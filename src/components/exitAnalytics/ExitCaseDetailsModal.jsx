/**
 * ExitCaseDetailsModal.jsx
 * Modal dialog for inspecting complete historical records of a completed exit case.
 * Renders Section 1 (Candidate Exit Questionnaire) and Section 2 (HR Exit Evaluation) side-by-side or stacked read-only.
 */

import { useEffect, useState } from "react";
import { X, UserCheck, FileText, CheckCircle2, Star, AlertCircle, ShieldAlert } from "lucide-react";
import { getCompletedExitCaseDetails } from "../../services/exitAnalyticsService";
import CandidateFeedbackPanel from "../exit/CandidateFeedbackPanel";
import ExitLoading from "../exit/ExitLoading";
import ExitErrorState from "../exit/ExitErrorState";

export default function ExitCaseDetailsModal({ exitCaseId, onClose }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [data, setData] = useState(null);
  const [activeTab, setActiveTab] = useState("ALL"); // "ALL", "CANDIDATE", "HR"

  useEffect(() => {
    if (!exitCaseId) return;

    let isMounted = true;

    async function loadCaseDetails() {
      try {
        setLoading(true);
        setError("");
        const res = await getCompletedExitCaseDetails(exitCaseId);
        if (isMounted) {
          setData(res);
        }
      } catch (err) {
        if (isMounted) {
          setError(err.message || "Failed to load exit case details.");
        }
      } finally {
        if (isMounted) setLoading(false);
      }
    }

    loadCaseDetails();

    return () => {
      isMounted = false;
    };
  }, [exitCaseId]);

  if (!exitCaseId) return null;

  const formatValue = (val) => (val !== null && val !== undefined && val !== "" ? String(val) : "—");
  const formatList = (arr) => (Array.isArray(arr) && arr.length > 0 ? arr.join(", ") : "None");

  return (
    <div
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: "rgba(15, 23, 42, 0.65)",
        backdropFilter: "blur(4px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 1000,
        padding: 20,
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: "#ffffff",
          borderRadius: 12,
          width: "100%",
          maxWidth: 950,
          maxHeight: "90vh",
          display: "flex",
          flexDirection: "column",
          boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.2)",
          overflow: "hidden",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div
          style={{
            padding: "16px 24px",
            borderBottom: "1px solid #e2e8f0",
            background: "#f8fafc",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <h2 style={{ margin: 0, fontSize: 18, fontWeight: 700, color: "#0f172a" }}>
                Exit Case Record — {data?.profile?.fullName || "Candidate"}
              </h2>
              <span
                style={{
                  fontSize: 12,
                  fontWeight: 700,
                  padding: "2px 8px",
                  borderRadius: 12,
                  background: "#dcfce7",
                  color: "#15803d",
                }}
              >
                COMPLETED
              </span>
            </div>
            <p style={{ margin: "2px 0 0", fontSize: 13, color: "#64748b" }}>
              MID: {data?.profile?.mid || "—"} | Department: {data?.profile?.department || "—"} | Exit Date: {data?.exitCase?.exitDate || "—"}
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            style={{
              background: "none",
              border: "none",
              cursor: "pointer",
              color: "#64748b",
              padding: 4,
              borderRadius: 6,
            }}
            aria-label="Close modal"
          >
            <X size={22} />
          </button>
        </div>

        {/* View Selection Tabs */}
        {!loading && !error && data && (
          <div style={{ padding: "12px 24px 0", borderBottom: "1px solid #e2e8f0", display: "flex", gap: 8 }}>
            <button
              type="button"
              onClick={() => setActiveTab("ALL")}
              style={{
                padding: "8px 16px",
                border: "none",
                borderBottom: activeTab === "ALL" ? "2px solid #2563eb" : "2px solid transparent",
                background: "none",
                color: activeTab === "ALL" ? "#2563eb" : "#64748b",
                fontWeight: activeTab === "ALL" ? 700 : 500,
                fontSize: 14,
                cursor: "pointer",
              }}
            >
              Full Case Record (Both)
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("CANDIDATE")}
              style={{
                padding: "8px 16px",
                border: "none",
                borderBottom: activeTab === "CANDIDATE" ? "2px solid #2563eb" : "2px solid transparent",
                background: "none",
                color: activeTab === "CANDIDATE" ? "#2563eb" : "#64748b",
                fontWeight: activeTab === "CANDIDATE" ? 700 : 500,
                fontSize: 14,
                cursor: "pointer",
              }}
            >
              Section 1: Candidate Questionnaire
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("HR")}
              style={{
                padding: "8px 16px",
                border: "none",
                borderBottom: activeTab === "HR" ? "2px solid #2563eb" : "2px solid transparent",
                background: "none",
                color: activeTab === "HR" ? "#2563eb" : "#64748b",
                fontWeight: activeTab === "HR" ? 700 : 500,
                fontSize: 14,
                cursor: "pointer",
              }}
            >
              Section 2: HR Evaluation
            </button>
          </div>
        )}

        {/* Modal Body Scroll Area */}
        <div style={{ padding: 24, overflowY: "auto", flex: 1, display: "flex", flexDirection: "column", gap: 24 }}>
          {loading && <ExitLoading />}
          {error && <ExitErrorState message={error} onRetry={() => window.location.reload()} />}

          {!loading && !error && data && (
            <>
              {/* SECTION 1 — CANDIDATE EXIT QUESTIONNAIRE */}
              {(activeTab === "ALL" || activeTab === "CANDIDATE") && (
                <div style={{ border: "1px solid #cbd5e1", borderRadius: 10, padding: 16, background: "#fafafa" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, borderBottom: "1px solid #e2e8f0", paddingBottom: 8 }}>
                    <FileText size={20} color="#2563eb" />
                    <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
                      Section 1 — Candidate Exit Questionnaire
                    </h3>
                  </div>

                  <CandidateFeedbackPanel
                    feedback={data.candidateFeedback}
                    profile={data.profile}
                    handoverItems={data.handoverItems}
                  />
                </div>
              )}

              {/* SECTION 2 — HR EXIT EVALUATION */}
              {(activeTab === "ALL" || activeTab === "HR") && (
                <div style={{ border: "1px solid #cbd5e1", borderRadius: 10, padding: 16, background: "#ffffff" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16, borderBottom: "1px solid #e2e8f0", paddingBottom: 8 }}>
                    <UserCheck size={20} color="#16a34a" />
                    <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
                      Section 2 — HR Exit Evaluation
                    </h3>
                  </div>

                  {!data.hrEvaluation ? (
                    <p style={{ margin: 0, fontSize: 14, color: "#64748b", fontStyle: "italic" }}>
                      No HR evaluation data recorded.
                    </p>
                  ) : (
                    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                      {/* Reviewer Details */}
                      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, padding: 12, background: "#f8fafc", borderRadius: 8, border: "1px solid #e2e8f0", fontSize: 13 }}>
                        <div>
                          <span style={{ color: "#64748b", display: "block" }}>Reviewer Name</span>
                          <strong>{formatValue(data.reviewer?.name)}</strong>
                        </div>
                        <div>
                          <span style={{ color: "#64748b", display: "block" }}>Reviewer Role</span>
                          <strong>{formatValue(data.reviewer?.role)}</strong>
                        </div>
                        <div>
                          <span style={{ color: "#64748b", display: "block" }}>Evaluation Date</span>
                          <strong>{formatValue(data.hrEvaluation.submitted_at?.substring(0, 10))}</strong>
                        </div>
                        <div>
                          <span style={{ color: "#64748b", display: "block" }}>Verified By</span>
                          <strong>{formatValue(data.verifier?.name)}</strong>
                        </div>
                      </div>

                      {/* Performance Ratings (1–5) */}
                      <div>
                        <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                          Performance Ratings (1–5)
                        </h4>
                        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: 10 }}>
                          {[
                            { label: "Skill Rating", val: data.hrEvaluation.skill_rating },
                            { label: "Communication", val: data.hrEvaluation.communication_rating },
                            { label: "Ownership", val: data.hrEvaluation.ownership_rating },
                            { label: "Reliability", val: data.hrEvaluation.reliability_rating },
                            { label: "Collaboration", val: data.hrEvaluation.collaboration_rating },
                            { label: "Adaptability", val: data.hrEvaluation.adaptability_rating },
                            { label: "Timeliness", val: data.hrEvaluation.timeliness_rating },
                            { label: "Independence", val: data.hrEvaluation.independence_rating },
                          ].map((item, idx) => (
                            <div key={idx} style={{ padding: "8px 12px", background: "#f1f5f9", borderRadius: 6, fontSize: 13 }}>
                              <span style={{ color: "#64748b", fontSize: 11, display: "block" }}>{item.label}</span>
                              <strong style={{ fontSize: 15, color: "#0f172a" }}>{formatValue(item.val)} / 5</strong>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* Exit Context & Retention */}
                      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 14 }}>
                        <div>
                          <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                            HR Exit Context
                          </h4>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Primary Exit Reason:</strong> {formatValue(data.hrEvaluation.hr_primary_reason)}
                          </p>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Other Reasons:</strong> {formatList(data.hrEvaluation.hr_other_reasons)}
                          </p>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Preventable:</strong> {formatValue(data.hrEvaluation.hr_preventable)}
                          </p>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Retention Attempted:</strong> {data.hrEvaluation.retention_attempt ? "Yes" : "No"}
                          </p>
                          {data.hrEvaluation.retention_notes && (
                            <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                              <strong>Retention Notes:</strong> {data.hrEvaluation.retention_notes}
                            </p>
                          )}
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Extension Offer:</strong> {formatValue(data.hrEvaluation.extension_offer)}
                          </p>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Lead Extension Rec:</strong> {formatValue(data.hrEvaluation.lead_extension_recommendation)}
                          </p>
                        </div>

                        <div>
                          <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                            HR Decision Fields
                          </h4>
                          <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                            <strong>Rehire Eligibility:</strong> {formatValue(data.hrEvaluation.rehire_eligibility)}
                          </p>
                          {data.hrEvaluation.internal_notes && (
                            <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                              <strong>Internal Notes:</strong> {data.hrEvaluation.internal_notes}
                            </p>
                          )}
                          {data.hrEvaluation.candidate_summary && (
                            <p style={{ margin: "0 0 4px 0", fontSize: 14 }}>
                              <strong>Candidate Summary:</strong> {data.hrEvaluation.candidate_summary}
                            </p>
                          )}
                        </div>
                      </div>

                      {/* Knowledge Transfer Verification */}
                      <div style={{ padding: 12, background: "#f8fafc", borderRadius: 8, border: "1px solid #e2e8f0" }}>
                        <h4 style={{ margin: "0 0 6px 0", fontSize: 13, color: "#475569", textTransform: "uppercase", fontWeight: 700 }}>
                          Knowledge Transfer Verification
                        </h4>
                        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 10, fontSize: 14 }}>
                          <p style={{ margin: 0 }}>
                            <strong>Handover Complete:</strong> {formatValue(data.hrEvaluation.handover_complete)}
                          </p>
                          <p style={{ margin: 0 }}>
                            <strong>Handover Method:</strong> {formatList(data.hrEvaluation.handover_method)}
                          </p>
                          <p style={{ margin: 0 }}>
                            <strong>Handover Gaps:</strong> {formatValue(data.hrEvaluation.handover_gap)}
                          </p>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>

        {/* Modal Footer */}
        <div style={{ padding: "12px 24px", borderTop: "1px solid #e2e8f0", background: "#f8fafc", textAlign: "right" }}>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={onClose}
            style={{ padding: "8px 20px", fontSize: 14, fontWeight: 600 }}
          >
            Close Record
          </button>
        </div>
      </div>
    </div>
  );
}

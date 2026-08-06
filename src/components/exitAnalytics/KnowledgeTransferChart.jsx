/**
 * KnowledgeTransferChart.jsx
 * Knowledge Transfer & Handover analytics visualization.
 */

import { FileText, CheckCircle2, AlertCircle, Link, Key, Clock } from "lucide-react";

export default function KnowledgeTransferChart({ knowledgeTransfer = {} }) {
  const {
    completeStatus = { YES: 0, PARTIAL: 0, NO: 0, NOT_APPLICABLE: 0 },
    methodCounts = { live_meeting: 0, whatsapp: 0, email: 0, shared_document: 0, not_done: 0 },
    gapsIdentifiedCount = 0,
    gapsIdentifiedPct = 0,
    verifiedByCount = 0,
    verificationPct = 0,
    totalHrEvaluationsCount = 0,
    totalHrHandoverItems = 0,
    avgHrItemsPerCase = 0,
  } = knowledgeTransfer;

  const METHOD_LABELS = {
    live_meeting: "Live Meeting",
    whatsapp: "WhatsApp",
    email: "Email",
    shared_document: "Shared Document",
    not_done: "Not Done",
    other: "Other",
  };

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#fefce8", color: "#ca8a04", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <FileText size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 7: Knowledge Transfer & Handover (HR Verification)
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            HR-verified handover completion rates, verification status, gaps identified, and handover methods
          </p>
        </div>
      </div>

      {/* Handover Status Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 12, marginBottom: 20 }}>
        <div style={{ padding: 12, borderRadius: 8, background: "#f0fdf4", border: "1px solid #bbf7d0" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "#16a34a" }}>Handover Complete</span>
          <div style={{ fontSize: 20, fontWeight: 800, color: "#15803d", marginTop: 2 }}>
            {completeStatus.YES || 0}
          </div>
        </div>

        <div style={{ padding: 12, borderRadius: 8, background: "#fefce8", border: "1px solid #fef08a" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "#ca8a04" }}>Partial Handover</span>
          <div style={{ fontSize: 20, fontWeight: 800, color: "#a16207", marginTop: 2 }}>
            {completeStatus.PARTIAL || 0}
          </div>
        </div>

        <div style={{ padding: 12, borderRadius: 8, background: "#fef2f2", border: "1px solid #fecaca" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "#dc2626" }}>Incomplete</span>
          <div style={{ fontSize: 20, fontWeight: 800, color: "#b91c1c", marginTop: 2 }}>
            {completeStatus.NO || 0}
          </div>
        </div>

        <div style={{ padding: 12, borderRadius: 8, background: "#f8fafc", border: "1px solid #e2e8f0" }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: "#64748b" }}>Not Applicable</span>
          <div style={{ fontSize: 20, fontWeight: 800, color: "#334155", marginTop: 2 }}>
            {completeStatus.NOT_APPLICABLE || 0}
          </div>
        </div>
      </div>

      {/* Detailed HR Verification Metrics Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 14, marginBottom: 16 }}>
        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <CheckCircle2 size={20} style={{ color: "#16a34a" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>HR Verification Rate</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{verificationPct}% ({verifiedByCount} verified)</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <AlertCircle size={20} style={{ color: "#eab308" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Gaps Identified Rate</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{gapsIdentifiedPct}% ({gapsIdentifiedCount} cases)</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <FileText size={20} style={{ color: "#3b82f6" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Avg HR Handover Items</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{avgHrItemsPerCase} items / case</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <Clock size={20} style={{ color: "#8b5cf6" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Total HR Evaluated Cases</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{totalHrEvaluationsCount} cases</div>
          </div>
        </div>
      </div>

      {/* Handover Methods Distribution */}
      <div>
        <h4 style={{ margin: "0 0 8px 0", fontSize: 13, color: "#475569", fontWeight: 700 }}>
          HR Verified Handover Methods
        </h4>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
          {Object.keys(METHOD_LABELS).map((mKey) => (
            <div
              key={mKey}
              style={{
                padding: "6px 12px",
                borderRadius: 6,
                background: "#f1f5f9",
                border: "1px solid #cbd5e1",
                fontSize: 13,
                color: "#334155",
                display: "flex",
                alignItems: "center",
                gap: 6,
              }}
            >
              <span style={{ fontWeight: 600 }}>{METHOD_LABELS[mKey]}:</span>
              <strong style={{ color: "#0f172a" }}>{methodCounts[mKey] || 0}</strong>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

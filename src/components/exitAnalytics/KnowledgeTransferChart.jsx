/**
 * KnowledgeTransferChart.jsx
 * Knowledge Transfer & Handover analytics visualization.
 */

import { FileText, CheckCircle2, AlertCircle, Link, Key, Clock } from "lucide-react";

export default function KnowledgeTransferChart({ knowledgeTransfer = {} }) {
  const {
    completeStatus = { YES: 0, PARTIAL: 0, NO: 0, NOT_APPLICABLE: 0 },
    avgOngoingTasks = 0,
    peopleBriefedPct = 0,
    repoLinkPct = 0,
    accessRevocationPct = 0,
    timeSensitivePct = 0,
  } = knowledgeTransfer;

  const totalStatusCount = Object.values(completeStatus).reduce((a, b) => a + b, 0);

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#fefce8", color: "#ca8a04", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <FileText size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 7: Knowledge Transfer & Handover
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Handover completion rates and candidate documentation metrics
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

      {/* Detailed Metrics Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 14 }}>
        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <CheckCircle2 size={20} style={{ color: "#3b82f6" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Avg Ongoing Tasks</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{avgOngoingTasks} tasks / exit</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <FileText size={20} style={{ color: "#10b981" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>People Briefed %</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{peopleBriefedPct}%</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <Link size={20} style={{ color: "#8b5cf6" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Repo Link Provided %</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{repoLinkPct}%</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <Key size={20} style={{ color: "#f59e0b" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Access Revocation %</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{accessRevocationPct}%</div>
          </div>
        </div>

        <div style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#ffffff", display: "flex", alignItems: "center", gap: 12 }}>
          <Clock size={20} style={{ color: "#ef4444" }} />
          <div>
            <div style={{ fontSize: 12, color: "#64748b", fontWeight: 600 }}>Time Sensitive Tasks %</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: "#1e293b" }}>{timeSensitivePct}%</div>
          </div>
        </div>
      </div>
    </div>
  );
}

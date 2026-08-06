/**
 * NPSSummary.jsx
 * Net Promoter Score breakdown component.
 */

import { TrendingUp, Smile, Meh, Frown } from "lucide-react";

export default function NPSSummary({ npsSummary = {} }) {
  const {
    averageNps = 0,
    netNpsScore = 0,
    promoters = 0,
    passives = 0,
    detractors = 0,
    promoterPct = 0,
    passivePct = 0,
    detractorPct = 0,
    totalResponses = 0,
  } = npsSummary;

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{ width: 32, height: 32, borderRadius: 6, background: "#ecfeff", color: "#06b6d4", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <TrendingUp size={18} />
          </div>
          <div>
            <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
              Section 4: Net Promoter Score (NPS)
            </h3>
            <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
              Likelihood to recommend interning at the organization
            </p>
          </div>
        </div>
        <span className="badge badge-primary" style={{ fontSize: 12 }}>
          {totalResponses} Total Responses
        </span>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 16, marginBottom: 20 }}>
        {/* Net NPS Badge */}
        <div style={{ padding: 16, borderRadius: 8, background: "#f8fafc", border: "1px solid #e2e8f0", textAlign: "center" }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: "#64748b" }}>Net NPS Score</span>
          <div style={{ fontSize: 28, fontWeight: 800, color: netNpsScore >= 0 ? "#16a34a" : "#dc2626", marginTop: 4 }}>
            {netNpsScore > 0 ? `+${netNpsScore}` : netNpsScore}
          </div>
        </div>

        {/* Avg Score */}
        <div style={{ padding: 16, borderRadius: 8, background: "#f8fafc", border: "1px solid #e2e8f0", textAlign: "center" }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: "#64748b" }}>Average Rating</span>
          <div style={{ fontSize: 28, fontWeight: 800, color: "#0284c7", marginTop: 4 }}>
            {averageNps} / 10
          </div>
        </div>
      </div>

      {/* Breakdown Bar */}
      <div style={{ height: 16, borderRadius: 8, overflow: "hidden", display: "flex", marginBottom: 16, background: "#e2e8f0" }}>
        <div style={{ width: `${promoterPct}%`, background: "#22c55e", transition: "width 0.4s ease" }} title={`Promoters: ${promoterPct}%`} />
        <div style={{ width: `${passivePct}%`, background: "#eab308", transition: "width 0.4s ease" }} title={`Passives: ${passivePct}%`} />
        <div style={{ width: `${detractorPct}%`, background: "#ef4444", transition: "width 0.4s ease" }} title={`Detractors: ${detractorPct}%`} />
      </div>

      {/* Breakdown Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 12 }}>
        <div style={{ padding: 12, borderRadius: 8, border: "1px solid #bbf7d0", background: "#f0fdf4", display: "flex", alignItems: "center", gap: 10 }}>
          <Smile size={24} style={{ color: "#16a34a" }} />
          <div>
            <div style={{ fontSize: 12, fontWeight: 700, color: "#16a34a" }}>Promoters (9-10)</div>
            <div style={{ fontSize: 16, fontWeight: 800, color: "#15803d" }}>{promoters} ({promoterPct}%)</div>
          </div>
        </div>

        <div style={{ padding: 12, borderRadius: 8, border: "1px solid #fef08a", background: "#fefce8", display: "flex", alignItems: "center", gap: 10 }}>
          <Meh size={24} style={{ color: "#ca8a04" }} />
          <div>
            <div style={{ fontSize: 12, fontWeight: 700, color: "#ca8a04" }}>Passives (7-8)</div>
            <div style={{ fontSize: 16, fontWeight: 800, color: "#a16207" }}>{passives} ({passivePct}%)</div>
          </div>
        </div>

        <div style={{ padding: 12, borderRadius: 8, border: "1px solid #fecaca", background: "#fef2f2", display: "flex", alignItems: "center", gap: 10 }}>
          <Frown size={24} style={{ color: "#dc2626" }} />
          <div>
            <div style={{ fontSize: 12, fontWeight: 700, color: "#dc2626" }}>Detractors (0-6)</div>
            <div style={{ fontSize: 16, fontWeight: 800, color: "#b91c1c" }}>{detractors} ({detractorPct}%)</div>
          </div>
        </div>
      </div>
    </div>
  );
}

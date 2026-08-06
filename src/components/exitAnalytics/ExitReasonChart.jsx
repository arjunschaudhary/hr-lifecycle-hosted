/**
 * ExitReasonChart.jsx
 * Bar Chart visualization for Candidate Primary Exit Reasons.
 */

import { HelpCircle } from "lucide-react";

export default function ExitReasonChart({ exitReasons = [] }) {
  const maxCount = Math.max(...exitReasons.map((r) => r.count), 1);
  const totalExitsWithReasons = exitReasons.reduce((acc, curr) => acc + curr.count, 0);

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 1: Primary Exit Reasons
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Distribution of candidate reported exit drivers
          </p>
        </div>
        <span className="badge badge-primary" style={{ fontSize: 12 }}>
          {totalExitsWithReasons} Responses
        </span>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {exitReasons.map((item) => {
          const pct = Math.round((item.count / maxCount) * 100);
          const sharePct = totalExitsWithReasons > 0 ? Math.round((item.count / totalExitsWithReasons) * 100) : 0;

          return (
            <div key={item.key} style={{ display: "grid", gridTemplateColumns: "160px 1fr 60px", alignItems: "center", gap: 12 }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#334155", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>
                {item.label}
              </span>
              <div style={{ background: "#f1f5f9", height: 22, borderRadius: 6, overflow: "hidden", position: "relative" }}>
                <div
                  style={{
                    width: `${pct}%`,
                    height: "100%",
                    backgroundColor: item.count > 0 ? "#3b82f6" : "#cbd5e1",
                    borderRadius: 6,
                    transition: "width 0.4s ease",
                  }}
                />
              </div>
              <div style={{ textAlign: "right", fontSize: 13, fontWeight: 700, color: item.count > 0 ? "#1e293b" : "#94a3b8" }}>
                {item.count} <span style={{ fontSize: 11, fontWeight: 400, color: "#64748b" }}>({sharePct}%)</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

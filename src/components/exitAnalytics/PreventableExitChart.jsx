/**
 * PreventableExitChart.jsx
 * Preventable Exit Analysis visualization.
 */

import { AlertTriangle } from "lucide-react";

export default function PreventableExitChart({ preventableData = [] }) {
  const totalCount = preventableData.reduce((acc, curr) => acc + curr.count, 0);
  const maxCount = Math.max(...preventableData.map((d) => d.count), 1);

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#fef2f2", color: "#ef4444", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <AlertTriangle size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 5: Preventable Exits
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Could these intern exits have been prevented by the organization?
          </p>
        </div>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        {preventableData.map((item) => {
          const pct = Math.round((item.count / maxCount) * 100);
          const sharePct = totalCount > 0 ? Math.round((item.count / totalCount) * 100) : 0;

          return (
            <div key={item.key} style={{ display: "grid", gridTemplateColumns: "140px 1fr 65px", alignItems: "center", gap: 12 }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#334155" }}>
                {item.label}
              </span>
              <div style={{ background: "#f1f5f9", height: 20, borderRadius: 6, overflow: "hidden" }}>
                <div
                  style={{
                    width: `${pct}%`,
                    height: "100%",
                    backgroundColor: item.color,
                    borderRadius: 6,
                    transition: "width 0.4s ease",
                  }}
                />
              </div>
              <div style={{ textAlign: "right", fontSize: 13, fontWeight: 700, color: "#1e293b" }}>
                {item.count} <span style={{ fontSize: 11, fontWeight: 400, color: "#64748b" }}>({sharePct}%)</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

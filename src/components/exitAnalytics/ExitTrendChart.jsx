/**
 * ExitTrendChart.jsx
 * Monthly Exit Trend Chart visualization.
 */

import { Calendar } from "lucide-react";

export default function ExitTrendChart({ exitTrend = [] }) {
  const maxCount = Math.max(...exitTrend.map((t) => t.count), 1);

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#eff6ff", color: "#3b82f6", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Calendar size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 2: Monthly Exit Trend
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Volume of intern exits recorded per month
          </p>
        </div>
      </div>

      {exitTrend.length === 0 ? (
        <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", textAlign: "center", padding: "20px 0" }}>
          No monthly trend data available for selected filters.
        </p>
      ) : (
        <div style={{ display: "flex", alignItems: "flex-end", gap: 16, height: 180, paddingTop: 20, paddingBottom: 10, borderBottom: "1px solid #e2e8f0", overflowX: "auto" }}>
          {exitTrend.map((item) => {
            const heightPct = Math.round((item.count / maxCount) * 100);

            return (
              <div key={item.month} style={{ flex: 1, minWidth: 44, display: "flex", flexDirection: "column", alignItems: "center", height: "100%", justifyContent: "flex-end" }}>
                <span style={{ fontSize: 12, fontWeight: 700, color: "#1e293b", marginBottom: 4 }}>
                  {item.count}
                </span>
                <div
                  style={{
                    width: "100%",
                    maxWidth: 36,
                    height: `${Math.max(heightPct, 8)}%`,
                    backgroundColor: "#3b82f6",
                    borderRadius: "6px 6px 0 0",
                    transition: "height 0.3s ease",
                  }}
                />
                <span style={{ fontSize: 11, fontWeight: 600, color: "#64748b", marginTop: 8, whiteSpace: "nowrap" }}>
                  {item.month}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

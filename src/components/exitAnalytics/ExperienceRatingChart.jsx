/**
 * ExperienceRatingChart.jsx
 * Average candidate experience ratings display.
 */

import { Star } from "lucide-react";

export default function ExperienceRatingChart({ experienceRatings = [] }) {
  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#f5f3ff", color: "#8b5cf6", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Star size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 3: Experience & Culture Ratings
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Average intern feedback scores across key workplace experience dimensions (out of 5)
          </p>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 14 }}>
        {experienceRatings.map((item, idx) => {
          const ratingNum = parseFloat(item.rating) || 0;
          const pct = Math.round((ratingNum / 5) * 100);

          return (
            <div key={idx} style={{ padding: 14, border: "1px solid #e2e8f0", borderRadius: 8, background: "#f8fafc" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
                <span style={{ fontSize: 13, fontWeight: 600, color: "#334155" }}>
                  {item.label}
                </span>
                <span style={{ fontSize: 14, fontWeight: 800, color: "#8b5cf6" }}>
                  {ratingNum} / 5
                </span>
              </div>
              <div style={{ background: "#cbd5e1", height: 10, borderRadius: 5, overflow: "hidden" }}>
                <div
                  style={{
                    width: `${pct}%`,
                    height: "100%",
                    backgroundColor: "#8b5cf6",
                    borderRadius: 5,
                    transition: "width 0.4s ease",
                  }}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

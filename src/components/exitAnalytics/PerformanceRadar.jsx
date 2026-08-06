/**
 * PerformanceRadar.jsx
 * Radar chart / 8-Dimension Performance Rating visualization.
 */

import { Award } from "lucide-react";

export default function PerformanceRadar({ performanceDimensions = [] }) {
  // Compute SVG coordinates for Radar Chart
  const numAxes = performanceDimensions.length || 8;
  const radius = 100;
  const centerX = 140;
  const centerY = 140;

  // Calculate polygon points
  const points = performanceDimensions.map((d, index) => {
    const angle = (Math.PI * 2 * index) / numAxes - Math.PI / 2;
    const scorePct = (d.score || 0) / 5;
    const r = radius * scorePct;
    const x = centerX + r * Math.cos(angle);
    const y = centerY + r * Math.sin(angle);
    return `${x},${y}`;
  }).join(" ");

  // Calculate grid rings (1 to 5)
  const rings = [0.2, 0.4, 0.6, 0.8, 1.0];

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#ecfdf5", color: "#10b981", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Award size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 6: Performance Evaluation Ratings
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            HR evaluation scores across 8 core intern competency dimensions (out of 5)
          </p>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 20, alignItems: "center" }}>
        {/* SVG Radar Chart */}
        <div style={{ display: "flex", justifyContent: "center" }}>
          <svg width="280" height="280" viewBox="0 0 280 280">
            {/* Background Grid Rings */}
            {rings.map((ringScale, idx) => (
              <polygon
                key={idx}
                points={performanceDimensions.map((_, i) => {
                  const angle = (Math.PI * 2 * i) / numAxes - Math.PI / 2;
                  const r = radius * ringScale;
                  return `${centerX + r * Math.cos(angle)},${centerY + r * Math.sin(angle)}`;
                }).join(" ")}
                fill="none"
                stroke="#e2e8f0"
                strokeWidth="1"
              />
            ))}

            {/* Axes Lines */}
            {performanceDimensions.map((_, i) => {
              const angle = (Math.PI * 2 * i) / numAxes - Math.PI / 2;
              const x2 = centerX + radius * Math.cos(angle);
              const y2 = centerY + radius * Math.sin(angle);
              return (
                <line
                  key={i}
                  x1={centerX}
                  y1={centerY}
                  x2={x2}
                  y2={y2}
                  stroke="#cbd5e1"
                  strokeWidth="1"
                />
              );
            })}

            {/* Filled Radar Polygon */}
            {points && (
              <polygon
                points={points}
                fill="rgba(16, 185, 129, 0.25)"
                stroke="#10b981"
                strokeWidth="2.5"
              />
            )}

            {/* Data Point Dots */}
            {performanceDimensions.map((d, i) => {
              const angle = (Math.PI * 2 * i) / numAxes - Math.PI / 2;
              const scorePct = (d.score || 0) / 5;
              const r = radius * scorePct;
              const cx = centerX + r * Math.cos(angle);
              const cy = centerY + r * Math.sin(angle);
              return (
                <circle
                  key={i}
                  cx={cx}
                  cy={cy}
                  r="4"
                  fill="#10b981"
                  stroke="#ffffff"
                  strokeWidth="1.5"
                />
              );
            })}
          </svg>
        </div>

        {/* Dimension Score List */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          {performanceDimensions.map((dim, idx) => (
            <div key={idx} style={{ padding: 10, border: "1px solid #e2e8f0", borderRadius: 8, background: "#f8fafc", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#334155" }}>
                {dim.dimension}
              </span>
              <span style={{ fontSize: 14, fontWeight: 800, color: "#059669" }}>
                {dim.score} / 5
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

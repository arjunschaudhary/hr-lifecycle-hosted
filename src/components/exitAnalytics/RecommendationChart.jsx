/**
 * RecommendationChart.jsx
 * HR Certificate and LOR recommendation stats.
 */

import { Award, FileCheck } from "lucide-react";
import RehireEligibilityChart from "./RehireEligibilityChart";

export default function RecommendationChart({ recommendations = {} }) {
  const { certificate = {}, lor = {}, rehire = {} } = recommendations;

  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#f5f3ff", color: "#8b5cf6", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Award size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 9: Exit Recommendations & Rehire
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            HR evaluation outcomes for Internship Certificates, LORs, and Rehire Eligibility
          </p>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 16 }}>
        {/* Certificate Recommendations */}
        <div className="card" style={{ padding: 18 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
            <Award size={18} style={{ color: "#8b5cf6" }} />
            <h4 style={{ margin: 0, fontSize: 14, fontWeight: 700, color: "#1e293b" }}>
              Certificate Recommendation
            </h4>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div style={{ padding: 10, borderRadius: 6, background: "#f0fdf4", border: "1px solid #bbf7d0", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#16a34a" }}>Recommended</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#15803d" }}>{certificate.YES || 0}</span>
            </div>
            <div style={{ padding: 10, borderRadius: 6, background: "#fefce8", border: "1px solid #fef08a", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#ca8a04" }}>Conditional</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#a16207" }}>{certificate.CONDITIONAL || 0}</span>
            </div>
            <div style={{ padding: 10, borderRadius: 6, background: "#fef2f2", border: "1px solid #fecaca", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#dc2626" }}>Rejected</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#b91c1c" }}>{certificate.NO || 0}</span>
            </div>
          </div>
        </div>

        {/* LOR Recommendations */}
        <div className="card" style={{ padding: 18 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
            <FileCheck size={18} style={{ color: "#06b6d4" }} />
            <h4 style={{ margin: 0, fontSize: 14, fontWeight: 700, color: "#1e293b" }}>
              LOR Recommendation
            </h4>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div style={{ padding: 10, borderRadius: 6, background: "#f0fdf4", border: "1px solid #bbf7d0", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#16a34a" }}>Recommended</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#15803d" }}>{lor.YES || 0}</span>
            </div>
            <div style={{ padding: 10, borderRadius: 6, background: "#fefce8", border: "1px solid #fef08a", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#ca8a04" }}>Conditional</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#a16207" }}>{lor.CONDITIONAL || 0}</span>
            </div>
            <div style={{ padding: 10, borderRadius: 6, background: "#fef2f2", border: "1px solid #fecaca", display: "flex", justifyContent: "space-between" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#dc2626" }}>Rejected</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: "#b91c1c" }}>{lor.NO || 0}</span>
            </div>
          </div>
        </div>

        {/* Rehire Eligibility */}
        <RehireEligibilityChart rehireData={rehire} />
      </div>
    </div>
  );
}

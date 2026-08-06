/**
 * RehireEligibilityChart.jsx
 * Visualizes Rehire Eligibility counts.
 */

import { UserCheck } from "lucide-react";

export default function RehireEligibilityChart({ rehireData = { YES: 0, MAYBE: 0, NO: 0 } }) {
  const total = (rehireData.YES || 0) + (rehireData.MAYBE || 0) + (rehireData.NO || 0);

  return (
    <div className="card" style={{ padding: 18 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
        <UserCheck size={18} style={{ color: "#3b82f6" }} />
        <h4 style={{ margin: 0, fontSize: 14, fontWeight: 700, color: "#1e293b" }}>
          Rehire Eligibility Breakdown
        </h4>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <div style={{ padding: 10, borderRadius: 6, background: "#f0fdf4", border: "1px solid #bbf7d0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: "#16a34a" }}>Eligible for Rehire (Yes)</span>
          <span style={{ fontSize: 16, fontWeight: 800, color: "#15803d" }}>{rehireData.YES || 0}</span>
        </div>
        <div style={{ padding: 10, borderRadius: 6, background: "#fefce8", border: "1px solid #fef08a", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: "#ca8a04" }}>Conditional (Maybe)</span>
          <span style={{ fontSize: 16, fontWeight: 800, color: "#a16207" }}>{rehireData.MAYBE || 0}</span>
        </div>
        <div style={{ padding: 10, borderRadius: 6, background: "#fef2f2", border: "1px solid #fecaca", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: "#dc2626" }}>Not Eligible (No)</span>
          <span style={{ fontSize: 16, fontWeight: 800, color: "#b91c1c" }}>{rehireData.NO || 0}</span>
        </div>
      </div>
    </div>
  );
}

/**
 * DepartmentBreakdown.jsx
 * Per-department analytics summary table.
 */

import { Building2 } from "lucide-react";

export default function DepartmentBreakdown({ departmentAnalytics = [] }) {
  return (
    <div className="card" style={{ padding: 20, marginBottom: 24 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ width: 32, height: 32, borderRadius: 6, background: "#f1f5f9", color: "#475569", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Building2 size={18} />
        </div>
        <div>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
            Section 8: Department / Pod Breakdown
          </h3>
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
            Comparative exit metrics across pods and functional departments
          </p>
        </div>
      </div>

      {departmentAnalytics.length === 0 ? (
        <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", textAlign: "center", padding: "16px 0" }}>
          No department data available.
        </p>
      ) : (
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>Department / Pod</th>
                <th>Total Exits</th>
                <th>Avg Experience</th>
                <th>Avg Performance</th>
                <th>Avg NPS</th>
                <th>Preventable Exit %</th>
              </tr>
            </thead>
            <tbody>
              {departmentAnalytics.map((dept, idx) => (
                <tr key={idx}>
                  <td>
                    <strong>{dept.department}</strong>
                  </td>
                  <td>{dept.totalExits}</td>
                  <td>
                    <span style={{ fontWeight: 600, color: "#8b5cf6" }}>
                      {dept.avgExperience} / 5
                    </span>
                  </td>
                  <td>
                    <span style={{ fontWeight: 600, color: "#059669" }}>
                      {dept.avgPerformance} / 5
                    </span>
                  </td>
                  <td>
                    <span style={{ fontWeight: 600, color: "#0284c7" }}>
                      {dept.avgNps} / 10
                    </span>
                  </td>
                  <td>
                    <span className={`badge ${dept.preventablePct > 50 ? "badge-warning" : "badge-success"}`}>
                      {dept.preventablePct}%
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

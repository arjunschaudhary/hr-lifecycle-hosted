/**
 * AnalyticsFilters.jsx
 * Filter bar at top of Exit Analytics page.
 */

import { Filter, RotateCcw } from "lucide-react";

export default function AnalyticsFilters({
  filters,
  allDepartments = [],
  onFilterChange,
  onResetFilters,
}) {
  const handleChange = (field, value) => {
    onFilterChange({ ...filters, [field]: value });
  };

  return (
    <div className="card" style={{ marginBottom: 24, padding: 18 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, fontWeight: 700, fontSize: 15, color: "#1e293b" }}>
          <Filter size={18} style={{ color: "#3b82f6" }} />
          <span>Analytics Filters</span>
        </div>
        <button
          type="button"
          onClick={onResetFilters}
          className="btn btn-secondary"
          style={{ fontSize: 12, padding: "5px 10px", display: "flex", alignItems: "center", gap: 4 }}
        >
          <RotateCcw size={14} /> Reset Filters
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 14 }}>
        {/* Department / Pod */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Department / Pod
          </label>
          <select
            value={filters.department || "ALL"}
            onChange={(e) => handleChange("department", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          >
            <option value="ALL">All Departments</option>
            {allDepartments.map((dept) => (
              <option key={dept} value={dept}>
                {dept}
              </option>
            ))}
          </select>
        </div>

        {/* Exit Type */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Exit Type
          </label>
          <select
            value={filters.exitType || "ALL"}
            onChange={(e) => handleChange("exitType", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          >
            <option value="ALL">All Exit Types</option>
            <option value="COMPLETED_TERM">Completed Term</option>
            <option value="EARLY_EXIT">Early Exit</option>
            <option value="TERMINATED">Terminated</option>
          </select>
        </div>

        {/* Start Date */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Start Date
          </label>
          <input
            type="date"
            value={filters.startDate || ""}
            onChange={(e) => handleChange("startDate", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          />
        </div>

        {/* End Date */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            End Date
          </label>
          <input
            type="date"
            value={filters.endDate || ""}
            onChange={(e) => handleChange("endDate", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          />
        </div>

        {/* Overall Status */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Overall Status
          </label>
          <select
            value={filters.overallStatus || "ALL"}
            onChange={(e) => handleChange("overallStatus", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          >
            <option value="ALL">All Statuses</option>
            <option value="INITIATED">Initiated</option>
            <option value="CANDIDATE_PENDING">Candidate Pending</option>
            <option value="HR_PENDING">HR Pending</option>
            <option value="COMPLETED">Completed</option>
          </select>
        </div>

        {/* Completed Internship */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Completed Term?
          </label>
          <select
            value={filters.completedInternship || "ALL"}
            onChange={(e) => handleChange("completedInternship", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          >
            <option value="ALL">All</option>
            <option value="yes">Yes</option>
            <option value="no">No</option>
          </select>
        </div>

        {/* Rehire Eligibility */}
        <div>
          <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "#64748b", marginBottom: 4 }}>
            Rehire Eligible
          </label>
          <select
            value={filters.rehireEligibility || "ALL"}
            onChange={(e) => handleChange("rehireEligibility", e.target.value)}
            style={{ width: "100%", padding: "8px 10px", borderRadius: 6, border: "1px solid #cbd5e1", fontSize: 13 }}
          >
            <option value="ALL">All</option>
            <option value="YES">Yes</option>
            <option value="MAYBE">Maybe</option>
            <option value="NO">No</option>
          </select>
        </div>
      </div>
    </div>
  );
}

/**
 * EmptyAnalyticsState.jsx
 * Displayed when no exit data exists or filters return no results.
 */

import { BarChart2 } from "lucide-react";

export default function EmptyAnalyticsState({ onResetFilters }) {
  return (
    <div
      className="card"
      style={{
        padding: 48,
        textAlign: "center",
        margin: "24px 0",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          width: 64,
          height: 64,
          borderRadius: "50%",
          background: "#f1f5f9",
          color: "#94a3b8",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          marginBottom: 16,
        }}
      >
        <BarChart2 size={32} />
      </div>

      <h3 style={{ margin: "0 0 8px 0", fontSize: 18, fontWeight: 700, color: "#1e293b" }}>
        No Exit Analytics Data Found
      </h3>

      <p style={{ margin: "0 0 20px 0", fontSize: 14, color: "#64748b", maxWidth: 460 }}>
        There are no exit records matching your current filter selections, or no intern exit processes have been initiated yet.
      </p>

      {onResetFilters && (
        <button type="button" className="btn btn-primary" onClick={onResetFilters}>
          Reset All Filters
        </button>
      )}
    </div>
  );
}

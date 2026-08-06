/**
 * ExitAnalytics.jsx
 * HR Exit Analytics Dashboard Page.
 * Visualizes descriptive exit data using modular charts, cards, and tables.
 */

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { BarChart3, RefreshCw, Eye } from "lucide-react";

import { getExitAnalyticsData } from "../services/exitAnalyticsService";

import AnalyticsFilters from "../components/exitAnalytics/AnalyticsFilters";
import AnalyticsSummaryCards from "../components/exitAnalytics/AnalyticsSummaryCards";
import ExitReasonChart from "../components/exitAnalytics/ExitReasonChart";
import ExitTrendChart from "../components/exitAnalytics/ExitTrendChart";
import ExperienceRatingChart from "../components/exitAnalytics/ExperienceRatingChart";
import NPSSummary from "../components/exitAnalytics/NPSSummary";
import PreventableExitChart from "../components/exitAnalytics/PreventableExitChart";
import PerformanceRadar from "../components/exitAnalytics/PerformanceRadar";
import KnowledgeTransferChart from "../components/exitAnalytics/KnowledgeTransferChart";
import DepartmentBreakdown from "../components/exitAnalytics/DepartmentBreakdown";
import ExitCaseDetailsModal from "../components/exitAnalytics/ExitCaseDetailsModal";
import EmptyAnalyticsState from "../components/exitAnalytics/EmptyAnalyticsState";
import ExitLoading from "../components/exit/ExitLoading";
import ExitErrorState from "../components/exit/ExitErrorState";

const INITIAL_FILTERS = {
  department: "ALL",
  exitType: "ALL",
  startDate: "",
  endDate: "",
  overallStatus: "ALL",
  completedInternship: "ALL",
  rehireEligibility: "ALL",
};

export default function ExitAnalytics() {
  const [filters, setFilters] = useState(INITIAL_FILTERS);
  const [analyticsData, setAnalyticsData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedExitCaseId, setSelectedExitCaseId] = useState(null);

  const loadData = async (currentFilters = filters) => {
    try {
      setLoading(true);
      setError("");
      const data = await getExitAnalyticsData(currentFilters);
      setAnalyticsData(data);
    } catch (err) {
      console.error("Failed to load exit analytics:", err);
      setError(err.message || "Failed to load exit analytics data.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData(filters);
  }, [filters]);

  const handleResetFilters = () => {
    setFilters(INITIAL_FILTERS);
  };

  if (loading && !analyticsData) {
    return (
      <div className="app-page">
        <ExitLoading />
      </div>
    );
  }

  if (error && !analyticsData) {
    return (
      <div className="app-page">
        <ExitErrorState message={error} onRetry={() => loadData(filters)} />
      </div>
    );
  }

  const {
    allDepartments = [],
    summary = {},
    exitReasons = [],
    exitTrend = [],
    experienceRatings = [],
    npsSummary = {},
    preventableData = [],
    performanceDimensions = [],
    knowledgeTransfer = {},
    departmentAnalytics = [],
    pendingWorkflow = [],
    completedExitRecords = [],
  } = analyticsData || {};

  const isEmpty = summary.totalExits === 0;

  return (
    <div className="app-page">
      <Link to="/" className="back-link">
        ← Back to HR Dashboard
      </Link>

      <div className="page-header-modern" style={{ marginBottom: 20 }}>
        <div className="page-icon" style={{ background: "#eff6ff", color: "#3b82f6" }}>
          <BarChart3 size={28} />
        </div>

        <div style={{ flex: 1, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <h1 className="page-title-modern">Exit Analytics Workspace</h1>
            <p className="page-subtitle">
              Comprehensive descriptive analytics, exit reasons, ratings, knowledge transfer insights, and historical records
            </p>
          </div>

          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => loadData(filters)}
            style={{ display: "flex", alignItems: "center", gap: 6 }}
          >
            <RefreshCw size={15} /> Refresh Data
          </button>
        </div>
      </div>

      {/* Top Filter Bar */}
      <AnalyticsFilters
        filters={filters}
        allDepartments={allDepartments}
        onFilterChange={setFilters}
        onResetFilters={handleResetFilters}
      />

      {isEmpty ? (
        <EmptyAnalyticsState onResetFilters={handleResetFilters} />
      ) : (
        <>
          {/* Summary Metric Cards */}
          <AnalyticsSummaryCards summary={summary} />

          {/* Section 1 & Section 2: Exit Reasons & Exit Trend */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(360px, 1fr))", gap: 20 }}>
            <ExitReasonChart exitReasons={exitReasons} />
            <ExitTrendChart exitTrend={exitTrend} />
          </div>

          {/* Section 3 & Section 4: Experience & NPS */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(360px, 1fr))", gap: 20 }}>
            <ExperienceRatingChart experienceRatings={experienceRatings} />
            <NPSSummary npsSummary={npsSummary} />
          </div>

          {/* Section 5 & Section 6: Preventable Exits & Performance Radar */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(360px, 1fr))", gap: 20 }}>
            <PreventableExitChart preventableData={preventableData} />
            <PerformanceRadar performanceDimensions={performanceDimensions} />
          </div>

          {/* Section 7: Knowledge Transfer & Handover */}
          <KnowledgeTransferChart knowledgeTransfer={knowledgeTransfer} />

          {/* Section 8: Department Breakdown */}
          <DepartmentBreakdown departmentAnalytics={departmentAnalytics} />

          {/* Section 9: Pending Exit Workflows */}
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <h3 style={{ margin: "0 0 4px 0", fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
              Section 9: Pending Exit Workflows
            </h3>
            <p style={{ margin: "0 0 16px 0", fontSize: 12, color: "#64748b" }}>
              Exit cases currently in progress across candidate or HR evaluation stages
            </p>

            {pendingWorkflow.length === 0 ? (
              <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", margin: 0 }}>
                No exit cases are currently pending.
              </p>
            ) : (
              <div className="table-container">
                <table>
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>MID</th>
                      <th>Exit Type</th>
                      <th>Overall Status</th>
                      <th>Candidate Form</th>
                      <th>HR Form</th>
                      <th>Exit Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pendingWorkflow.map((item) => (
                      <tr key={item.exitCaseId}>
                        <td><strong>{item.candidateName}</strong></td>
                        <td>{item.mid}</td>
                        <td>{item.exitType ? item.exitType.replaceAll("_", " ") : "—"}</td>
                        <td>
                          <span className="badge badge-warning">
                            {item.overallStatus}
                          </span>
                        </td>
                        <td>
                          {item.candidateFormCompleted ? (
                            <span className="badge badge-success">Completed</span>
                          ) : (
                            <span className="badge badge-warning">Pending</span>
                          )}
                        </td>
                        <td>
                          {item.hrFormCompleted ? (
                            <span className="badge badge-success">Completed</span>
                          ) : (
                            <span className="badge badge-warning">Pending</span>
                          )}
                        </td>
                        <td>{item.exitDate}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Section 10: Completed Exit Case Records */}
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
              <div>
                <h3 style={{ margin: "0 0 4px 0", fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
                  Section 10: Completed Exit Case Records
                </h3>
                <p style={{ margin: 0, fontSize: 12, color: "#64748b" }}>
                  Historical log of all finalized exit cases (`overall_status = COMPLETED`). Inspect complete Candidate Questionnaire & HR Evaluation side-by-side.
                </p>
              </div>
              <span style={{ fontSize: 13, fontWeight: 600, color: "#15803d", background: "#dcfce7", padding: "4px 12px", borderRadius: 16 }}>
                {completedExitRecords.length} Completed {completedExitRecords.length === 1 ? "Record" : "Records"}
              </span>
            </div>

            {completedExitRecords.length === 0 ? (
              <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", margin: 0 }}>
                No completed exit cases found matching the active filters.
              </p>
            ) : (
              <div className="table-container" style={{ overflowX: "auto" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
                  <thead>
                    <tr style={{ background: "#f8fafc", textAlign: "left", color: "#475569", borderBottom: "1px solid #e2e8f0" }}>
                      <th style={{ padding: "12px 14px" }}>Candidate Name</th>
                      <th style={{ padding: "12px 14px" }}>MID</th>
                      <th style={{ padding: "12px 14px" }}>Department / Pod</th>
                      <th style={{ padding: "12px 14px" }}>Exit Type</th>
                      <th style={{ padding: "12px 14px" }}>Exit Date</th>
                      <th style={{ padding: "12px 14px" }}>Candidate Form</th>
                      <th style={{ padding: "12px 14px" }}>HR Form</th>
                      <th style={{ padding: "12px 14px" }}>Reviewed By</th>
                      <th style={{ padding: "12px 14px" }}>Evaluation Date</th>
                      <th style={{ padding: "12px 14px", textAlign: "right" }}>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {completedExitRecords.map((item) => (
                      <tr key={item.exitCaseId} style={{ borderBottom: "1px solid #f1f5f9" }}>
                        <td style={{ padding: "12px 14px", fontWeight: 600, color: "#0f172a" }}>
                          {item.candidateName}
                        </td>
                        <td style={{ padding: "12px 14px", color: "#475569" }}>{item.mid}</td>
                        <td style={{ padding: "12px 14px", color: "#475569" }}>{item.department}</td>
                        <td style={{ padding: "12px 14px" }}>
                          <span style={{ padding: "2px 8px", borderRadius: 4, fontSize: 12, fontWeight: 600, background: "#f1f5f9", color: "#475569" }}>
                            {item.exitType}
                          </span>
                        </td>
                        <td style={{ padding: "12px 14px", color: "#475569" }}>{item.exitDate}</td>
                        <td style={{ padding: "12px 14px" }}>
                          <span style={{ padding: "2px 8px", borderRadius: 10, fontSize: 11, fontWeight: 700, background: "#dcfce7", color: "#15803d" }}>
                            Completed
                          </span>
                        </td>
                        <td style={{ padding: "12px 14px" }}>
                          <span style={{ padding: "2px 8px", borderRadius: 10, fontSize: 11, fontWeight: 700, background: "#dcfce7", color: "#15803d" }}>
                            Completed
                          </span>
                        </td>
                        <td style={{ padding: "12px 14px", color: "#475569" }}>{item.reviewedBy}</td>
                        <td style={{ padding: "12px 14px", color: "#475569" }}>{item.evaluationDate}</td>
                        <td style={{ padding: "12px 14px", textAlign: "right" }}>
                          <button
                            type="button"
                            className="btn btn-secondary"
                            onClick={() => setSelectedExitCaseId(item.exitCaseId)}
                            style={{
                              padding: "6px 12px",
                              fontSize: 12,
                              fontWeight: 600,
                              display: "inline-flex",
                              alignItems: "center",
                              gap: 4,
                            }}
                          >
                            <Eye size={14} /> View Responses
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {/* Interactive Modal for Viewing Case Record */}
      {selectedExitCaseId && (
        <ExitCaseDetailsModal
          exitCaseId={selectedExitCaseId}
          onClose={() => setSelectedExitCaseId(null)}
        />
      )}
    </div>
  );
}

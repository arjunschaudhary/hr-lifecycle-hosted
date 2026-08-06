/**
 * ExitAnalytics.jsx
 * HR Exit Analytics Dashboard Page.
 * Visualizes descriptive exit data using modular charts, cards, and tables.
 */

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { BarChart3, RefreshCw, GitCompare } from "lucide-react";

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
import RecommendationChart from "../components/exitAnalytics/RecommendationChart";
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
    recommendations = {},
    candidateVsHrComparison = {},
    pendingWorkflow = [],
    recentExits = [],
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
              Comprehensive descriptive analytics, exit reasons, ratings, and knowledge transfer insights
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

          {/* Section 7: Knowledge Transfer */}
          <KnowledgeTransferChart knowledgeTransfer={knowledgeTransfer} />

          {/* Section 8: Department Breakdown */}
          <DepartmentBreakdown departmentAnalytics={departmentAnalytics} />

          {/* Section 9: Recommendations */}
          <RecommendationChart recommendations={recommendations} />

          {/* Section 10: Candidate vs HR Comparison */}
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
              <div style={{ width: 32, height: 32, borderRadius: 6, background: "#fdf4ff", color: "#c026d3", display: "flex", alignItems: "center", justifyContent: "center" }}>
                <GitCompare size={18} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
                  Section 10: Candidate vs HR Primary Reason Comparison
                </h3>
                <p style={{ margin: "2px 0 0", fontSize: 12, color: "#64748b" }}>
                  Alignment analysis between candidate-reported primary exit reason and HR evaluation reason
                </p>
              </div>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 14, marginBottom: 20 }}>
              <div style={{ padding: 14, borderRadius: 8, background: "#f0fdf4", border: "1px solid #bbf7d0", textAlign: "center" }}>
                <span style={{ fontSize: 12, fontWeight: 600, color: "#16a34a" }}>Reason Agreement %</span>
                <div style={{ fontSize: 24, fontWeight: 800, color: "#15803d", marginTop: 4 }}>
                  {candidateVsHrComparison.agreementPct ?? 0}%
                </div>
              </div>

              <div style={{ padding: 14, borderRadius: 8, background: "#fef2f2", border: "1px solid #fecaca", textAlign: "center" }}>
                <span style={{ fontSize: 12, fontWeight: 600, color: "#dc2626" }}>Reason Mismatch %</span>
                <div style={{ fontSize: 24, fontWeight: 800, color: "#b91c1c", marginTop: 4 }}>
                  {candidateVsHrComparison.mismatchPct ?? 0}%
                </div>
              </div>

              <div style={{ padding: 14, borderRadius: 8, background: "#f8fafc", border: "1px solid #e2e8f0", textAlign: "center" }}>
                <span style={{ fontSize: 12, fontWeight: 600, color: "#64748b" }}>Total Compared Exits</span>
                <div style={{ fontSize: 24, fontWeight: 800, color: "#1e293b", marginTop: 4 }}>
                  {candidateVsHrComparison.totalCompared ?? 0}
                </div>
              </div>
            </div>

            {candidateVsHrComparison.topMismatches && candidateVsHrComparison.topMismatches.length > 0 && (
              <div>
                <h4 style={{ margin: "0 0 10px 0", fontSize: 14, fontWeight: 700, color: "#334155" }}>
                  Top Mismatched Exit Reasons
                </h4>
                <div className="table-container">
                  <table>
                    <thead>
                      <tr>
                        <th>Candidate Reported Reason</th>
                        <th>HR Evaluated Reason</th>
                        <th>Occurrences</th>
                      </tr>
                    </thead>
                    <tbody>
                      {candidateVsHrComparison.topMismatches.map((m, idx) => (
                        <tr key={idx}>
                          <td><strong>{m.candidateReason}</strong></td>
                          <td><span style={{ color: "#dc2626" }}>{m.hrReason}</span></td>
                          <td>{m.count}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>

          {/* Section 11: Pending Workflow Table */}
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <h3 style={{ margin: "0 0 4px 0", fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
              Section 11: Pending Exit Workflows
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

          {/* Section 12: Recent Completed Exits Table */}
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <h3 style={{ margin: "0 0 4px 0", fontSize: 16, fontWeight: 700, color: "#1e293b" }}>
              Section 12: Recent Completed Exits
            </h3>
            <p style={{ margin: "0 0 16px 0", fontSize: 12, color: "#64748b" }}>
              Log of recently finalized intern exit cases and evaluation decisions
            </p>

            {recentExits.length === 0 ? (
              <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", margin: 0 }}>
                No completed exit cases found.
              </p>
            ) : (
              <div className="table-container">
                <table>
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>MID</th>
                      <th>Department</th>
                      <th>Exit Date</th>
                      <th>Experience Rating</th>
                      <th>Performance Average</th>
                      <th>Rehire</th>
                      <th>Certificate</th>
                      <th>LOR</th>
                    </tr>
                  </thead>
                  <tbody>
                    {recentExits.map((item) => (
                      <tr key={item.exitCaseId}>
                        <td><strong>{item.candidateName}</strong></td>
                        <td>{item.mid}</td>
                        <td>{item.department}</td>
                        <td>{item.exitDate}</td>
                        <td>{item.experienceRating}</td>
                        <td>{item.performanceAvg}</td>
                        <td>
                          <span className={`badge ${item.rehire === "YES" ? "badge-success" : item.rehire === "NO" ? "badge-danger" : "badge-warning"}`}>
                            {item.rehire}
                          </span>
                        </td>
                        <td>{item.certificate}</td>
                        <td>{item.lor}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

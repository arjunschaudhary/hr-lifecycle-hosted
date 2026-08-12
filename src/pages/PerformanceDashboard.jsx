import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  Calculator,
  CheckCircle2,
  Clock3,
  Gauge,
  Lock,
  Users,
} from "lucide-react";
import { useAuth } from "../context/authContext";
import {
  fetchCandidatePerformanceList,
  fetchPerformanceActionQueue,
  fetchPerformanceCycleOverview,
} from "../services/performanceDashboardService";

const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const getMonthKey = (value) => {
  if (typeof value !== "string") {
    return "";
  }

  const match = /^(\d{4})-(\d{2})-\d{2}$/.exec(value);
  return match ? `${match[1]}-${match[2]}` : "";
};

const formatMonthLabel = (monthKey) => {
  const match = /^(\d{4})-(\d{2})$/.exec(monthKey);
  if (!match) {
    return monthKey;
  }

  const monthIndex = Number(match[2]) - 1;
  return MONTH_NAMES[monthIndex]
    ? `${MONTH_NAMES[monthIndex]} ${match[1]}`
    : monthKey;
};

const formatDate = (value) => {
  if (!value) {
    return "—";
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : DATE_FORMATTER.format(date);
};

const formatStatus = (value) => {
  if (!value) {
    return "—";
  }

  return value
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
};

const formatActionOwner = (value) =>
  value === "HR_SITE_CONNECT" ? "HR Psyconnect" : formatStatus(value);

const formatNullableValue = (value) =>
  value === null || value === undefined || value === "" ? "—" : value;

const getResultBadgeClass = (status) => {
  if (status === "FINALIZED" || status === "LOCKED") {
    return "badge-success";
  }

  if (status === "AWAITING_REVIEWS" || status === "DAILY_SCORING") {
    return "badge-warning";
  }

  return "badge-primary";
};

const getPodLabel = (record) => {
  if (record.podName && record.podCode) {
    return `${record.podName} (${record.podCode})`;
  }

  return record.podName || record.podCode || "—";
};

const MetricCard = ({ icon: Icon, title, value }) => (
  <article className="metric-card">
    <div className="metric-card__icon" aria-hidden="true">
      <Icon size={22} />
    </div>
    <p className="metric-title">{title}</p>
    <p className="metric-value">{formatNullableValue(value)}</p>
  </article>
);

const PerformanceDashboard = () => {
  const {
    hasPerformanceDashboardAccess,
    hasStaffAccess,
    hasLeadReviewAccess,
  } = useAuth();
  const [cycles, setCycles] = useState([]);
  const [candidateRecords, setCandidateRecords] = useState([]);
  const [actionItems, setActionItems] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [selectedMonthKey, setSelectedMonthKey] = useState("");
  const [selectedCycleId, setSelectedCycleId] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedPod, setSelectedPod] = useState("");
  const [selectedResultStatus, setSelectedResultStatus] = useState("");
  const [selectedActionOwner, setSelectedActionOwner] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const selectedCycleIdRef = useRef("");

  useEffect(() => {
    if (!hasPerformanceDashboardAccess) {
      return undefined;
    }

    let isMounted = true;

    const loadDashboard = async () => {
      await Promise.resolve();

      if (!isMounted) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const [nextCycles, nextCandidateRecords, nextActionItems] =
          await Promise.all([
            fetchPerformanceCycleOverview(),
            fetchCandidatePerformanceList(),
            fetchPerformanceActionQueue(),
          ]);

        if (!isMounted) {
          return;
        }

        setCycles(nextCycles);
        setCandidateRecords(nextCandidateRecords);
        setActionItems(nextActionItems);
        const preservedCycle = nextCycles.find(
          (cycle) => cycle.cycleId === selectedCycleIdRef.current,
        );
        const nextSelectedCycle =
          preservedCycle ||
          nextCycles.find((cycle) => cycle.cycleStatus === "OPEN") ||
          nextCycles[0] ||
          null;
        const nextSelectedCycleId = nextSelectedCycle?.cycleId || "";

        selectedCycleIdRef.current = nextSelectedCycleId;
        setSelectedMonthKey(getMonthKey(nextSelectedCycle?.startDate));
        setSelectedCycleId(nextSelectedCycleId);
      } catch {
        if (isMounted) {
          setPageError("Unable to load the Performance Dashboard.");
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    };

    void loadDashboard();

    return () => {
      isMounted = false;
    };
  }, [hasPerformanceDashboardAccess, retryRequestId]);

  const monthOptions = useMemo(() => {
    const months = new Map();

    cycles.forEach((cycle) => {
      const key = getMonthKey(cycle.startDate);
      if (key && !months.has(key)) {
        months.set(key, {
          key,
          label: formatMonthLabel(key),
        });
      }
    });

    return Array.from(months.values()).sort((left, right) =>
      right.key.localeCompare(left.key),
    );
  }, [cycles]);

  const filteredCycles = useMemo(
    () =>
      cycles.filter(
        (cycle) => getMonthKey(cycle.startDate) === selectedMonthKey,
      ),
    [cycles, selectedMonthKey],
  );

  const selectedCycle = useMemo(
    () => cycles.find((cycle) => cycle.cycleId === selectedCycleId) || null,
    [cycles, selectedCycleId],
  );

  const selectedCycleCandidateRecords = useMemo(
    () =>
      candidateRecords.filter(
        (record) => record.cycleId === selectedCycleId,
      ),
    [candidateRecords, selectedCycleId],
  );

  const selectedCycleActionItems = useMemo(
    () => actionItems.filter((item) => item.cycleId === selectedCycleId),
    [actionItems, selectedCycleId],
  );

  const podOptions = useMemo(() => {
    const pods = new Map();

    selectedCycleCandidateRecords.forEach((record) => {
      if (record.podId) {
        pods.set(record.podId, getPodLabel(record));
      }
    });

    return Array.from(pods, ([value, label]) => ({ value, label })).sort(
      (left, right) => left.label.localeCompare(right.label),
    );
  }, [selectedCycleCandidateRecords]);

  const resultStatusOptions = useMemo(
    () =>
      Array.from(
        new Set(
          selectedCycleCandidateRecords
            .map((record) => record.resultStatus)
            .filter(Boolean),
        ),
      ).sort(),
    [selectedCycleCandidateRecords],
  );

  const actionOwnerOptions = useMemo(
    () =>
      Array.from(
        new Set(
          selectedCycleActionItems
            .map((item) => item.actionOwnerScope)
            .filter(Boolean),
        ),
      ).sort(),
    [selectedCycleActionItems],
  );

  const filteredCandidateRecords = useMemo(() => {
    const normalizedSearchTerm = searchTerm.trim().toLowerCase();

    return selectedCycleCandidateRecords.filter((record) => {
      const matchesSearch =
        !normalizedSearchTerm ||
        record.fullName?.toLowerCase().includes(normalizedSearchTerm) ||
        record.email?.toLowerCase().includes(normalizedSearchTerm);
      const matchesPod = !selectedPod || record.podId === selectedPod;
      const matchesResultStatus =
        !selectedResultStatus ||
        record.resultStatus === selectedResultStatus;

      return matchesSearch && matchesPod && matchesResultStatus;
    });
  }, [
    searchTerm,
    selectedCycleCandidateRecords,
    selectedPod,
    selectedResultStatus,
  ]);

  const filteredActionItems = useMemo(
    () =>
      selectedCycleActionItems.filter(
        (item) =>
          !selectedActionOwner ||
          item.actionOwnerScope === selectedActionOwner,
      ),
    [selectedActionOwner, selectedCycleActionItems],
  );

  const handleCycleChange = (event) => {
    selectedCycleIdRef.current = event.target.value;
    setSelectedCycleId(event.target.value);
    setSelectedPod("");
    setSelectedResultStatus("");
    setSelectedActionOwner("");
  };

  const handleMonthChange = (event) => {
    const nextMonthKey = event.target.value;
    const nextMonthCycles = cycles.filter(
      (cycle) => getMonthKey(cycle.startDate) === nextMonthKey,
    );
    const nextCycle =
      nextMonthCycles.find((cycle) => cycle.cycleStatus === "OPEN") ||
      nextMonthCycles[0] ||
      null;
    const nextCycleId = nextCycle?.cycleId || "";

    setSelectedMonthKey(nextMonthKey);
    selectedCycleIdRef.current = nextCycleId;
    setSelectedCycleId(nextCycleId);
    setSelectedPod("");
    setSelectedResultStatus("");
    setSelectedActionOwner("");
  };

  const handleRetry = () => {
    setRetryRequestId((currentRequestId) => currentRequestId + 1);
  };

  const scoringCompletionValue =
    selectedCycle?.scoringCompletionPercent === null ||
    selectedCycle?.scoringCompletionPercent === undefined
      ? "—"
      : `${selectedCycle.scoringCompletionPercent}%`;

  const backLink = hasStaffAccess
    ? { to: "/", label: "Back to Dashboard" }
    : hasLeadReviewAccess
      ? { to: "/lead-reviews", label: "Lead Reviews" }
      : null;

  return (
    <main className="app-page">
      {backLink && (
        <Link to={backLink.to} className="back-link">
          {backLink.label}
        </Link>
      )}

      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <Gauge size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">Performance Dashboard</h1>
          <p className="page-subtitle">
            Monitor performance cycles, candidate progress, reviews, and
            outstanding actions.
          </p>
        </div>
      </header>

      {!hasPerformanceDashboardAccess ? (
        <section className="info-banner" role="status" aria-live="polite">
          <h2>Performance Dashboard access unavailable</h2>
          <p>
            Your account does not have access to performance dashboard data.
          </p>
        </section>
      ) : isLoading ? (
        <p role="status" aria-live="polite">
          Loading Performance Dashboard...
        </p>
      ) : pageError ? (
        <section className="info-banner" role="alert">
          <p>{pageError}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      ) : cycles.length === 0 ? (
        <p className="info-banner" role="status" aria-live="polite">
          No performance cycles are available.
        </p>
      ) : (
        <>
          <section aria-labelledby="cycle-overview-heading">
            <h2 id="cycle-overview-heading">Cycle Overview</h2>
            <div className="metric-grid">
              <div className="form-group">
                <label htmlFor="performance-month">Performance Month</label>
                <select
                  id="performance-month"
                  className="form-select"
                  value={selectedMonthKey}
                  onChange={handleMonthChange}
                >
                  {monthOptions.map((month) => (
                    <option key={month.key} value={month.key}>
                      {month.label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="performance-cycle">Performance Cycle</label>
                <select
                  id="performance-cycle"
                  className="form-select"
                  value={selectedCycleId}
                  onChange={handleCycleChange}
                  disabled={filteredCycles.length === 0}
                >
                  {filteredCycles.map((cycle) => (
                    <option key={cycle.cycleId} value={cycle.cycleId}>
                      {cycle.cycleCode} ({formatDate(cycle.startDate)} -{" "}
                      {formatDate(cycle.endDate)})
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div className="metric-grid">
              <MetricCard
                icon={Users}
                title="Assignments"
                value={selectedCycle?.assignmentCount}
              />
              <MetricCard
                icon={Gauge}
                title="Scoring Completion"
                value={scoringCompletionValue}
              />
              <MetricCard
                icon={Clock3}
                title="Awaiting Reviews"
                value={selectedCycle?.awaitingReviewsCount}
              />
              <MetricCard
                icon={Calculator}
                title="Ready to Calculate"
                value={selectedCycle?.readyToCalculateCount}
              />
              <MetricCard
                icon={CheckCircle2}
                title="Finalized"
                value={selectedCycle?.finalizedCount}
              />
              <MetricCard
                icon={Lock}
                title="Locked"
                value={selectedCycle?.lockedCount}
              />
            </div>
          </section>

          <section aria-labelledby="candidate-performance-heading">
            <h2 id="candidate-performance-heading">Candidate Performance</h2>
            <div className="form-grid">
              <div className="form-group">
                <label htmlFor="candidate-search">Search Candidate</label>
                <input
                  id="candidate-search"
                  className="form-input"
                  type="search"
                  value={searchTerm}
                  onChange={(event) => setSearchTerm(event.target.value)}
                  placeholder="Search name or email"
                />
              </div>
              <div className="form-group">
                <label htmlFor="candidate-pod-filter">Pod</label>
                <select
                  id="candidate-pod-filter"
                  className="form-select"
                  value={selectedPod}
                  onChange={(event) => setSelectedPod(event.target.value)}
                >
                  <option value="">All Pods</option>
                  {podOptions.map((pod) => (
                    <option key={pod.value} value={pod.value}>
                      {pod.label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label htmlFor="candidate-result-filter">Result Status</label>
                <select
                  id="candidate-result-filter"
                  className="form-select"
                  value={selectedResultStatus}
                  onChange={(event) =>
                    setSelectedResultStatus(event.target.value)
                  }
                >
                  <option value="">All Result Statuses</option>
                  {resultStatusOptions.map((status) => (
                    <option key={status} value={status}>
                      {formatStatus(status)}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {filteredCandidateRecords.length === 0 ? (
              <p className="info-banner" role="status" aria-live="polite">
                No candidate performance records match the selected filters.
              </p>
            ) : (
              <div className="table-container">
                <table>
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Email</th>
                      <th>Pod</th>
                      <th>Applied Role</th>
                      <th>Scoring Progress</th>
                      <th>Daily Score</th>
                      <th>Lead Score</th>
                      <th>HR Score</th>
                      <th>Exceptional Score</th>
                      <th>Final Score</th>
                      <th>Performance Band</th>
                      <th>Result Status</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredCandidateRecords.map((record) => (
                      <tr key={record.candidateCycleId}>
                        <td>{formatNullableValue(record.fullName)}</td>
                        <td>{formatNullableValue(record.email)}</td>
                        <td>{getPodLabel(record)}</td>
                        <td>{formatNullableValue(record.appliedRole)}</td>
                        <td>
                          {formatNullableValue(record.scoredDays)} /{" "}
                          {formatNullableValue(record.eligibleDays)} (
                          {formatNullableValue(
                            record.scoringCompletionPercent,
                          )}
                          %)
                        </td>
                        <td>
                          {formatNullableValue(record.dailyComponentScore)}
                        </td>
                        <td>{formatNullableValue(record.leadScore)}</td>
                        <td>{formatNullableValue(record.hrScore)}</td>
                        <td>
                          {formatNullableValue(record.exceptionalScore)}
                        </td>
                        <td>{formatNullableValue(record.finalScore)}</td>
                        <td>{formatStatus(record.performanceBand)}</td>
                        <td>
                          <span
                            className={`badge ${getResultBadgeClass(
                              record.resultStatus,
                            )}`}
                          >
                            {formatStatus(record.resultStatus)}
                          </span>
                        </td>
                        <td>
                          <div className="action-group">
                            <Link
                              to={`/performance-dashboard/${record.candidateCycleId}/daily`}
                              className="btn btn-primary"
                            >
                              Open Daily Entries
                            </Link>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section aria-labelledby="performance-actions-heading">
            <h2 id="performance-actions-heading">Action Queue</h2>
            <div className="form-group">
              <label htmlFor="action-owner-filter">Action Owner</label>
              <select
                id="action-owner-filter"
                className="form-select"
                value={selectedActionOwner}
                onChange={(event) =>
                  setSelectedActionOwner(event.target.value)
                }
              >
                <option value="">All Action Owners</option>
                {actionOwnerOptions.map((owner) => (
                  <option key={owner} value={owner}>
                    {formatActionOwner(owner)}
                  </option>
                ))}
              </select>
            </div>

            {filteredActionItems.length === 0 ? (
              <p className="info-banner" role="status" aria-live="polite">
                No outstanding actions match the selected filters.
              </p>
            ) : (
              <div className="table-container">
                <table>
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Pod</th>
                      <th>Action</th>
                      <th>Owner</th>
                      <th>Due Date</th>
                      <th>Status</th>
                      <th>Reason</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredActionItems.map((item) => (
                      <tr key={item.actionKey}>
                        <td>{formatNullableValue(item.fullName)}</td>
                        <td>{getPodLabel(item)}</td>
                        <td>{formatNullableValue(item.actionLabel)}</td>
                        <td>{formatActionOwner(item.actionOwnerScope)}</td>
                        <td>{formatDate(item.dueDate)}</td>
                        <td>
                          <span
                            className={`badge ${
                              item.isOverdue
                                ? "badge-warning"
                                : "badge-primary"
                            }`}
                          >
                            {item.isOverdue ? "Overdue" : "Due"}
                          </span>
                        </td>
                        <td>{formatNullableValue(item.actionReason)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </>
      )}
    </main>
  );
};

export default PerformanceDashboard;

import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  CheckCircle2,
  ClipboardCheck,
  Clock3,
  FilePenLine,
  Users,
} from "lucide-react";

import { useAuth } from "../context/authContext";
import { fetchLeadReviewTasks } from "../services/leadReviewService";

const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const TASK_CATEGORIES = {
  PENDING: new Set(["NOT_STARTED", "WAITING_FOR_DAILY_MARKING"]),
  DRAFT: new Set(["DRAFT"]),
  SUBMITTED: new Set(["SUBMITTED"]),
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

const formatNullableValue = (value) =>
  value === null || value === undefined || value === "" ? "—" : value;

const getPodLabel = (task) => {
  if (task.podName && task.podCode) {
    return `${task.podName} (${task.podCode})`;
  }

  return task.podName || task.podCode || "—";
};

const getReviewBadgeClass = (status) => {
  if (status === "SUBMITTED") {
    return "badge-success";
  }

  if (status === "DRAFT" || status === "WAITING_FOR_DAILY_MARKING") {
    return "badge-warning";
  }

  return "badge-primary";
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

const TaskAction = ({ task }) => {
  const detailPath = `/lead-reviews/${task.candidateCycleId}`;

  if (task.reviewDisplayStatus === "WAITING_FOR_DAILY_MARKING") {
    return (
      <button className="btn" type="button" disabled>
        Waiting for Daily Marking
      </button>
    );
  }

  if (task.reviewDisplayStatus === "SUBMITTED") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        View Review
      </Link>
    );
  }

  if (task.reviewDisplayStatus === "DRAFT") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        {task.canEdit ? "Continue Review" : "View Draft"}
      </Link>
    );
  }

  if (task.reviewDisplayStatus === "NOT_STARTED" && task.canEdit) {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        Start Review
      </Link>
    );
  }

  return (
    <button className="btn" type="button" disabled>
      Review Unavailable
    </button>
  );
};

const LeadReviews = () => {
  const { hasLeadReviewAccess } = useAuth();
  const [tasks, setTasks] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const [selectedCategory, setSelectedCategory] = useState("PENDING");
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedPod, setSelectedPod] = useState("");
  const [selectedCycle, setSelectedCycle] = useState("");

  useEffect(() => {
    if (!hasLeadReviewAccess) {
      return undefined;
    }

    let isMounted = true;

    const loadTasks = async () => {
      await Promise.resolve();

      if (!isMounted) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const nextTasks = await fetchLeadReviewTasks();

        if (!isMounted) {
          return;
        }

        setTasks(nextTasks);
        setSelectedPod((currentPod) =>
          currentPod &&
          !nextTasks.some((task) => task.podId === currentPod)
            ? ""
            : currentPod,
        );
        setSelectedCycle((currentCycle) =>
          currentCycle &&
          !nextTasks.some((task) => task.cycleId === currentCycle)
            ? ""
            : currentCycle,
        );
      } catch {
        if (isMounted) {
          setPageError("Unable to load the Lead Reviews workspace.");
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    };

    void loadTasks();

    return () => {
      isMounted = false;
    };
  }, [hasLeadReviewAccess, retryRequestId]);

  const metrics = useMemo(
    () => ({
      total: tasks.length,
      ready: tasks.filter(
        (task) =>
          task.canEdit && task.reviewDisplayStatus === "NOT_STARTED",
      ).length,
      draft: tasks.filter(
        (task) => task.reviewDisplayStatus === "DRAFT",
      ).length,
      submitted: tasks.filter(
        (task) => task.reviewDisplayStatus === "SUBMITTED",
      ).length,
      waiting: tasks.filter(
        (task) =>
          task.reviewDisplayStatus === "WAITING_FOR_DAILY_MARKING",
      ).length,
    }),
    [tasks],
  );

  const podOptions = useMemo(() => {
    const pods = new Map();

    tasks.forEach((task) => {
      pods.set(task.podId, getPodLabel(task));
    });

    return Array.from(pods, ([value, label]) => ({ value, label })).sort(
      (left, right) => left.label.localeCompare(right.label),
    );
  }, [tasks]);

  const cycleOptions = useMemo(() => {
    const cycles = new Map();

    tasks.forEach((task) => {
      cycles.set(task.cycleId, {
        value: task.cycleId,
        label: `${task.cycleCode} (${formatDate(
          task.cycleStartDate,
        )} - ${formatDate(task.cycleEndDate)})`,
        startDate: task.cycleStartDate,
      });
    });

    return Array.from(cycles.values()).sort((left, right) =>
      right.startDate.localeCompare(left.startDate),
    );
  }, [tasks]);

  const filteredTasks = useMemo(() => {
    const normalizedSearchTerm = searchTerm.trim().toLowerCase();
    const categoryStatuses = TASK_CATEGORIES[selectedCategory];

    return tasks.filter((task) => {
      const matchesCategory = categoryStatuses.has(
        task.reviewDisplayStatus,
      );
      const matchesSearch =
        !normalizedSearchTerm ||
        task.fullName.toLowerCase().includes(normalizedSearchTerm) ||
        task.appliedRole?.toLowerCase().includes(normalizedSearchTerm) ||
        task.roleCode?.toLowerCase().includes(normalizedSearchTerm);
      const matchesPod = !selectedPod || task.podId === selectedPod;
      const matchesCycle =
        !selectedCycle || task.cycleId === selectedCycle;

      return matchesCategory && matchesSearch && matchesPod && matchesCycle;
    });
  }, [
    searchTerm,
    selectedCategory,
    selectedCycle,
    selectedPod,
    tasks,
  ]);

  const handleRetry = () => {
    setRetryRequestId((currentRequestId) => currentRequestId + 1);
  };

  return (
    <main className="app-page">
      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <ClipboardCheck size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">Lead Reviews</h1>
          <p className="page-subtitle">
            Review candidate performance for the cycles and pods assigned to
            you.
          </p>
        </div>
      </header>

      {!hasLeadReviewAccess ? (
        <section className="info-banner" role="status" aria-live="polite">
          <h2>Lead Review workspace access unavailable</h2>
          <p>Your account does not have access to Lead Review tasks.</p>
        </section>
      ) : isLoading ? (
        <p role="status" aria-live="polite">
          Loading Lead Reviews...
        </p>
      ) : pageError ? (
        <section className="info-banner" role="alert">
          <p>{pageError}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      ) : tasks.length === 0 ? (
        <p className="info-banner" role="status" aria-live="polite">
          No Lead Review tasks are currently available for your assigned pods.
        </p>
      ) : (
        <>
          <section aria-labelledby="lead-review-overview-heading">
            <h2 id="lead-review-overview-heading">Review Overview</h2>
            <div className="metric-grid">
              <MetricCard
                icon={Users}
                title="Total Tasks"
                value={metrics.total}
              />
              <MetricCard
                icon={ClipboardCheck}
                title="Ready to Review"
                value={metrics.ready}
              />
              <MetricCard
                icon={FilePenLine}
                title="Draft Reviews"
                value={metrics.draft}
              />
              <MetricCard
                icon={CheckCircle2}
                title="Submitted Reviews"
                value={metrics.submitted}
              />
              <MetricCard
                icon={Clock3}
                title="Waiting for Daily Marking"
                value={metrics.waiting}
              />
            </div>
          </section>

          <section aria-labelledby="lead-review-tasks-heading">
            <h2 id="lead-review-tasks-heading">Review Tasks</h2>

            <div className="action-group" aria-label="Review task category">
              {Object.keys(TASK_CATEGORIES).map((category) => (
                <button
                  key={category}
                  className={
                    selectedCategory === category
                      ? "btn btn-primary"
                      : "btn"
                  }
                  type="button"
                  aria-pressed={selectedCategory === category}
                  onClick={() => setSelectedCategory(category)}
                >
                  {formatStatus(category)}
                </button>
              ))}
            </div>

            <div className="form-grid">
              <div className="form-group">
                <label htmlFor="lead-review-search">Search Candidate</label>
                <input
                  id="lead-review-search"
                  className="form-input"
                  type="search"
                  value={searchTerm}
                  onChange={(event) => setSearchTerm(event.target.value)}
                  placeholder="Search name, role, or role code"
                />
              </div>
              <div className="form-group">
                <label htmlFor="lead-review-pod-filter">Pod</label>
                <select
                  id="lead-review-pod-filter"
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
                <label htmlFor="lead-review-cycle-filter">Cycle</label>
                <select
                  id="lead-review-cycle-filter"
                  className="form-select"
                  value={selectedCycle}
                  onChange={(event) => setSelectedCycle(event.target.value)}
                >
                  <option value="">All Cycles</option>
                  {cycleOptions.map((cycle) => (
                    <option key={cycle.value} value={cycle.value}>
                      {cycle.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {filteredTasks.length === 0 ? (
              <p className="info-banner" role="status" aria-live="polite">
                No Lead Review tasks match the selected filters.
              </p>
            ) : (
              <div className="table-container">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Applied Role</th>
                      <th>Pod</th>
                      <th>Cycle</th>
                      <th>Evaluation Period</th>
                      <th>Daily Progress</th>
                      <th>Daily Score</th>
                      <th>Review Status</th>
                      <th>Lead Score</th>
                      <th>Reviewer</th>
                      <th>Submitted On</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredTasks.map((task) => (
                      <tr key={task.candidateCycleId}>
                        <td>{task.fullName}</td>
                        <td>
                          {formatNullableValue(task.appliedRole)}
                          {task.roleCode ? ` (${task.roleCode})` : ""}
                        </td>
                        <td>{getPodLabel(task)}</td>
                        <td>
                          <strong>{task.cycleCode}</strong>
                          <br />
                          {formatDate(task.cycleStartDate)} -{" "}
                          {formatDate(task.cycleEndDate)}
                        </td>
                        <td>
                          {formatDate(task.evaluationStartDate)} -{" "}
                          {formatDate(task.evaluationEndDate)}
                          {task.isPartialCycle && (
                            <>
                              <br />
                              <span>Partial Cycle</span>
                            </>
                          )}
                        </td>
                        <td>
                          {task.scoredDays} / {task.eligibleDays}
                          <br />
                          {task.dailyScoringComplete ? "Complete" : "Pending"}
                        </td>
                        <td>
                          {task.dailyComponentScore === null
                            ? "—"
                            : `${task.dailyComponentScore} / 50`}
                        </td>
                        <td>
                          <span
                            className={`badge ${getReviewBadgeClass(
                              task.reviewDisplayStatus,
                            )}`}
                          >
                            {formatStatus(task.reviewDisplayStatus)}
                          </span>
                        </td>
                        <td>
                          {task.totalScore === null
                            ? "—"
                            : `${task.totalScore} / 25`}
                        </td>
                        <td>{formatNullableValue(task.reviewerName)}</td>
                        <td>{formatDate(task.submittedAt)}</td>
                        <td>
                          <div className="action-group">
                            <TaskAction task={task} />
                          </div>
                        </td>
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

export default LeadReviews;

import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  CheckCircle2,
  ClipboardCheck,
  FilePenLine,
  ListChecks,
  ShieldCheck,
} from "lucide-react";

import { getHrReviewTasks } from "../services/hrReviewService";

const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const TASK_STATUS_OPTIONS = [
  "ALL",
  "READY",
  "DRAFT",
  "SUBMITTED",
  "WAITING_FOR_DAILY_SCORING",
  "NOT_OPEN",
  "PROTECTED",
];

const STATUS_LABELS = {
  READY: "Ready",
  DRAFT: "Draft",
  SUBMITTED: "Submitted",
  WAITING_FOR_DAILY_SCORING: "Waiting for Daily Scoring",
  NOT_OPEN: "Not Open",
  PROTECTED: "Protected",
};

const formatDate = (value) => {
  if (!value) {
    return "—";
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : DATE_FORMATTER.format(date);
};

const formatNullableValue = (value) =>
  value === null || value === undefined || value === "" ? "—" : value;

const getStatusLabel = (status) => STATUS_LABELS[status] || status || "—";

const getStatusBadgeClass = (status) => {
  if (status === "SUBMITTED") {
    return "badge-success";
  }

  if (status === "DRAFT" || status === "WAITING_FOR_DAILY_SCORING") {
    return "badge-warning";
  }

  return "badge-primary";
};

const getPodLabel = (task) => {
  if (task.podName && task.podCode) {
    return `${task.podName} (${task.podCode})`;
  }

  return task.podName || task.podCode || "—";
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
  const detailPath = `/performance/hr-review/${task.candidateCycleId}`;

  if (task.taskStatus === "READY") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        Start Review
      </Link>
    );
  }

  if (task.taskStatus === "DRAFT") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        Continue Review
      </Link>
    );
  }

  if (task.taskStatus === "SUBMITTED") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        {task.canEdit ? "View / Amend" : "View"}
      </Link>
    );
  }

  if (task.taskStatus === "PROTECTED") {
    return (
      <Link className="btn btn-primary" to={detailPath}>
        View
      </Link>
    );
  }

  return (
    <button className="btn" type="button" disabled>
      Not Available
    </button>
  );
};

const HrReviewQueue = () => {
  const [tasks, setTasks] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedTaskStatus, setSelectedTaskStatus] = useState("ALL");

  useEffect(() => {
    let isMounted = true;

    const loadTasks = async () => {
      await Promise.resolve();

      if (!isMounted) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const nextTasks = await getHrReviewTasks();

        if (isMounted) {
          setTasks(nextTasks);
        }
      } catch {
        if (isMounted) {
          setPageError("Unable to load HR Review tasks.");
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
  }, [retryRequestId]);

  const metrics = useMemo(
    () => ({
      total: tasks.length,
      ready: tasks.filter((task) => task.taskStatus === "READY").length,
      draft: tasks.filter((task) => task.taskStatus === "DRAFT").length,
      submitted: tasks.filter((task) => task.taskStatus === "SUBMITTED")
        .length,
      protected: tasks.filter((task) => task.taskStatus === "PROTECTED")
        .length,
    }),
    [tasks],
  );

  const filteredTasks = useMemo(() => {
    const normalizedSearchTerm = searchTerm.trim().toLowerCase();

    return tasks.filter((task) => {
      const matchesStatus =
        selectedTaskStatus === "ALL" ||
        task.taskStatus === selectedTaskStatus;
      const searchableValues = [
        task.fullName,
        task.email,
        task.appliedRole,
        task.roleCode,
        task.podName,
        task.podCode,
        task.cycleCode,
      ];
      const matchesSearch =
        !normalizedSearchTerm ||
        searchableValues.some((value) =>
          value?.toLowerCase().includes(normalizedSearchTerm),
        );

      return matchesStatus && matchesSearch;
    });
  }, [searchTerm, selectedTaskStatus, tasks]);

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
          <h1 className="page-title-modern">HR Review</h1>
          <p className="page-subtitle">
            Complete the independent 15-mark HR review for eligible performance
            cycles.
          </p>
        </div>
      </header>

      {isLoading ? (
        <p role="status" aria-live="polite">
          Loading HR Review tasks...
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
          No HR Review tasks are currently available.
        </p>
      ) : (
        <>
          <section aria-labelledby="hr-review-overview-heading">
            <h2 id="hr-review-overview-heading">Review Overview</h2>
            <div className="metric-grid">
              <MetricCard
                icon={ListChecks}
                title="Total Tasks"
                value={metrics.total}
              />
              <MetricCard
                icon={ClipboardCheck}
                title="Ready"
                value={metrics.ready}
              />
              <MetricCard
                icon={FilePenLine}
                title="Draft"
                value={metrics.draft}
              />
              <MetricCard
                icon={CheckCircle2}
                title="Submitted"
                value={metrics.submitted}
              />
              <MetricCard
                icon={ShieldCheck}
                title="Protected"
                value={metrics.protected}
              />
            </div>
          </section>

          <section aria-labelledby="hr-review-tasks-heading">
            <h2 id="hr-review-tasks-heading">Review Tasks</h2>

            <div className="form-grid">
              <div className="form-group">
                <label htmlFor="hr-review-search">Search</label>
                <input
                  id="hr-review-search"
                  className="form-input"
                  type="search"
                  value={searchTerm}
                  onChange={(event) => setSearchTerm(event.target.value)}
                  placeholder="Search candidate, role, pod, or cycle"
                />
              </div>
              <div className="form-group">
                <label htmlFor="hr-review-status-filter">Task Status</label>
                <select
                  id="hr-review-status-filter"
                  className="form-select"
                  value={selectedTaskStatus}
                  onChange={(event) =>
                    setSelectedTaskStatus(event.target.value)
                  }
                >
                  {TASK_STATUS_OPTIONS.map((status) => (
                    <option key={status} value={status}>
                      {status === "ALL" ? "All Statuses" : getStatusLabel(status)}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {filteredTasks.length === 0 ? (
              <p className="info-banner" role="status" aria-live="polite">
                No HR Review tasks match the current search and filter.
              </p>
            ) : (
              <div className="table-container">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Role</th>
                      <th>Pod</th>
                      <th>Cycle</th>
                      <th>Evaluation Period</th>
                      <th>Daily Progress</th>
                      <th>HR Review Score</th>
                      <th>Status</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredTasks.map((task) => (
                      <tr key={task.candidateCycleId}>
                        <td>
                          <strong>{task.fullName}</strong>
                          <br />
                          {task.email}
                        </td>
                        <td>
                          {formatNullableValue(task.appliedRole)}
                          {task.roleCode ? ` (${task.roleCode})` : ""}
                        </td>
                        <td>{getPodLabel(task)}</td>
                        <td>{task.cycleCode}</td>
                        <td>
                          {formatDate(task.evaluationStartDate)} -{" "}
                          {formatDate(task.evaluationEndDate)}
                        </td>
                        <td>
                          {task.scoredDays} / {task.eligibleDays}
                        </td>
                        <td>
                          {task.totalScore === null
                            ? "—"
                            : `${task.totalScore} / 15`}
                        </td>
                        <td>
                          <span
                            className={`badge ${getStatusBadgeClass(
                              task.taskStatus,
                            )}`}
                          >
                            {getStatusLabel(task.taskStatus)}
                          </span>
                        </td>
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

export default HrReviewQueue;

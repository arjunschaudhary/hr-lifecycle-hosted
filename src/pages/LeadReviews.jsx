import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertCircle,
  CheckCircle2,
  ClipboardCheck,
  Clock3,
  FilePenLine,
  Inbox,
  ListChecks,
  LoaderCircle,
  Search,
  SlidersHorizontal,
  Users,
} from "lucide-react";

import { useAuth } from "../context/authContext";
import { fetchLeadReviewTasks } from "../services/leadReviewService";
import "./LeadReviews.css";

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

const MetricCard = ({ icon: Icon, title, value, tone }) => (
  <article className={`lead-reviews-metric lead-reviews-metric--${tone}`}>
    <div className="lead-reviews-metric__icon" aria-hidden="true">
      <Icon size={22} />
    </div>
    <div>
      <p className="lead-reviews-metric__label">{title}</p>
      <p className="lead-reviews-metric__value">
        {formatNullableValue(value)}
      </p>
    </div>
  </article>
);

const DailyProgress = ({ task }) => {
  const scoredDays = Number(task.scoredDays);
  const eligibleDays = Number(task.eligibleDays);
  const progressPercent =
    eligibleDays > 0
      ? Math.min(100, Math.max(0, (scoredDays / eligibleDays) * 100))
      : 0;

  return (
    <div className="lead-reviews-progress">
      <span className="lead-reviews-progress__count">
        {task.scoredDays} / {task.eligibleDays}
      </span>
      <span className="lead-reviews-progress__track" aria-hidden="true">
        <span
          className="lead-reviews-progress__fill"
          style={{ width: `${progressPercent}%` }}
        />
      </span>
      <span
        className={`lead-reviews-progress__status ${
          task.dailyScoringComplete
            ? "lead-reviews-progress__status--complete"
            : "lead-reviews-progress__status--pending"
        }`}
      >
        {task.dailyScoringComplete ? "Complete" : "Pending"}
      </span>
    </div>
  );
};

const WorkspaceState = ({ icon: Icon, title, children, role = "status" }) => (
  <section
    className="lead-reviews-state"
    role={role}
    aria-live={role === "alert" ? undefined : "polite"}
  >
    <div className="lead-reviews-state__icon" aria-hidden="true">
      <Icon size={22} />
    </div>
    <div className="lead-reviews-state__content">
      <div>
        {title && <h2>{title}</h2>}
        {children}
      </div>
    </div>
  </section>
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
    <main className="app-page lead-reviews-page">
      <header className="lead-reviews-hero">
        <div className="lead-reviews-hero__icon" aria-hidden="true">
          <ClipboardCheck size={32} />
        </div>
        <div className="lead-reviews-hero__content">
          <p className="lead-reviews-hero__eyebrow">Performance Review</p>
          <h1>Lead Reviews</h1>
          <p>
            Review candidate performance for the cycles and pods assigned to
            you.
          </p>
        </div>
      </header>

      {!hasLeadReviewAccess ? (
        <WorkspaceState
          icon={AlertCircle}
          title="Lead Review workspace access unavailable"
        >
          <p>Your account does not have access to Lead Review tasks.</p>
        </WorkspaceState>
      ) : isLoading ? (
        <WorkspaceState icon={LoaderCircle}>
          <p>Loading Lead Reviews...</p>
        </WorkspaceState>
      ) : pageError ? (
        <WorkspaceState icon={AlertCircle} role="alert">
          <p>{pageError}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </WorkspaceState>
      ) : tasks.length === 0 ? (
        <WorkspaceState icon={Inbox}>
          <p>
            No Lead Review tasks are currently available for your assigned
            pods.
          </p>
        </WorkspaceState>
      ) : (
        <>
          <section
            className="lead-reviews-overview"
            aria-labelledby="lead-review-overview-heading"
          >
            <div className="lead-reviews-section-heading">
              <div
                className="lead-reviews-section-heading__icon"
                aria-hidden="true"
              >
                <Users size={20} />
              </div>
              <div>
                <h2 id="lead-review-overview-heading">Review Overview</h2>
                <p>Your assigned Lead Review workload at a glance.</p>
              </div>
            </div>
            <div className="lead-reviews-metrics-grid">
              <MetricCard
                icon={Users}
                title="Total Tasks"
                value={metrics.total}
                tone="blue"
              />
              <MetricCard
                icon={ClipboardCheck}
                title="Ready to Review"
                value={metrics.ready}
                tone="indigo"
              />
              <MetricCard
                icon={FilePenLine}
                title="Draft Reviews"
                value={metrics.draft}
                tone="amber"
              />
              <MetricCard
                icon={CheckCircle2}
                title="Submitted Reviews"
                value={metrics.submitted}
                tone="emerald"
              />
              <MetricCard
                icon={Clock3}
                title="Waiting for Daily Marking"
                value={metrics.waiting}
                tone="orange"
              />
            </div>
          </section>

          <section
            className="lead-reviews-workspace"
            aria-labelledby="lead-review-tasks-heading"
          >
            <div className="lead-reviews-workspace__header">
              <div className="lead-reviews-section-heading">
                <div
                  className="lead-reviews-section-heading__icon"
                  aria-hidden="true"
                >
                  <ListChecks size={20} />
                </div>
                <div>
                  <h2 id="lead-review-tasks-heading">Review Tasks</h2>
                  <p>
                    Find and manage candidate reviews for your assigned pods.
                  </p>
                </div>
              </div>

              <div
                className="lead-reviews-tabs"
                aria-label="Review task category"
              >
                {Object.keys(TASK_CATEGORIES).map((category) => (
                  <button
                    key={category}
                    className="lead-reviews-tab"
                    type="button"
                    aria-pressed={selectedCategory === category}
                    onClick={() => setSelectedCategory(category)}
                  >
                    {formatStatus(category)}
                  </button>
                ))}
              </div>
            </div>

            <div className="lead-reviews-filters">
              <div className="lead-reviews-filters__heading">
                <SlidersHorizontal size={18} aria-hidden="true" />
                <span>Filter review tasks</span>
              </div>
              <div className="lead-reviews-filters__grid">
                <div className="lead-reviews-field">
                  <label htmlFor="lead-review-search">Search Candidate</label>
                  <div className="lead-reviews-search-control">
                    <Search size={18} aria-hidden="true" />
                    <input
                      id="lead-review-search"
                      className="lead-reviews-control lead-reviews-control--search"
                      type="search"
                      value={searchTerm}
                      onChange={(event) => setSearchTerm(event.target.value)}
                      placeholder="Search name, role, or role code"
                    />
                  </div>
                </div>
                <div className="lead-reviews-field">
                  <label htmlFor="lead-review-pod-filter">Pod</label>
                  <select
                    id="lead-review-pod-filter"
                    className="lead-reviews-control"
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
                <div className="lead-reviews-field">
                  <label htmlFor="lead-review-cycle-filter">Cycle</label>
                  <select
                    id="lead-review-cycle-filter"
                    className="lead-reviews-control"
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
            </div>

            {filteredTasks.length === 0 ? (
              <WorkspaceState icon={Inbox}>
                <p>No Lead Review tasks match the selected filters.</p>
              </WorkspaceState>
            ) : (
              <div className="lead-reviews-table-wrap">
                <table className="lead-reviews-table">
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
                      <tr
                        key={task.candidateCycleId}
                        className={
                          task.reviewDisplayStatus ===
                          "WAITING_FOR_DAILY_MARKING"
                            ? "lead-reviews-row--waiting"
                            : undefined
                        }
                      >
                        <td>
                          <strong className="lead-reviews-candidate-name">
                            {task.fullName}
                          </strong>
                        </td>
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
                          <DailyProgress task={task} />
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
                          <div className="lead-reviews-table__action">
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

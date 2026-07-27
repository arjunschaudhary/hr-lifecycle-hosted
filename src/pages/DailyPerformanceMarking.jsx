import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import { Link, useParams } from "react-router-dom";
import { ClipboardCheck } from "lucide-react";
import { useAuth } from "../context/authContext";
import {
  DAILY_PERFORMANCE_REASON_OPTIONS,
  fetchCandidateDailyPerformanceEntries,
  saveCandidateDailyPerformanceEntry,
} from "../services/dailyPerformanceService";

const EMPTY_VALUE = "—";
const PROTECTED_RESULT_STATUSES = new Set([
  "CANDIDATE_REVIEW",
  "FINALIZED",
  "LOCKED",
]);
const PROTECTED_CYCLE_STATUSES = new Set([
  "DRAFT",
  "FINALIZED",
  "LOCKED",
]);
const SCORE_OPTIONS = Array.from({ length: 11 }, (_, index) => index - 5);
const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

const formatDate = (value) => {
  if (typeof value !== "string") {
    return EMPTY_VALUE;
  }

  const dateParts = value.split("-").map(Number);

  if (
    dateParts.length !== 3 ||
    dateParts.some((part) => !Number.isInteger(part))
  ) {
    return EMPTY_VALUE;
  }

  const [year, month, day] = dateParts;
  const date = new Date(Date.UTC(year, month - 1, day));

  if (
    Number.isNaN(date.getTime()) ||
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return EMPTY_VALUE;
  }

  return DATE_FORMATTER.format(date);
};

const formatStatus = (value) => {
  if (typeof value !== "string" || value.trim() === "") {
    return EMPTY_VALUE;
  }

  return value
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
};

const formatValue = (value) =>
  value === null || value === undefined || value === ""
    ? EMPTY_VALUE
    : value;

const buildDrafts = (rows) =>
  Object.fromEntries(
    rows.map((row) => [
      row.performanceDate,
      {
        workDeliveryScore:
          row.workDeliveryScore === null
            ? ""
            : String(row.workDeliveryScore),
        communicationResponsibilityScore:
          row.communicationResponsibilityScore === null
            ? ""
            : String(row.communicationResponsibilityScore),
        reasonCode: row.reasonCode ?? "",
        reviewerComment: row.reviewerComment ?? "",
      },
    ])
  );

const parseDraftScore = (value) => {
  if (value === "") {
    return null;
  }

  const score = Number(value);
  return Number.isInteger(score) && score >= -5 && score <= 5
    ? score
    : null;
};

const getDraftTotal = (draft) => {
  if (!draft) {
    return null;
  }

  const workDeliveryScore = parseDraftScore(draft.workDeliveryScore);
  const communicationScore = parseDraftScore(
    draft.communicationResponsibilityScore
  );

  return workDeliveryScore === null || communicationScore === null
    ? null
    : workDeliveryScore + communicationScore;
};

const getAvailabilityLabel = (row) => {
  if (row.isScorable) {
    return "Scorable";
  }

  const labels = {
    SUNDAY: "Sunday",
    APPROVED_LEAVE: "Approved Leave",
    FUTURE_DATE: "Future Date",
  };

  return labels[row.exclusionReason] || "Not Scorable";
};

const getReasonLabel = (reasonCode) =>
  DAILY_PERFORMANCE_REASON_OPTIONS.find(
    (option) => option.value === reasonCode
  )?.label || EMPTY_VALUE;

const MetricCard = ({ title, value }) => (
  <article className="metric-card">
    <p className="metric-title">{title}</p>
    <p className="metric-value">{formatValue(value)}</p>
  </article>
);

const removeMessage = (messages, performanceDate) => {
  if (!Object.prototype.hasOwnProperty.call(messages, performanceDate)) {
    return messages;
  }

  const nextMessages = { ...messages };
  delete nextMessages[performanceDate];
  return nextMessages;
};

const DailyPerformanceMarking = () => {
  const { candidateCycleId } = useParams();
  const {
    hasPerformanceDashboardAccess,
    hasPerformanceMarkingAccess,
  } = useAuth();
  const [rows, setRows] = useState([]);
  const [drafts, setDrafts] = useState({});
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const [savingPerformanceDates, setSavingPerformanceDates] = useState(
    () => new Set()
  );
  const [rowErrors, setRowErrors] = useState({});
  const [rowSuccessMessages, setRowSuccessMessages] = useState({});

  const loadEntries = useCallback(
    async (isActive) => {
      await Promise.resolve();

      if (!isActive()) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const nextRows =
          await fetchCandidateDailyPerformanceEntries(candidateCycleId);

        if (!isActive()) {
          return;
        }

        setRows(nextRows);
        setDrafts(buildDrafts(nextRows));
        setRowErrors({});
        setRowSuccessMessages({});
      } catch {
        if (isActive()) {
          setPageError("Unable to load daily performance entries.");
        }
      } finally {
        if (isActive()) {
          setIsLoading(false);
        }
      }
    },
    [candidateCycleId]
  );

  useEffect(() => {
    if (!hasPerformanceDashboardAccess) {
      return undefined;
    }

    let isMounted = true;
    void loadEntries(() => isMounted);

    return () => {
      isMounted = false;
    };
  }, [
    hasPerformanceDashboardAccess,
    loadEntries,
    retryRequestId,
  ]);

  const summary = useMemo(() => {
    if (rows.length === 0) {
      return null;
    }

    const firstRow = rows[0];
    const scoredRows = rows.filter((row) => row.entryId !== null);
    const scoredDays = scoredRows.length;
    const dailyAverage =
      scoredDays === 0
        ? null
        : scoredRows.reduce((total, row) => total + row.dailyTotal, 0) /
          scoredDays;
    const dailyComponentScore =
      dailyAverage === null
        ? null
        : ((dailyAverage + 10) / 20) * 50;

    return {
      fullName: firstRow.fullName,
      cycleCode: firstRow.cycleCode,
      cycleStatus: firstRow.cycleStatus,
      podLabel:
        firstRow.podName && firstRow.podCode
          ? `${firstRow.podName} (${firstRow.podCode})`
          : firstRow.podName || firstRow.podCode || EMPTY_VALUE,
      evaluationPeriod: `${formatDate(
        firstRow.evaluationStartDate
      )} - ${formatDate(firstRow.evaluationEndDate)}`,
      resultStatus: firstRow.resultStatus,
      eligibleDays: firstRow.eligibleDays,
      scoredDays,
      dailyAverage,
      dailyComponentScore,
    };
  }, [rows]);

  const isProtectedResult = Boolean(
    summary &&
      PROTECTED_RESULT_STATUSES.has(summary.resultStatus)
  );
  const isProtectedCycle = Boolean(
    summary &&
      PROTECTED_CYCLE_STATUSES.has(summary.cycleStatus)
  );
  const canEdit =
    hasPerformanceMarkingAccess &&
    !isProtectedCycle &&
    !isProtectedResult;

  const handleDraftChange = (performanceDate, field, value) => {
    setDrafts((currentDrafts) => ({
      ...currentDrafts,
      [performanceDate]: {
        ...currentDrafts[performanceDate],
        [field]: value,
      },
    }));
    setRowErrors((currentErrors) =>
      removeMessage(currentErrors, performanceDate)
    );
    setRowSuccessMessages((currentMessages) =>
      removeMessage(currentMessages, performanceDate)
    );
  };

  const handleSave = async (performanceDate) => {
    if (savingPerformanceDates.has(performanceDate)) {
      return;
    }

    const draft = drafts[performanceDate];
    const workDeliveryScore = parseDraftScore(
      draft?.workDeliveryScore ?? ""
    );
    const communicationResponsibilityScore = parseDraftScore(
      draft?.communicationResponsibilityScore ?? ""
    );

    setRowErrors((currentErrors) =>
      removeMessage(currentErrors, performanceDate)
    );
    setRowSuccessMessages((currentMessages) =>
      removeMessage(currentMessages, performanceDate)
    );
    setSavingPerformanceDates((currentDates) => {
      const nextDates = new Set(currentDates);
      nextDates.add(performanceDate);
      return nextDates;
    });

    try {
      await saveCandidateDailyPerformanceEntry({
        candidateCycleId,
        performanceDate,
        workDeliveryScore,
        communicationResponsibilityScore,
        reasonCode: draft?.reasonCode ?? "",
        reviewerComment: draft?.reviewerComment ?? "",
      });

      const refreshedRows =
        await fetchCandidateDailyPerformanceEntries(candidateCycleId);

      setRows(refreshedRows);
      setDrafts(buildDrafts(refreshedRows));
      setRowSuccessMessages((currentMessages) => ({
        ...currentMessages,
        [performanceDate]: "Daily performance saved successfully.",
      }));
    } catch (error) {
      setRowErrors((currentErrors) => ({
        ...currentErrors,
        [performanceDate]:
          error instanceof Error
            ? error.message
            : "Unable to save the daily performance entry.",
      }));
    } finally {
      setSavingPerformanceDates((currentDates) => {
        const nextDates = new Set(currentDates);
        nextDates.delete(performanceDate);
        return nextDates;
      });
    }
  };

  const handleRetry = () => {
    setRetryRequestId((currentRequestId) => currentRequestId + 1);
  };

  return (
    <main className="app-page">
      <Link to="/performance-dashboard" className="back-link">
        Back to Performance Dashboard
      </Link>

      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <ClipboardCheck size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">
            Daily Performance Marking
          </h1>
          <p className="page-subtitle">
            Review and record daily performance scores for the selected
            candidate cycle.
          </p>
        </div>
      </header>

      {!hasPerformanceDashboardAccess ? (
        <section className="info-banner" role="status" aria-live="polite">
          Daily performance access is unavailable.
        </section>
      ) : isLoading ? (
        <p role="status" aria-live="polite">
          Loading daily performance entries...
        </p>
      ) : pageError ? (
        <section className="info-banner" role="alert">
          <p>{pageError}</p>
          <button
            className="btn btn-primary"
            type="button"
            onClick={handleRetry}
          >
            Retry
          </button>
        </section>
      ) : rows.length === 0 ? (
        <p className="info-banner" role="status" aria-live="polite">
          No evaluation dates are available for this candidate cycle.
        </p>
      ) : (
        <>
          <section aria-labelledby="candidate-cycle-summary">
            <h2 id="candidate-cycle-summary">Candidate Cycle Summary</h2>
            <div className="metric-grid">
              <MetricCard
                title="Candidate"
                value={summary.fullName}
              />
              <MetricCard title="Cycle" value={summary.cycleCode} />
              <MetricCard
                title="Cycle Status"
                value={formatStatus(summary.cycleStatus)}
              />
              <MetricCard title="Pod" value={summary.podLabel} />
              <MetricCard
                title="Evaluation Period"
                value={summary.evaluationPeriod}
              />
              <MetricCard
                title="Result Status"
                value={formatStatus(summary.resultStatus)}
              />
              <MetricCard
                title="Scoring Progress"
                value={`${summary.scoredDays} / ${summary.eligibleDays}`}
              />
              <MetricCard
                title="Daily Average"
                value={
                  summary.dailyAverage === null
                    ? EMPTY_VALUE
                    : summary.dailyAverage.toFixed(2)
                }
              />
              <MetricCard
                title="Daily Component Score"
                value={
                  summary.dailyComponentScore === null
                    ? EMPTY_VALUE
                    : `${summary.dailyComponentScore.toFixed(2)} / 50`
                }
              />
            </div>
          </section>

          {isProtectedCycle && (
            <p className="info-banner" role="status" aria-live="polite">
              Daily performance marking is not available for this cycle
              status.
            </p>
          )}

          {isProtectedResult && (
            <p className="info-banner" role="status" aria-live="polite">
              Daily performance can no longer be changed for this result
              status.
            </p>
          )}

          <section aria-labelledby="daily-performance-table">
            <h2 id="daily-performance-table">Daily Entries</h2>
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Availability</th>
                    <th>Work Delivery</th>
                    <th>Communication &amp; Responsibility</th>
                    <th>Daily Total</th>
                    <th>Reason</th>
                    <th>Reviewer Comment</th>
                    <th>Reviewed By</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const draft = drafts[row.performanceDate];
                    const draftTotal = getDraftTotal(draft);
                    const reasonRequired =
                      draftTotal !== null &&
                      (draftTotal <= -5 || draftTotal === 10);
                    const commentRequired = draftTotal === -10;
                    const isSaving = savingPerformanceDates.has(
                      row.performanceDate
                    );
                    const rowIsEditable = canEdit && row.isScorable;

                    return (
                      <tr key={row.performanceDate}>
                        <td>{formatDate(row.performanceDate)}</td>
                        <td>
                          <span
                            className={`badge ${
                              row.isScorable
                                ? "badge-success"
                                : "badge-warning"
                            }`}
                          >
                            {getAvailabilityLabel(row)}
                          </span>
                        </td>
                        <td>
                          {rowIsEditable ? (
                            <select
                              className="form-select"
                              value={draft?.workDeliveryScore ?? ""}
                              onChange={(event) =>
                                handleDraftChange(
                                  row.performanceDate,
                                  "workDeliveryScore",
                                  event.target.value
                                )
                              }
                              aria-label={`Work Delivery score for ${row.performanceDate}`}
                            >
                              <option value="">Select score</option>
                              {SCORE_OPTIONS.map((score) => (
                                <option key={score} value={score}>
                                  {score}
                                </option>
                              ))}
                            </select>
                          ) : (
                            formatValue(row.workDeliveryScore)
                          )}
                        </td>
                        <td>
                          {rowIsEditable ? (
                            <select
                              className="form-select"
                              value={
                                draft?.communicationResponsibilityScore ??
                                ""
                              }
                              onChange={(event) =>
                                handleDraftChange(
                                  row.performanceDate,
                                  "communicationResponsibilityScore",
                                  event.target.value
                                )
                              }
                              aria-label={`Communication and Responsibility score for ${row.performanceDate}`}
                            >
                              <option value="">Select score</option>
                              {SCORE_OPTIONS.map((score) => (
                                <option key={score} value={score}>
                                  {score}
                                </option>
                              ))}
                            </select>
                          ) : (
                            formatValue(
                              row.communicationResponsibilityScore
                            )
                          )}
                        </td>
                        <td>
                          {rowIsEditable
                            ? formatValue(draftTotal)
                            : formatValue(row.dailyTotal)}
                        </td>
                        <td>
                          {rowIsEditable ? (
                            <>
                              <label
                                htmlFor={`reason-${row.performanceDate}`}
                              >
                                Reason
                                {reasonRequired && (
                                  <span
                                    className="required"
                                    aria-hidden="true"
                                  >
                                    *
                                  </span>
                                )}
                              </label>
                              <select
                                id={`reason-${row.performanceDate}`}
                                className="form-select"
                                value={draft?.reasonCode ?? ""}
                                onChange={(event) =>
                                  handleDraftChange(
                                    row.performanceDate,
                                    "reasonCode",
                                    event.target.value
                                  )
                                }
                                aria-label={`Reason for ${row.performanceDate}`}
                                aria-required={reasonRequired}
                              >
                                <option value="">Select reason</option>
                                {DAILY_PERFORMANCE_REASON_OPTIONS.map(
                                  (option) => (
                                    <option
                                      key={option.value}
                                      value={option.value}
                                    >
                                      {option.label}
                                    </option>
                                  )
                                )}
                              </select>
                            </>
                          ) : (
                            getReasonLabel(row.reasonCode)
                          )}
                        </td>
                        <td>
                          {rowIsEditable ? (
                            <>
                              <label
                                htmlFor={`comment-${row.performanceDate}`}
                              >
                                Reviewer Comment
                                {commentRequired && (
                                  <span
                                    className="required"
                                    aria-hidden="true"
                                  >
                                    *
                                  </span>
                                )}
                              </label>
                              <textarea
                                id={`comment-${row.performanceDate}`}
                                className="form-input"
                                value={draft?.reviewerComment ?? ""}
                                onChange={(event) =>
                                  handleDraftChange(
                                    row.performanceDate,
                                    "reviewerComment",
                                    event.target.value
                                  )
                                }
                                maxLength={2000}
                                aria-label={`Reviewer comment for ${row.performanceDate}`}
                                aria-required={commentRequired}
                              />
                              <small>
                                {(draft?.reviewerComment ?? "").length} / 2000
                              </small>
                            </>
                          ) : (
                            formatValue(row.reviewerComment)
                          )}
                        </td>
                        <td>{formatValue(row.reviewerName)}</td>
                        <td>
                          <div className="action-group">
                            {rowIsEditable ? (
                              <button
                                className="btn btn-primary"
                                type="button"
                                disabled={isSaving}
                                onClick={() =>
                                  void handleSave(row.performanceDate)
                                }
                              >
                                {isSaving
                                  ? "Saving..."
                                  : row.entryId === null
                                    ? "Save"
                                    : "Update"}
                              </button>
                            ) : (
                              <span>View only</span>
                            )}
                            {rowErrors[row.performanceDate] && (
                              <span role="alert">
                                {rowErrors[row.performanceDate]}
                              </span>
                            )}
                            {rowSuccessMessages[row.performanceDate] && (
                              <span role="status" aria-live="polite">
                                {
                                  rowSuccessMessages[
                                    row.performanceDate
                                  ]
                                }
                              </span>
                            )}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </main>
  );
};

export default DailyPerformanceMarking;

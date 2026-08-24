import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ClipboardCheck } from "lucide-react";

import {
  getCandidateHrReview,
  saveCandidateHrReview,
} from "../services/hrReviewService";
import { fetchCandidatePerformanceList } from "../services/performanceDashboardService";
import { saveCandidateExceptionalScore } from "../services/performanceResultService";

const EMPTY_VALUE = "—";
const SCORE_FIELDS = [
  "communicationProfessionalismScore",
  "attendanceUpdateDisciplineScore",
  "reportingPolicyComplianceScore",
];
const SCORE_OPTIONS = Array.from({ length: 6 }, (_, index) => index);
const TERMINAL_RESULT_STATUSES = new Set([
  "FINALIZED",
  "LOCKED",
  "NOT_EVALUATED",
]);
const CLOSED_CYCLE_STATUSES = new Set(["DRAFT", "FINALIZED", "LOCKED"]);
const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const EMPTY_FORM = {
  communicationProfessionalismScore: "",
  attendanceUpdateDisciplineScore: "",
  reportingPolicyComplianceScore: "",
  reviewerComment: "",
  amendmentReason: "",
};

const formatDate = (value) => {
  if (!value) {
    return EMPTY_VALUE;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? EMPTY_VALUE
    : DATE_FORMATTER.format(date);
};

const formatStatus = (value) => {
  if (!value) {
    return EMPTY_VALUE;
  }

  return value
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
};

const formatNullableValue = (value) =>
  value === null || value === undefined || value === ""
    ? EMPTY_VALUE
    : value;

const getPodLabel = (detail) => {
  if (detail.podName && detail.podCode) {
    return `${detail.podName} (${detail.podCode})`;
  }

  return detail.podName || detail.podCode || EMPTY_VALUE;
};

const getRoleLabel = (detail) => {
  if (detail.appliedRole && detail.roleCode) {
    return `${detail.appliedRole} (${detail.roleCode})`;
  }

  return detail.appliedRole || detail.roleCode || EMPTY_VALUE;
};

const getStatusBadgeClass = (status) => {
  if (status === "READY" || status === "SUBMITTED") {
    return "badge-success";
  }

  if (status === "DRAFT" || status === "WAITING_FOR_DAILY_SCORING") {
    return "badge-warning";
  }

  return "badge-primary";
};

const buildForm = (detail) => ({
  communicationProfessionalismScore:
    detail.communicationProfessionalismScore === null
      ? ""
      : String(detail.communicationProfessionalismScore),
  attendanceUpdateDisciplineScore:
    detail.attendanceUpdateDisciplineScore === null
      ? ""
      : String(detail.attendanceUpdateDisciplineScore),
  reportingPolicyComplianceScore:
    detail.reportingPolicyComplianceScore === null
      ? ""
      : String(detail.reportingPolicyComplianceScore),
  reviewerComment: detail.reviewerComment ?? "",
  amendmentReason: "",
});

const parseScore = (value) => (value === "" ? null : Number(value));

const getCandidatePerformanceRecord = async (candidateCycleId) => {
  const records = await fetchCandidatePerformanceList();
  const record = records.find(
    (candidateRecord) =>
      candidateRecord.candidateCycleId === candidateCycleId,
  );

  if (!record) {
    throw new Error("Candidate performance record is not available.");
  }

  return record;
};

const MetricCard = ({ title, value }) => (
  <article className="metric-card">
    <p className="metric-title">{title}</p>
    <p className="metric-value">{formatNullableValue(value)}</p>
  </article>
);

const ScoreSelect = ({ id, label, value, disabled, onChange }) => (
  <div className="form-group">
    <label htmlFor={id}>{label}</label>
    <select
      id={id}
      className="form-select"
      value={value}
      onChange={onChange}
      disabled={disabled}
    >
      <option value="">Select score</option>
      {SCORE_OPTIONS.map((option) => (
        <option key={option} value={option}>
          {option}
        </option>
      ))}
    </select>
  </div>
);

const HrReviewDetail = () => {
  const { candidateCycleId } = useParams();
  const [detail, setDetail] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [saveSuccess, setSaveSuccess] = useState("");
  const [refreshError, setRefreshError] = useState("");
  const [performanceRecord, setPerformanceRecord] = useState(null);
  const [exceptionalScore, setExceptionalScore] = useState("");
  const [isExceptionalLoading, setIsExceptionalLoading] = useState(true);
  const [isExceptionalSaving, setIsExceptionalSaving] = useState(false);
  const [exceptionalError, setExceptionalError] = useState("");
  const [exceptionalSuccess, setExceptionalSuccess] = useState("");

  useEffect(() => {
    let isMounted = true;

    const loadDetail = async () => {
      await Promise.resolve();

      if (!isMounted) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const nextDetail = await getCandidateHrReview(candidateCycleId);

        if (!isMounted) {
          return;
        }

        setDetail(nextDetail);
        setForm(buildForm(nextDetail));
        setSaveError("");
        setSaveSuccess("");
        setRefreshError("");
      } catch {
        if (isMounted) {
          setPageError("Unable to load the HR Review.");
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    };

    void loadDetail();

    return () => {
      isMounted = false;
    };
  }, [candidateCycleId, retryRequestId]);

  useEffect(() => {
    let isMounted = true;

    const loadExceptionalScore = async () => {
      setIsExceptionalLoading(true);
      setExceptionalError("");

      try {
        const record = await getCandidatePerformanceRecord(candidateCycleId);

        if (!isMounted) {
          return;
        }

        setPerformanceRecord(record);
        setExceptionalScore(
          record.exceptionalScore === null
            ? ""
            : String(record.exceptionalScore),
        );
        setExceptionalSuccess("");
      } catch {
        if (isMounted) {
          setPerformanceRecord(null);
          setExceptionalError(
            "Unable to load the current Exceptional Score.",
          );
        }
      } finally {
        if (isMounted) {
          setIsExceptionalLoading(false);
        }
      }
    };

    void loadExceptionalScore();

    return () => {
      isMounted = false;
    };
  }, [candidateCycleId, retryRequestId]);

  const isEditable = detail?.canEdit === true;
  const isAmendment = Boolean(
    isEditable && detail?.reviewStatus === "SUBMITTED",
  );

  const handleFieldChange = (field, value) => {
    setForm((currentForm) => ({
      ...currentForm,
      [field]: value,
    }));
    setSaveError("");
    setSaveSuccess("");
  };

  const validateSave = (reviewStatus, isAmendmentSave) => {
    const parsedScores = SCORE_FIELDS.map((field) =>
      parseScore(form[field]),
    );
    const hasInvalidScore = parsedScores.some(
      (score) =>
        score !== null &&
        (!Number.isInteger(score) || score < 0 || score > 5),
    );

    if (hasInvalidScore) {
      return "Each HR Review score must be an integer from 0 to 5.";
    }

    if (
      reviewStatus === "SUBMITTED" &&
      parsedScores.some((score) => score === null)
    ) {
      return "All three HR Review scores are required for submission.";
    }

    if (!form.reviewerComment.trim()) {
      return "Reviewer Comment is required.";
    }

    if (isAmendmentSave && !form.amendmentReason.trim()) {
      return "Amendment Reason is required.";
    }

    return "";
  };

  const handleSave = async (reviewStatus) => {
    if (!isEditable || isSaving || refreshError) {
      return;
    }

    const validationError = validateSave(reviewStatus, isAmendment);
    if (validationError) {
      setSaveError(validationError);
      setSaveSuccess("");
      return;
    }

    setIsSaving(true);
    setSaveError("");
    setSaveSuccess("");
    setRefreshError("");

    try {
      await saveCandidateHrReview({
        candidateCycleId,
        communicationProfessionalismScore: parseScore(
          form.communicationProfessionalismScore,
        ),
        attendanceUpdateDisciplineScore: parseScore(
          form.attendanceUpdateDisciplineScore,
        ),
        reportingPolicyComplianceScore: parseScore(
          form.reportingPolicyComplianceScore,
        ),
        reviewerComment: form.reviewerComment,
        reviewStatus,
        amendmentReason: isAmendment ? form.amendmentReason : null,
      });
    } catch {
      setSaveError("Unable to save the HR Review.");
      setIsSaving(false);
      return;
    }

    const successMessage = isAmendment
      ? "HR Review amendment saved successfully."
      : reviewStatus === "SUBMITTED"
        ? "HR Review submitted successfully."
        : "HR Review draft saved successfully.";

    setSaveSuccess(successMessage);
    setForm((currentForm) => ({
      ...currentForm,
      amendmentReason: "",
    }));

    try {
      const nextDetail = await getCandidateHrReview(candidateCycleId);

      setDetail(nextDetail);
      setForm(buildForm(nextDetail));
    } catch {
      setRefreshError(
        "The HR Review was saved, but the refreshed details could not be loaded.",
      );
    } finally {
      setIsSaving(false);
    }
  };

  const handleRetryRefresh = async () => {
    if (isRefreshing || isSaving) {
      return;
    }

    setIsRefreshing(true);

    try {
      const nextDetail = await getCandidateHrReview(candidateCycleId);

      setDetail(nextDetail);
      setForm(buildForm(nextDetail));
      setRefreshError("");
    } catch {
      setRefreshError(
        "The HR Review was saved, but the refreshed details could not be loaded.",
      );
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleSaveExceptionalScore = async () => {
    if (!exceptionalCanEdit || isExceptionalSaving) {
      return;
    }

    const normalizedValue = exceptionalScore.trim();

    if (!normalizedValue) {
      setExceptionalError("Exceptional Score is required.");
      setExceptionalSuccess("");
      return;
    }

    const parsedValue = Number(normalizedValue);

    if (
      !Number.isFinite(parsedValue) ||
      parsedValue < 0 ||
      parsedValue > 10
    ) {
      setExceptionalError("Exceptional Score must be between 0 and 10.");
      setExceptionalSuccess("");
      return;
    }

    setIsExceptionalSaving(true);
    setExceptionalError("");
    setExceptionalSuccess("");

    try {
      await saveCandidateExceptionalScore(candidateCycleId, parsedValue);
    } catch {
      setExceptionalError("Unable to save the Exceptional Score.");
      setIsExceptionalSaving(false);
      return;
    }

    try {
      const [nextDetail, nextPerformanceRecord] = await Promise.all([
        getCandidateHrReview(candidateCycleId),
        getCandidatePerformanceRecord(candidateCycleId),
      ]);

      setDetail(nextDetail);
      setForm(buildForm(nextDetail));
      setPerformanceRecord(nextPerformanceRecord);
      setExceptionalScore(String(nextPerformanceRecord.exceptionalScore));
      setExceptionalSuccess("Exceptional Score saved successfully.");
    } catch {
      setExceptionalError(
        "The Exceptional Score was saved, but the refreshed details could not be loaded.",
      );
    } finally {
      setIsExceptionalSaving(false);
    }
  };

  const readOnlyMessage =
    detail?.editReason || "HR Review editing is not available for this cycle.";
  const isFormDisabled =
    !isEditable || isSaving || isRefreshing || Boolean(refreshError);
  const performanceResultStatus =
    performanceRecord?.resultStatus || detail?.resultStatus;
  const isNotEvaluated = performanceResultStatus === "NOT_EVALUATED";
  const exceptionalCanEdit = Boolean(
    detail &&
      performanceRecord &&
      detail.dailyScoringComplete &&
      detail.reviewIsOpen &&
      !CLOSED_CYCLE_STATUSES.has(detail.cycleStatus) &&
      !TERMINAL_RESULT_STATUSES.has(performanceResultStatus),
  );
  const exceptionalReadOnlyMessage = isNotEvaluated
    ? "Not Evaluated — No eligible working days."
    : TERMINAL_RESULT_STATUSES.has(performanceResultStatus)
      ? "Exceptional Score is read-only because this result is final."
      : "Exceptional Score becomes editable when Daily scoring is complete and the review window is open.";
  const subtitle = detail
    ? `${detail.fullName} - ${detail.cycleCode}`
    : "Review candidate performance for the selected cycle.";

  return (
    <main className="app-page">
      <Link className="back-link" to="/performance/hr-review">
        Back to HR Review
      </Link>

      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <ClipboardCheck size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">HR Review</h1>
          <p className="page-subtitle">{subtitle}</p>
        </div>
      </header>

      {isLoading ? (
        <p role="status" aria-live="polite">
          Loading HR Review...
        </p>
      ) : pageError ? (
        <section className="info-banner" role="alert">
          <p>{pageError}</p>
          <button
            className="btn btn-primary"
            type="button"
            onClick={() =>
              setRetryRequestId(
                (currentRequestId) => currentRequestId + 1,
              )
            }
          >
            Retry
          </button>
        </section>
      ) : !detail ? (
        <p className="info-banner" role="status" aria-live="polite">
          HR Review details are not available.
        </p>
      ) : (
        <>
          <section aria-labelledby="hr-review-summary-heading">
            <h2 id="hr-review-summary-heading">Assignment Summary</h2>
            <div className="metric-grid">
              <MetricCard title="Candidate" value={detail.fullName} />
              <MetricCard title="Email" value={detail.email} />
              <MetricCard title="Applied Role" value={getRoleLabel(detail)} />
              <MetricCard title="Pod" value={getPodLabel(detail)} />
              <MetricCard title="Cycle" value={detail.cycleCode} />
              <MetricCard
                title="Evaluation Period"
                value={`${formatDate(
                  detail.evaluationStartDate,
                )} - ${formatDate(detail.evaluationEndDate)}`}
              />
              <MetricCard
                title="Daily Progress"
                value={`${detail.scoredDays} / ${detail.eligibleDays}`}
              />
              <MetricCard
                title="Task Status"
                value={
                  <span
                    className={`badge ${getStatusBadgeClass(
                      detail.taskStatus,
                    )}`}
                  >
                    {formatStatus(detail.taskStatus)}
                  </span>
                }
              />
              <MetricCard
                title="HR Review Score"
                value={
                  detail.totalScore === null
                    ? EMPTY_VALUE
                    : `${detail.totalScore} / 15`
                }
              />
              <MetricCard
                title="Submitted On"
                value={formatDate(detail.submittedAt)}
              />
              <MetricCard
                title="Reviewer"
                value={formatNullableValue(detail.reviewerName)}
              />
            </div>
          </section>

          <section aria-labelledby="hr-review-form-heading">
            <h2 id="hr-review-form-heading">HR Review Scores</h2>

            {!isEditable && (
              <p className="info-banner" role="status" aria-live="polite">
                {readOnlyMessage}
              </p>
            )}

            <form onSubmit={(event) => event.preventDefault()}>
              <div className="form-grid">
                <ScoreSelect
                  id="hr-review-communication-professionalism"
                  label="Communication & Professionalism"
                  value={form.communicationProfessionalismScore}
                  disabled={isFormDisabled}
                  onChange={(event) =>
                    handleFieldChange(
                      "communicationProfessionalismScore",
                      event.target.value,
                    )
                  }
                />
                <ScoreSelect
                  id="hr-review-attendance-update-discipline"
                  label="Attendance & Update Discipline"
                  value={form.attendanceUpdateDisciplineScore}
                  disabled={isFormDisabled}
                  onChange={(event) =>
                    handleFieldChange(
                      "attendanceUpdateDisciplineScore",
                      event.target.value,
                    )
                  }
                />
                <ScoreSelect
                  id="hr-review-reporting-policy-compliance"
                  label="Reporting & Policy Compliance"
                  value={form.reportingPolicyComplianceScore}
                  disabled={isFormDisabled}
                  onChange={(event) =>
                    handleFieldChange(
                      "reportingPolicyComplianceScore",
                      event.target.value,
                    )
                  }
                />
                <div className="form-group">
                  <label htmlFor="hr-review-comment">Reviewer Comment</label>
                  <textarea
                    id="hr-review-comment"
                    className="form-input"
                    value={form.reviewerComment}
                    onChange={(event) =>
                      handleFieldChange(
                        "reviewerComment",
                        event.target.value,
                      )
                    }
                    maxLength={2000}
                    required={isEditable}
                    disabled={isFormDisabled}
                  />
                </div>
                {isAmendment && (
                  <div className="form-group">
                    <label htmlFor="hr-review-amendment-reason">
                      Amendment Reason
                    </label>
                    <textarea
                      id="hr-review-amendment-reason"
                      className="form-input"
                      value={form.amendmentReason}
                      onChange={(event) =>
                        handleFieldChange(
                          "amendmentReason",
                          event.target.value,
                        )
                      }
                      maxLength={2000}
                      required
                      disabled={isFormDisabled}
                    />
                  </div>
                )}
              </div>

              {saveError && (
                <p className="info-banner" role="alert">
                  {saveError}
                </p>
              )}
              {saveSuccess && (
                <p className="info-banner" role="status" aria-live="polite">
                  {saveSuccess}
                </p>
              )}
              {refreshError && (
                <section className="info-banner" role="alert">
                  <p>{refreshError}</p>
                  <button
                    className="btn btn-primary"
                    type="button"
                    disabled={isRefreshing}
                    onClick={() => void handleRetryRefresh()}
                  >
                    {isRefreshing ? "Refreshing..." : "Retry Refresh"}
                  </button>
                </section>
              )}

              {isEditable && !isAmendment && (
                <div className="action-group">
                  <button
                    className="btn"
                    type="button"
                    disabled={isSaving || Boolean(refreshError)}
                    onClick={() => void handleSave("DRAFT")}
                  >
                    {isSaving ? "Saving..." : "Save Draft"}
                  </button>
                  <button
                    className="btn btn-primary"
                    type="button"
                    disabled={isSaving || Boolean(refreshError)}
                    onClick={() => void handleSave("SUBMITTED")}
                  >
                    {isSaving ? "Submitting..." : "Submit HR Review"}
                  </button>
                </div>
              )}

              {isAmendment && (
                <div className="action-group">
                  <button
                    className="btn btn-primary"
                    type="button"
                    disabled={isSaving || Boolean(refreshError)}
                    onClick={() => void handleSave("SUBMITTED")}
                  >
                    {isSaving ? "Saving..." : "Save Amendment"}
                  </button>
                </div>
              )}
            </form>
          </section>

          <section aria-labelledby="exceptional-score-heading">
            <h2 id="exceptional-score-heading">Exceptional Score</h2>
            <p className="page-subtitle">
              Record the separate Exceptional contribution component. This
              does not change the HR Review /15 fields.
            </p>

            {isExceptionalLoading ? (
              <p role="status" aria-live="polite">
                Loading Exceptional Score...
              </p>
            ) : (
              <form onSubmit={(event) => event.preventDefault()}>
                <div className="form-grid">
                  <div className="form-group">
                    <label htmlFor="candidate-exceptional-score">
                      Exceptional Score <span>/10</span>
                    </label>
                    <input
                      id="candidate-exceptional-score"
                      className="form-input"
                      type="number"
                      min="0"
                      max="10"
                      step="0.01"
                      inputMode="decimal"
                      value={exceptionalScore}
                      onChange={(event) => {
                        setExceptionalScore(event.target.value);
                        setExceptionalError("");
                        setExceptionalSuccess("");
                      }}
                      disabled={!exceptionalCanEdit || isExceptionalSaving}
                    />
                  </div>
                  <MetricCard
                    title="Current Saved Value"
                    value={
                      performanceRecord?.exceptionalScore === null ||
                      performanceRecord?.exceptionalScore === undefined
                        ? EMPTY_VALUE
                        : `${performanceRecord.exceptionalScore} / 10`
                    }
                  />
                </div>

                {!exceptionalCanEdit && !exceptionalError && (
                  <p className="info-banner" role="status" aria-live="polite">
                    {exceptionalReadOnlyMessage}
                  </p>
                )}
                {exceptionalError && (
                  <p className="info-banner" role="alert">
                    {exceptionalError}
                  </p>
                )}
                {exceptionalSuccess && (
                  <p className="info-banner" role="status" aria-live="polite">
                    {exceptionalSuccess}
                  </p>
                )}

                {exceptionalCanEdit && (
                  <div className="action-group">
                    <button
                      className="btn btn-primary"
                      type="button"
                      disabled={isExceptionalSaving}
                      onClick={() => void handleSaveExceptionalScore()}
                    >
                      {isExceptionalSaving
                        ? "Saving..."
                        : "Save Exceptional Score"}
                    </button>
                  </div>
                )}
              </form>
            )}
          </section>
        </>
      )}
    </main>
  );
};

export default HrReviewDetail;

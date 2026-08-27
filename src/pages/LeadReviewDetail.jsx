import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ClipboardCheck } from "lucide-react";

import { useAuth } from "../context/authContext";
import {
  fetchCandidateLeadReview,
  fetchLeadReviewTasks,
  saveCandidateLeadReview,
} from "../services/leadReviewService";

const EMPTY_VALUE = "—";
const SCORE_FIELDS = [
  "workQualityScore",
  "roleCapabilityScore",
  "deadlineDeliveryScore",
  "ownershipTeamworkScore",
];
const WORK_QUALITY_OPTIONS = Array.from(
  { length: 11 },
  (_, index) => index,
);
const FIVE_POINT_OPTIONS = Array.from(
  { length: 6 },
  (_, index) => index,
);
const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const EMPTY_FORM = {
  workQualityScore: "",
  roleCapabilityScore: "",
  deadlineDeliveryScore: "",
  ownershipTeamworkScore: "",
  reviewerComment: "",
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

const buildForm = (detail) => ({
  workQualityScore:
    detail.workQualityScore === null
      ? ""
      : String(detail.workQualityScore),
  roleCapabilityScore:
    detail.roleCapabilityScore === null
      ? ""
      : String(detail.roleCapabilityScore),
  deadlineDeliveryScore:
    detail.deadlineDeliveryScore === null
      ? ""
      : String(detail.deadlineDeliveryScore),
  ownershipTeamworkScore:
    detail.ownershipTeamworkScore === null
      ? ""
      : String(detail.ownershipTeamworkScore),
  reviewerComment: detail.reviewerComment ?? "",
});

const parseScore = (value) => (value === "" ? null : Number(value));

const MetricCard = ({ title, value }) => (
  <article className="metric-card">
    <p className="metric-title">{title}</p>
    <p className="metric-value">{formatNullableValue(value)}</p>
  </article>
);

const ScoreSelect = ({
  id,
  label,
  value,
  options,
  disabled,
  onChange,
}) => (
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
      {options.map((option) => (
        <option key={option} value={option}>
          {option}
        </option>
      ))}
    </select>
  </div>
);

const LeadReviewDetail = () => {
  const { candidateCycleId } = useParams();
  const { hasLeadReviewAccess, user } = useAuth();
  const [detail, setDetail] = useState(null);
  const [taskCanEdit, setTaskCanEdit] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [retryRequestId, setRetryRequestId] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [saveSuccess, setSaveSuccess] = useState("");

  useEffect(() => {
    if (!hasLeadReviewAccess) {
      return undefined;
    }

    let isMounted = true;

    const loadDetail = async () => {
      await Promise.resolve();

      if (!isMounted) {
        return;
      }

      setIsLoading(true);
      setPageError("");

      try {
        const [nextDetail, tasks] = await Promise.all([
          fetchCandidateLeadReview(candidateCycleId),
          fetchLeadReviewTasks(),
        ]);

        if (!isMounted) {
          return;
        }

        const currentTask = tasks.find(
          (task) => task.candidateCycleId === candidateCycleId,
        );

        setDetail(nextDetail);
        setTaskCanEdit(currentTask?.canEdit === true);
        setForm(buildForm(nextDetail));
        setSaveError("");
        setSaveSuccess("");
      } catch {
        if (isMounted) {
          setPageError("Unable to load the Lead Review.");
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
  }, [candidateCycleId, hasLeadReviewAccess, retryRequestId]);

  const totalScore = useMemo(
    () =>
      SCORE_FIELDS.reduce(
        (total, field) => total + (parseScore(form[field]) ?? 0),
        0,
      ),
    [form],
  );

  const allScoresSelected = SCORE_FIELDS.every(
    (field) => form[field] !== "",
  );
  const isEditable = Boolean(
    detail &&
      detail.reviewIsOpen &&
      detail.dailyScoringComplete &&
      detail.reviewStatus !== "SUBMITTED" &&
      taskCanEdit,
  );
  const isOwnedByAnotherReviewer = Boolean(
    detail?.reviewStatus === "DRAFT" &&
      detail.reviewerUserId &&
      detail.reviewerUserId !== user?.id,
  );

  const handleFieldChange = (field, value) => {
    setForm((currentForm) => ({
      ...currentForm,
      [field]: value,
    }));
    setSaveError("");
    setSaveSuccess("");
  };

  const handleSave = async (reviewStatus) => {
    if (!isEditable || isSaving) {
      return;
    }

    setIsSaving(true);
    setSaveError("");
    setSaveSuccess("");

    try {
      await saveCandidateLeadReview({
        candidateCycleId,
        workQualityScore: parseScore(form.workQualityScore),
        roleCapabilityScore: parseScore(form.roleCapabilityScore),
        deadlineDeliveryScore: parseScore(form.deadlineDeliveryScore),
        ownershipTeamworkScore: parseScore(form.ownershipTeamworkScore),
        reviewerComment: form.reviewerComment,
        reviewStatus,
      });

      const [nextDetail, tasks] = await Promise.all([
        fetchCandidateLeadReview(candidateCycleId),
        fetchLeadReviewTasks(),
      ]);
      const currentTask = tasks.find(
        (task) => task.candidateCycleId === candidateCycleId,
      );

      setDetail(nextDetail);
      setTaskCanEdit(currentTask?.canEdit === true);
      setForm(buildForm(nextDetail));
      setSaveSuccess(
        reviewStatus === "SUBMITTED"
          ? "Lead Review submitted successfully."
          : "Lead Review draft saved successfully.",
      );
    } catch (error) {
      setSaveError(
        error instanceof Error
          ? error.message
          : "Unable to save the Lead Review.",
      );
    } finally {
      setIsSaving(false);
    }
  };

  const getReadOnlyMessage = () => {
    if (isOwnedByAnotherReviewer) {
      return "This Lead Review is being handled by another reviewer.";
    }

    if (detail?.reviewStatus === "SUBMITTED") {
      return "This Lead Review has been submitted and is read-only.";
    }

    if (detail && !detail.dailyScoringComplete) {
      return "Daily performance scoring must be complete before the Lead Review can be edited.";
    }

    return "Lead Review editing is not available for this cycle.";
  };

  return (
    <main className="app-page">
      <Link className="back-link" to="/lead-reviews">
        Back to Lead Reviews
      </Link>

      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <ClipboardCheck size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">Lead Review</h1>
          <p className="page-subtitle">
            Review the candidate&apos;s performance for this cycle.
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
          Loading Lead Review...
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
          Lead Review details are not available.
        </p>
      ) : (
        <>
          <section aria-labelledby="lead-review-summary-heading">
            <h2 id="lead-review-summary-heading">Review Summary</h2>
            <div className="metric-grid">
              <MetricCard title="Candidate" value={detail.fullName} />
              <MetricCard title="Cycle" value={detail.cycleCode} />
              <MetricCard
                title="Cycle Status"
                value={formatStatus(detail.cycleStatus)}
              />
              <MetricCard title="Pod" value={getPodLabel(detail)} />
              <MetricCard
                title="Evaluation Period"
                value={`${formatDate(
                  detail.evaluationStartDate,
                )} - ${formatDate(detail.evaluationEndDate)}`}
              />
              <MetricCard
                title="Result Status"
                value={formatStatus(detail.resultStatus)}
              />
              <MetricCard
                title="Daily Progress"
                value={`${detail.scoredDays} / ${detail.eligibleDays}`}
              />
              <MetricCard
                title="Daily Component Score"
                value={
                  detail.dailyComponentScore === null
                    ? EMPTY_VALUE
                    : `${detail.dailyComponentScore} / 50`
                }
              />
              <MetricCard
                title="Review Status"
                value={
                  detail.reviewStatus
                    ? formatStatus(detail.reviewStatus)
                    : "Not Started"
                }
              />
              <MetricCard
                title="Reviewer"
                value={formatNullableValue(detail.reviewerName)}
              />
              <MetricCard
                title="Submitted On"
                value={formatDate(detail.submittedAt)}
              />
            </div>
          </section>

          <section aria-labelledby="lead-review-form-heading">
            <h2 id="lead-review-form-heading">Lead Review Scores</h2>

            {!isEditable && (
              <p className="info-banner" role="status" aria-live="polite">
                {getReadOnlyMessage()}
              </p>
            )}

            <form onSubmit={(event) => event.preventDefault()}>
              <div className="form-grid">
                <ScoreSelect
                  id="lead-review-work-quality"
                  label="Work Quality"
                  value={form.workQualityScore}
                  options={WORK_QUALITY_OPTIONS}
                  disabled={!isEditable || isSaving}
                  onChange={(event) =>
                    handleFieldChange(
                      "workQualityScore",
                      event.target.value,
                    )
                  }
                />
                <ScoreSelect
                  id="lead-review-role-capability"
                  label="Role Capability"
                  value={form.roleCapabilityScore}
                  options={FIVE_POINT_OPTIONS}
                  disabled={!isEditable || isSaving}
                  onChange={(event) =>
                    handleFieldChange(
                      "roleCapabilityScore",
                      event.target.value,
                    )
                  }
                />
                <ScoreSelect
                  id="lead-review-deadline-delivery"
                  label="Deadline Delivery"
                  value={form.deadlineDeliveryScore}
                  options={FIVE_POINT_OPTIONS}
                  disabled={!isEditable || isSaving}
                  onChange={(event) =>
                    handleFieldChange(
                      "deadlineDeliveryScore",
                      event.target.value,
                    )
                  }
                />
                <ScoreSelect
                  id="lead-review-ownership-teamwork"
                  label="Ownership & Teamwork"
                  value={form.ownershipTeamworkScore}
                  options={FIVE_POINT_OPTIONS}
                  disabled={!isEditable || isSaving}
                  onChange={(event) =>
                    handleFieldChange(
                      "ownershipTeamworkScore",
                      event.target.value,
                    )
                  }
                />
                <div className="form-group">
                  <label htmlFor="lead-review-comment">
                    Reviewer Comment
                  </label>
                  <textarea
                    id="lead-review-comment"
                    className="form-input"
                    value={form.reviewerComment}
                    onChange={(event) =>
                      handleFieldChange(
                        "reviewerComment",
                        event.target.value,
                      )
                    }
                    maxLength={2000}
                    disabled={!isEditable || isSaving}
                  />
                </div>
              </div>

              <p>
                <strong>Calculated Total:</strong> {totalScore} / 25
              </p>

              {saveError && (
                <p className="info-banner" role="alert">
                  {saveError}
                </p>
              )}
              {saveSuccess && (
                <p
                  className="info-banner"
                  role="status"
                  aria-live="polite"
                >
                  {saveSuccess}
                </p>
              )}

              {isEditable && (
                <div className="action-group">
                  <button
                    className="btn"
                    type="button"
                    disabled={isSaving}
                    onClick={() => void handleSave("DRAFT")}
                  >
                    {isSaving ? "Saving..." : "Save Draft"}
                  </button>
                  <button
                    className="btn btn-primary"
                    type="button"
                    disabled={isSaving || !allScoresSelected}
                    onClick={() => void handleSave("SUBMITTED")}
                  >
                    {isSaving ? "Submitting..." : "Submit Review"}
                  </button>
                </div>
              )}
            </form>
          </section>
        </>
      )}
    </main>
  );
};

export default LeadReviewDetail;

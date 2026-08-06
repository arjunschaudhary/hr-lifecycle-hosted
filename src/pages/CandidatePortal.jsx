import { useEffect, useMemo, useRef, useState } from "react";
import { BriefcaseBusiness } from "lucide-react";

import { useAuth } from "../context/authContext";
import {
  CANDIDATE_LEAVE_TYPES,
  fetchCurrentCandidateLeaveRequests,
  submitCurrentCandidateLeaveRequest,
} from "../services/candidateLeaveService";
import { fetchCurrentCandidatePortalSummary } from "../services/candidatePortalService";
import { submitCurrentCandidateSignedOffer } from "../services/candidateSignedOfferUploadService";
import { calculateLeaveDays } from "../utils/leaveRules";

const INITIAL_LEAVE_FORM = {
  leaveType: "Casual Leave",
  startDate: "",
  endDate: "",
  reason: "",
  supportingDocument: "",
};

const formatValue = (value) => {
  if (value === null || value === undefined) {
    return "";
  }

  const normalizedValue = String(value).trim();
  return normalizedValue || "";
};

const formatStatus = (value) =>
  formatValue(value)
    .toLowerCase()
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");

const formatDate = (value) => {
  const normalizedValue = formatValue(value);

  if (!normalizedValue) {
    return "";
  }

  const date = /^\d{4}-\d{2}-\d{2}$/.test(normalizedValue)
    ? (() => {
        const [year, month, day] = normalizedValue.split("-").map(Number);
        return new Date(year, month - 1, day);
      })()
    : new Date(normalizedValue);

  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return new Intl.DateTimeFormat("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(date);
};

const formatDuration = (value) => {
  const duration = Number(value);

  if (!Number.isFinite(duration)) {
    return "";
  }

  return `${duration} month${duration === 1 ? "" : "s"}`;
};

const formatFileSize = (value) => {
  const size = Number(value);

  if (!Number.isFinite(size) || size <= 0) {
    return "";
  }

  if (size < 1024) {
    return `${size} bytes`;
  }

  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`;
  }

  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
};

function SummaryFields({ fields }) {
  const availableFields = fields.filter((field) => field.value);

  if (availableFields.length === 0) {
    return <p className="page-subtitle">No information available.</p>;
  }

  return (
    <div className="candidate-details-grid">
      {availableFields.map((field) => (
        <div className="candidate-detail-card" key={field.label}>
          <span>{field.label}</span>
          <strong>{field.value}</strong>
        </div>
      ))}
    </div>
  );
}

function SummaryCard({ title, children }) {
  return (
    <section className="card" aria-labelledby={`${title.toLowerCase().replaceAll(" ", "-")}-title`}>
      <h2 id={`${title.toLowerCase().replaceAll(" ", "-")}-title`}>{title}</h2>
      {children}
    </section>
  );
}

const getLeaveStatusBadgeClass = (status) => {
  if (status === "APPROVED") {
    return "badge-success";
  }

  if (status === "REJECTED") {
    return "badge-warning";
  }

  return "badge-primary";
};

function CandidateLeaveSection({
  form,
  requestedLeaveDays,
  exceedsRemainingLeave,
  hasPendingRequest,
  history,
  historyLoading,
  historyError,
  submitting,
  submissionError,
  submissionSuccess,
  onChange,
  onSubmit,
  onRetryHistory,
}) {
  const applicationDisabled =
    submitting || historyLoading || hasPendingRequest;

  return (
    <>
      <SummaryCard title="Leave Application">
        {hasPendingRequest && (
          <div className="info-banner" role="status" aria-live="polite">
            You already have a pending leave request. Wait for HR to review it
            before submitting another.
          </div>
        )}

        <form onSubmit={onSubmit} noValidate>
          <div className="form-group">
            <label htmlFor="candidate-leave-type">Leave Type</label>
            <select
              id="candidate-leave-type"
              className="form-select"
              name="leaveType"
              value={form.leaveType}
              onChange={onChange}
              disabled={applicationDisabled}
              required
            >
              {CANDIDATE_LEAVE_TYPES.map((leaveType) => (
                <option key={leaveType} value={leaveType}>
                  {leaveType}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label htmlFor="candidate-leave-start-date">Start Date</label>
            <input
              id="candidate-leave-start-date"
              name="startDate"
              type="date"
              value={form.startDate}
              onChange={onChange}
              disabled={applicationDisabled}
              required
            />
          </div>

          <div className="form-group">
            <label htmlFor="candidate-leave-end-date">End Date</label>
            <input
              id="candidate-leave-end-date"
              name="endDate"
              type="date"
              value={form.endDate}
              onChange={onChange}
              disabled={applicationDisabled}
              required
            />
          </div>

          {requestedLeaveDays !== null && (
            <p className="page-subtitle" role="status" aria-live="polite">
              Requested leave days, excluding Sundays: {requestedLeaveDays}
            </p>
          )}

          {exceedsRemainingLeave && (
            <div className="info-banner" role="status" aria-live="polite">
              This request exceeds your remaining leave balance. Add a
              supporting document link before submitting.
            </div>
          )}

          <div className="form-group">
            <label htmlFor="candidate-leave-reason">Reason</label>
            <textarea
              id="candidate-leave-reason"
              className="form-textarea"
              name="reason"
              rows="4"
              value={form.reason}
              onChange={onChange}
              disabled={applicationDisabled}
              required
            />
          </div>

          <div className="form-group">
            <label htmlFor="candidate-leave-supporting-document">
              Supporting Document Link
              {exceedsRemainingLeave ? " (required)" : " (optional)"}
            </label>
            <input
              id="candidate-leave-supporting-document"
              name="supportingDocument"
              type="url"
              value={form.supportingDocument}
              onChange={onChange}
              disabled={applicationDisabled}
              required={exceedsRemainingLeave}
              aria-describedby="candidate-leave-supporting-document-help"
              placeholder="https://example.com/document"
            />
            <p
              id="candidate-leave-supporting-document-help"
              className="page-subtitle"
            >
              Required when requested leave exceeds your remaining balance.
            </p>
          </div>

          {submissionError && (
            <p className="auth-inline-error" role="alert">
              {submissionError}
            </p>
          )}

          {submissionSuccess && (
            <p className="auth-success-message" role="status" aria-live="polite">
              {submissionSuccess}
            </p>
          )}

          <button
            className="btn btn-primary"
            type="submit"
            disabled={applicationDisabled}
            aria-busy={submitting}
          >
            {submitting
              ? "Submitting..."
              : hasPendingRequest
                ? "Pending HR Review"
                : "Submit Leave Request"}
          </button>
        </form>
      </SummaryCard>

      <SummaryCard title="Leave Request History">
        {historyLoading && (
          <p role="status" aria-live="polite">
            Loading leave-request history...
          </p>
        )}

        {!historyLoading && historyError && (
          <div role="alert">
            <p className="auth-inline-error">{historyError}</p>
            <button
              className="btn btn-primary"
              type="button"
              onClick={onRetryHistory}
            >
              Retry
            </button>
          </div>
        )}

        {!historyLoading && !historyError && history.length === 0 && (
          <p className="page-subtitle" role="status" aria-live="polite">
            No leave requests submitted yet.
          </p>
        )}

        {!historyLoading && !historyError && history.length > 0 && (
          <div className="table-container">
            <table>
              <thead>
                <tr>
                  <th>Leave Type</th>
                  <th>Period</th>
                  <th>Days</th>
                  <th>Reason</th>
                  <th>Document</th>
                  <th>Submitted</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {history.map((request) => (
                  <tr key={request.leaveRequestId}>
                    <td>{request.leaveType}</td>
                    <td>
                      {formatDate(request.startDate)} - {formatDate(request.endDate)}
                    </td>
                    <td>{request.requestedLeaveDays}</td>
                    <td>{formatValue(request.reason) || "-"}</td>
                    <td>
                      {request.supportingDocument ? (
                        <a
                          href={request.supportingDocument}
                          target="_blank"
                          rel="noreferrer"
                        >
                          View document
                        </a>
                      ) : (
                        "-"
                      )}
                    </td>
                    <td>{formatDate(request.createdAt) || "-"}</td>
                    <td>
                      <span
                        className={`badge ${getLeaveStatusBadgeClass(
                          request.leaveStatus,
                        )}`}
                      >
                        {formatStatus(request.leaveStatus)}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </SummaryCard>
    </>
  );
}

function PortalSummary({
  summary,
  selectedFile,
  uploadLoading,
  fileInputRef,
  onFileChange,
  onSubmit,
  children,
}) {
  const profile = summary.profile;
  const internship = summary.internship;
  const leave = summary.leave;
  const signedOffer = summary.signedOffer;

  const profileFields = [
    { label: "Full Name", value: formatValue(profile.fullName) },
    { label: "Email", value: formatValue(profile.email) },
    { label: "Phone", value: formatValue(profile.phone) },
    { label: "Alternate Phone", value: formatValue(profile.alternatePhone) },
    { label: "Address", value: formatValue(profile.address) },
    { label: "City", value: formatValue(profile.city) },
    { label: "State", value: formatValue(profile.state) },
    { label: "Applied Role", value: formatValue(profile.appliedRole) },
    { label: "Role Code", value: formatValue(profile.roleCode) },
    { label: "Department", value: formatValue(profile.department) },
    { label: "Qualification", value: formatValue(profile.qualification) },
    { label: "College", value: formatValue(profile.collegeName) },
    { label: "Availability", value: formatValue(profile.availabilityStatus) },
    { label: "MID", value: formatValue(profile.mid) },
  ];

  const internshipFields = [
    { label: "Start Date", value: formatDate(internship.startDate) },
    { label: "Current End Date", value: formatDate(internship.currentEndDate) },
    {
      label: "Internship Duration",
      value: formatDuration(internship.internshipDurationMonths),
    },
    { label: "Lifecycle Status", value: formatStatus(internship.lifecycleStatus) },
  ];

  const signedOfferFields = [
    {
      label: "Current Status",
      value: formatStatus(signedOffer.status) || "Not submitted",
    },
    { label: "Submitted Date", value: formatDate(signedOffer.submittedAt) },
    { label: "Verified Date", value: formatDate(signedOffer.verifiedAt) },
  ];

  return (
    <>
      <SummaryCard title="Personal Information">
        <SummaryFields fields={profileFields} />
      </SummaryCard>

      <SummaryCard title="Internship Information">
        <SummaryFields fields={internshipFields} />
      </SummaryCard>

      <SummaryCard title="Leave Summary">
        {leave.available ? (
          <SummaryFields
            fields={[
              { label: "Allocated Leave", value: formatValue(leave.allocatedLeaveDays) },
              { label: "Approved Leave", value: formatValue(leave.approvedLeaveDays) },
              { label: "Remaining Leave", value: formatValue(leave.remainingLeaveDays) },
              { label: "Extra Leave", value: formatValue(leave.extraLeaveDays) },
            ]}
          />
        ) : (
          <p>Leave balance not available.</p>
        )}
      </SummaryCard>

      {children}

      <SummaryCard title="Signed Offer">
        <SummaryFields fields={signedOfferFields} />
        {signedOffer.canSubmit && (
          <form onSubmit={onSubmit} noValidate>
            <div className="form-group">
              <label htmlFor="signed-offer-file">Signed offer PDF</label>
              <input
                ref={fileInputRef}
                id="signed-offer-file"
                type="file"
                accept=".pdf,application/pdf"
                onChange={onFileChange}
                disabled={signedOffer.canSubmit === false || uploadLoading}
                aria-describedby="signed-offer-file-help"
              />
              <p id="signed-offer-file-help" className="page-subtitle">
                PDF only, maximum 10 MB.
              </p>
              {selectedFile && (
                <p className="page-subtitle">
                  Selected file: <strong>{selectedFile.name}</strong> ({formatFileSize(selectedFile.size)})
                </p>
              )}
            </div>
            <button
              className="btn btn-primary"
              type="submit"
              disabled={!signedOffer.canSubmit || !selectedFile || uploadLoading}
              aria-busy={uploadLoading}
            >
              {uploadLoading ? "Uploading..." : "Submit Signed Offer"}
            </button>
          </form>
        )}
      </SummaryCard>

      <SummaryCard title="Performance">
        <span className="badge badge-info">Coming next</span>
      </SummaryCard>
    </>
  );
}

export default function CandidatePortal() {
  const { user, candidateId } = useAuth();
  const [summary, setSummary] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retryKey, setRetryKey] = useState(0);
  const [selectedFile, setSelectedFile] = useState(null);
  const [uploadLoading, setUploadLoading] = useState(false);
  const [uploadError, setUploadError] = useState("");
  const [uploadSuccess, setUploadSuccess] = useState("");
  const [leaveForm, setLeaveForm] = useState(INITIAL_LEAVE_FORM);
  const [leaveRequests, setLeaveRequests] = useState([]);
  const [leaveHistoryLoading, setLeaveHistoryLoading] = useState(true);
  const [leaveHistoryError, setLeaveHistoryError] = useState("");
  const [leaveSubmitting, setLeaveSubmitting] = useState(false);
  const [leaveSubmissionError, setLeaveSubmissionError] = useState("");
  const [leaveSubmissionSuccess, setLeaveSubmissionSuccess] = useState("");
  const [leaveHistoryRetryKey, setLeaveHistoryRetryKey] = useState(0);
  const fileInputRef = useRef(null);

  const requestedLeaveDays = useMemo(() => {
    if (!leaveForm.startDate || !leaveForm.endDate) {
      return null;
    }

    try {
      return calculateLeaveDays(leaveForm.startDate, leaveForm.endDate);
    } catch {
      return null;
    }
  }, [leaveForm.endDate, leaveForm.startDate]);

  const rawRemainingLeaveDays = summary?.leave?.remainingLeaveDays;
  const remainingLeaveDays =
    rawRemainingLeaveDays !== null &&
    rawRemainingLeaveDays !== undefined &&
    rawRemainingLeaveDays !== ""
      ? Number(rawRemainingLeaveDays)
      : null;
  const exceedsRemainingLeave =
    requestedLeaveDays !== null &&
    remainingLeaveDays !== null &&
    Number.isFinite(remainingLeaveDays) &&
    requestedLeaveDays > remainingLeaveDays;
  const hasPendingLeaveRequest = leaveRequests.some(
    (request) => request.leaveStatus === "PENDING",
  );

  useEffect(() => {
    let isMounted = true;

    const loadSummary = async () => {
      try {
        const nextSummary = await fetchCurrentCandidatePortalSummary();

        if (!isMounted) {
          return;
        }

        setSummary(nextSummary);
        setError("");
      } catch (loadError) {
        if (!isMounted) {
          return;
        }

        setSummary(null);
        setError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to load your candidate portal summary.",
        );
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    };

    void loadSummary();

    return () => {
      isMounted = false;
    };
  }, [retryKey]);

  useEffect(() => {
    let isMounted = true;

    const loadLeaveHistory = async () => {
      try {
        const nextRequests = await fetchCurrentCandidateLeaveRequests();

        if (!isMounted) {
          return;
        }

        setLeaveRequests(nextRequests);
        setLeaveHistoryError("");
      } catch (loadError) {
        if (!isMounted) {
          return;
        }

        setLeaveRequests([]);
        setLeaveHistoryError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to load your leave-request history.",
        );
      } finally {
        if (isMounted) {
          setLeaveHistoryLoading(false);
        }
      }
    };

    void loadLeaveHistory();

    return () => {
      isMounted = false;
    };
  }, [leaveHistoryRetryKey]);

  const handleRetry = () => {
    setLoading(true);
    setError("");
    setSummary(null);
    setRetryKey((currentKey) => currentKey + 1);
  };

  const resetFileInput = () => {
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  const handleFileChange = (event) => {
    setUploadError("");
    setUploadSuccess("");
    setSelectedFile(event.target.files?.[0] || null);
  };

  const handleLeaveFormChange = (event) => {
    const { name, value } = event.target;

    setLeaveForm((currentForm) => ({
      ...currentForm,
      [name]: value,
    }));
    setLeaveSubmissionError("");
    setLeaveSubmissionSuccess("");
  };

  const handleRetryLeaveHistory = () => {
    setLeaveHistoryLoading(true);
    setLeaveHistoryError("");
    setLeaveHistoryRetryKey((currentKey) => currentKey + 1);
  };

  const handleSubmitLeaveRequest = async (event) => {
    event.preventDefault();

    if (leaveSubmitting || hasPendingLeaveRequest) {
      return;
    }

    setLeaveSubmitting(true);
    setLeaveSubmissionError("");
    setLeaveSubmissionSuccess("");

    try {
      const submittedRequest = await submitCurrentCandidateLeaveRequest({
        ...leaveForm,
        remainingLeaveDays: summary?.leave?.remainingLeaveDays,
      });

      setLeaveForm(INITIAL_LEAVE_FORM);
      setLeaveRequests((currentRequests) => [
        submittedRequest,
        ...currentRequests.filter(
          (request) => request.leaveRequestId !== submittedRequest.leaveRequestId,
        ),
      ]);
      setLeaveSubmissionSuccess("Leave request submitted successfully.");
      setLeaveHistoryLoading(true);
      setLeaveHistoryRetryKey((currentKey) => currentKey + 1);

      try {
        const nextSummary = await fetchCurrentCandidatePortalSummary();
        setSummary(nextSummary);
      } catch {
        setLeaveSubmissionError(
          "Your leave request was submitted, but the refreshed leave balance could not be loaded.",
        );
      }
    } catch (submitError) {
      setLeaveSubmissionError(
        submitError instanceof Error
          ? submitError.message
          : "Unable to submit your leave request.",
      );
    } finally {
      setLeaveSubmitting(false);
    }
  };

  const handleSubmitSignedOffer = async (event) => {
    event.preventDefault();

    if (!summary?.signedOffer?.canSubmit || !selectedFile || uploadLoading) {
      return;
    }

    const authenticatedCandidateId = formatValue(candidateId);
    const summaryCandidateId = formatValue(summary.profile?.candidateId);

    if (
      authenticatedCandidateId &&
      summaryCandidateId &&
      authenticatedCandidateId.toLowerCase() !== summaryCandidateId.toLowerCase()
    ) {
      setUploadError("Candidate reference could not be verified.");
      setUploadSuccess("");
      return;
    }

    const uploadCandidateId = authenticatedCandidateId || summaryCandidateId;

    setUploadLoading(true);
    setUploadError("");
    setUploadSuccess("");

    try {
      await submitCurrentCandidateSignedOffer({
        candidateId: uploadCandidateId,
        file: selectedFile,
      });

      setSelectedFile(null);
      resetFileInput();
      setUploadSuccess("Signed offer submitted successfully.");
      setLoading(true);
      setSummary(null);
      setRetryKey((currentKey) => currentKey + 1);
    } catch (submitError) {
      const safeMessage =
        submitError instanceof Error
          ? submitError.message
          : "Unable to complete the signed-offer submission. Please try again.";

      setUploadError(safeMessage);
      setUploadSuccess("");

      if (safeMessage.includes("clean up") || safeMessage.includes("contact HR")) {
        setSelectedFile(null);
        resetFileInput();
      }
    } finally {
      setUploadLoading(false);
    }
  };

  return (
    <main className="app-page">
      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <BriefcaseBusiness />
        </div>
        <div>
          <h1 className="page-title-modern">Candidate Portal</h1>
          <p className="page-subtitle">Your secure candidate workspace.</p>
        </div>
      </header>

      <section className="card" aria-labelledby="candidate-account-title">
        <h2 id="candidate-account-title">Account</h2>
        <p>
          Signed in as <strong>{user?.email || "Unknown account"}</strong>
        </p>
        <span className="badge badge-success">Portal account active</span>
      </section>

      <section className="card" aria-labelledby="candidate-reference-title">
        <h2 id="candidate-reference-title">Candidate reference</h2>

        <p>
          MID:{" "}
          <strong>
            {loading
              ? "Loading..."
              : formatValue(summary?.profile?.mid) || "Not generated yet"}
          </strong>
        </p>

      </section>

      {loading && (
        <section className="card" role="status" aria-live="polite">
          <p>Loading candidate portal summary...</p>
        </section>
      )}

      {!loading && error && (
        <section className="card" role="alert" aria-labelledby="candidate-summary-error-title">
          <h2 id="candidate-summary-error-title">Portal summary unavailable</h2>
          <p>{error}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      )}

      {!loading && !error && !summary && (
        <section className="card" aria-labelledby="candidate-summary-empty-title">
          <h2 id="candidate-summary-empty-title">No portal summary available</h2>
          <p>Candidate information is not available yet.</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      )}

      {!loading && !error && summary && (
        <PortalSummary
          summary={summary}
          selectedFile={selectedFile}
          uploadLoading={uploadLoading}
          fileInputRef={fileInputRef}
          onFileChange={handleFileChange}
          onSubmit={handleSubmitSignedOffer}
        >
          <CandidateLeaveSection
            form={leaveForm}
            requestedLeaveDays={requestedLeaveDays}
            exceedsRemainingLeave={exceedsRemainingLeave}
            hasPendingRequest={hasPendingLeaveRequest}
            history={leaveRequests}
            historyLoading={leaveHistoryLoading}
            historyError={leaveHistoryError}
            submitting={leaveSubmitting}
            submissionError={leaveSubmissionError}
            submissionSuccess={leaveSubmissionSuccess}
            onChange={handleLeaveFormChange}
            onSubmit={handleSubmitLeaveRequest}
            onRetryHistory={handleRetryLeaveHistory}
          />
        </PortalSummary>
      )}

      {uploadError && (
        <section className="card card-danger" role="alert">
          <p className="auth-inline-error">{uploadError}</p>
        </section>
      )}

      {uploadSuccess && (
        <section className="card card-success" role="status" aria-live="polite">
          <p className="auth-success-message">{uploadSuccess}</p>
        </section>
      )}
    </main>
  );
}

import { useEffect, useMemo, useRef, useState } from "react";


import { Link } from "react-router-dom";
import { BriefcaseBusiness, ClipboardList } from "lucide-react";

import { useAuth } from "../context/authContext";
import {
  CANDIDATE_LEAVE_TYPES,
  fetchCurrentCandidateLeaveRequests,
  submitCurrentCandidateLeaveRequest,
  uploadLeaveDocument,
  deleteLeaveDocument,
  getSupportingDocumentUrl,
} from "../services/candidateLeaveService";
import { fetchCurrentCandidatePortalSummary } from "../services/candidatePortalService";
import { submitCurrentCandidateSignedOffer, resubmitCurrentCandidateSignedOffer } from "../services/candidateSignedOfferUploadService";
import { fetchCurrentCandidatePerformanceHistory } from "../services/candidatePerformanceService";
import { calculateLeaveDays, getTodayKolkataString } from "../utils/leaveRules";

const INITIAL_LEAVE_FORM = {
  leaveType: "Casual Leave",
  startDate: "",
  endDate: "",
  reason: "",
  supportingDocument: "",
  otherLeaveTypeReason: "",
};
import { getCandidateExitCase } from "../services/exitService";

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

const getPerformanceBandBadgeClass = (band) => {
  if (band === "OUTSTANDING" || band === "EXCELLENT") return "badge-success";
  if (band === "GOOD") return "badge-info";
  if (band === "SATISFACTORY") return "badge-warning";
  return "badge-secondary";
};

function CandidatePerformanceSection({ cycles, loading, error }) {
  if (loading) {
    return (
      <SummaryCard title="Performance History">
        <p role="status" aria-live="polite">Loading performance history...</p>
      </SummaryCard>
    );
  }

  if (error) {
    return (
      <SummaryCard title="Performance History">
        <p className="auth-inline-error" role="alert">{error}</p>
      </SummaryCard>
    );
  }

  return (
    <SummaryCard title="Performance History">
      {cycles.length === 0 ? (
        <p className="page-subtitle">No performance cycles available yet.</p>
      ) : (
        <div className="table-wrapper">
          <table>
            <thead>
              <tr>
                <th>Cycle</th>
                <th>Period</th>
                <th>Your Evaluation Period</th>
                <th>Status</th>
                <th>Band</th>
                <th>Final Score</th>
              </tr>
            </thead>
            <tbody>
              {cycles.map((cycle) => (
                <tr key={cycle.candidateCycleId}>
                  <td>
                    <strong>{cycle.cycleCode}</strong>
                    {cycle.isPartialCycle && (
                      <> <span className="badge badge-secondary" style={{ fontSize: "11px" }}>Partial</span></>
                    )}
                  </td>
                  <td>
                    {formatDate(cycle.cycleStartDate)}
                    {" – "}
                    {formatDate(cycle.cycleEndDate)}
                  </td>
                  <td>
                    {formatDate(cycle.evaluationStartDate)}
                    {" – "}
                    {formatDate(cycle.evaluationEndDate)}
                  </td>
                  <td>
                    <span className={`badge ${cycle.cycleStatus === "LOCKED" || cycle.cycleStatus === "COMPLETED" ? "badge-success" : "badge-warning"}`}>
                      {formatStatus(cycle.cycleStatus)}
                    </span>
                  </td>
                  <td>
                    {cycle.performanceBand ? (
                      <span className={`badge ${getPerformanceBandBadgeClass(cycle.performanceBand)}`}>
                        {formatStatus(cycle.performanceBand)}
                      </span>
                    ) : (
                      <span className="page-subtitle">—</span>
                    )}
                  </td>
                  <td>
                    {cycle.finalResultReady && cycle.finalScore !== null
                      ? `${cycle.finalScore}`
                      : <span className="page-subtitle">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </SummaryCard>
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
  selectedFile,
  fileInputRef,
  onFileChange,
  onRemoveFile,
  onViewDocument,
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

          {form.leaveType === "Other" && (
            <div className="form-group">
              <label htmlFor="candidate-leave-other-reason">
                Specify Reason *
              </label>
              <input
                id="candidate-leave-other-reason"
                name="otherLeaveTypeReason"
                type="text"
                value={form.otherLeaveTypeReason || ""}
                onChange={onChange}
                disabled={applicationDisabled}
                required
                placeholder="e.g. Personal work at bank"
              />
            </div>
          )}

          <div className="form-group">
            <label htmlFor="candidate-leave-start-date">Start Date</label>
            <input
              id="candidate-leave-start-date"
              name="startDate"
              type="date"
              value={form.startDate}
              onChange={onChange}
              disabled={applicationDisabled}
              min={getTodayKolkataString()}
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
              min={form.startDate || getTodayKolkataString()}
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
              supporting document PDF before submitting.
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
              Supporting Document
              {exceedsRemainingLeave ? " (required)" : " (optional)"}
            </label>
            <input
              ref={fileInputRef}
              id="candidate-leave-supporting-document"
              name="supportingDocumentFile"
              type="file"
              accept=".pdf,application/pdf"
              onChange={onFileChange}
              disabled={applicationDisabled}
              required={exceedsRemainingLeave}
              aria-describedby="candidate-leave-supporting-document-help"
            />
            <p
              id="candidate-leave-supporting-document-help"
              className="page-subtitle"
            >
              PDF only, maximum 10 MB. Required when requested leave exceeds your remaining balance.
            </p>
            {selectedFile && (
              <div style={{ display: "flex", alignItems: "center", gap: "8px", marginTop: "8px" }}>
                <span className="page-subtitle" style={{ margin: 0 }}>
                  Selected file: <strong>{selectedFile.name}</strong> ({formatFileSize(selectedFile.size)})
                </span>
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  style={{ padding: "2px 8px", fontSize: "12px" }}
                  onClick={onRemoveFile}
                  disabled={applicationDisabled}
                >
                  Remove
                </button>
              </div>
            )}
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
                    <td>
                      {request.leaveType === "Other" && request.otherLeaveTypeReason
                        ? `Other (${request.otherLeaveTypeReason})`
                        : request.leaveType}
                    </td>
                    <td>
                      {formatDate(request.startDate)} - {formatDate(request.endDate)}
                    </td>
                    <td>{request.requestedLeaveDays}</td>
                    <td>{formatValue(request.reason) || "-"}</td>
                    <td>
                      {request.supportingDocument ? (
                        <button
                          type="button"
                          className="candidate-link"
                          onClick={() => onViewDocument(request.supportingDocument)}
                        >
                          View document
                        </button>
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
  exitCase,
  selectedFile,
  uploadLoading,
  resubmitLoading,
  fileInputRef,
  resubmitFileInputRef,
  selectedResubmitFile,
  onFileChange,
  onResubmitFileChange,
  onSubmit,
  onResubmit,
  performanceCycles,
  performanceLoading,
  performanceError,
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


  return (
    <>
      <SummaryCard title="Personal Information">
        <SummaryFields fields={profileFields} />
      </SummaryCard>

      <SummaryCard title="Internship Information">
        <SummaryFields fields={internshipFields} />
      </SummaryCard>

      {exitCase && (
        <SummaryCard title="Exit Questionnaire">
          {exitCase.candidate_form_completed ? (
            <div>
              <div style={{ marginBottom: 12 }}>
                <span className="badge badge-success">
                  Exit Questionnaire Submitted
                </span>
              </div>
              <p className="page-subtitle" style={{ margin: 0 }}>
                Thank you! Your exit feedback has already been recorded.
              </p>
            </div>
          ) : (
            <div>
              <p className="page-subtitle" style={{ marginBottom: 16 }}>
                An exit process has been initiated for your internship. Please complete your exit questionnaire.
              </p>
              <Link to="/candidate-exit-form" className="btn btn-primary" style={{ textDecoration: "none", display: "inline-flex", alignItems: "center", gap: 8 }}>
                <ClipboardList size={18} />
                Complete Exit Questionnaire
              </Link>
            </div>
          )}
        </SummaryCard>
      )}

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

      <CandidateSignedOfferSection
        signedOffer={signedOffer}
        selectedFile={selectedFile}
        uploadLoading={uploadLoading}
        resubmitLoading={resubmitLoading}
        fileInputRef={fileInputRef}
        resubmitFileInputRef={resubmitFileInputRef}
        selectedResubmitFile={selectedResubmitFile}
        onFileChange={onFileChange}
        onResubmitFileChange={onResubmitFileChange}
        onSubmit={onSubmit}
        onResubmit={onResubmit}
      />

      <CandidatePerformanceSection
        cycles={performanceCycles}
        loading={performanceLoading}
        error={performanceError}
      />
    </>
  );
}

function CandidateSignedOfferSection({
  signedOffer,
  selectedFile,
  uploadLoading,
  resubmitLoading,
  fileInputRef,
  resubmitFileInputRef,
  selectedResubmitFile,
  onFileChange,
  onResubmitFileChange,
  onSubmit,
  onResubmit,
}) {
  const status = signedOffer?.status;
  const canSubmit = signedOffer?.canSubmit;
  const canResubmit = signedOffer?.canResubmit;
  const verificationNotes = signedOffer?.verificationNotes;

  const signedOfferFields = [
    {
      label: "Current Status",
      value: formatStatus(status) || "Not submitted",
    },
    { label: "Submitted Date", value: formatDate(signedOffer?.submittedAt) },
    { label: "Verified Date", value: formatDate(signedOffer?.verifiedAt) },
  ];

  return (
    <SummaryCard title="Signed Offer">
      <SummaryFields fields={signedOfferFields} />

      {/* ── Verified (accepted) ─────────────────────────────── */}
      {status === "SIGNED_OFFER_VERIFIED" && (
        <div style={{ marginTop: 12 }}>
          <span className="badge badge-success">Signed offer verified</span>
        </div>
      )}

      {/* ── Pending review ───────────────────────────────────── */}
      {status === "SIGNED_OFFER_SUBMITTED" && (
        <div style={{ marginTop: 12 }}>
          <span className="badge badge-info">Pending HR review</span>
        </div>
      )}

      {/* ── Rejected / MISMATCH_REVIEW ───────────────────────── */}
      {canResubmit && (
        <div
          style={{
            marginTop: 16,
            padding: "14px 16px",
            borderRadius: 8,
            border: "1.5px solid var(--color-danger, #e53e3e)",
            background: "rgba(229,62,62,0.06)",
          }}
          role="alert"
          aria-labelledby="signed-offer-rejected-title"
        >
          <h3
            id="signed-offer-rejected-title"
            style={{
              margin: "0 0 6px",
              fontSize: "0.97rem",
              color: "var(--color-danger, #e53e3e)",
            }}
          >
            Signed offer requires correction
          </h3>
          <p className="page-subtitle" style={{ margin: "0 0 10px" }}>
            HR reviewed your signed offer and found a mismatch. Please
            upload a corrected copy.
          </p>
          {verificationNotes && (
            <div
              style={{
                padding: "8px 12px",
                borderRadius: 6,
                background: "rgba(229,62,62,0.08)",
                marginBottom: 14,
              }}
            >
              <p
                className="page-subtitle"
                style={{ margin: 0, fontWeight: 600, marginBottom: 2 }}
              >
                HR note:
              </p>
              <p className="page-subtitle" style={{ margin: 0 }}>
                {verificationNotes}
              </p>
            </div>
          )}
          <form onSubmit={onResubmit} noValidate>
            <div className="form-group">
              <label htmlFor="signed-offer-resubmit-file">
                Upload corrected signed offer PDF
              </label>
              <input
                ref={resubmitFileInputRef}
                id="signed-offer-resubmit-file"
                type="file"
                accept=".pdf,application/pdf"
                onChange={onResubmitFileChange}
                disabled={resubmitLoading}
                aria-describedby="signed-offer-resubmit-file-help"
              />
              <p
                id="signed-offer-resubmit-file-help"
                className="page-subtitle"
              >
                PDF only, maximum 10 MB.
              </p>
              {selectedResubmitFile && (
                <p className="page-subtitle">
                  Selected file:{" "}
                  <strong>{selectedResubmitFile.name}</strong>{" "}
                  ({formatFileSize(selectedResubmitFile.size)})
                </p>
              )}
            </div>
            <button
              className="btn btn-primary"
              type="submit"
              id="signed-offer-resubmit-btn"
              disabled={!selectedResubmitFile || resubmitLoading}
              aria-busy={resubmitLoading}
            >
              {resubmitLoading ? "Uploading..." : "Re-upload Signed Offer"}
            </button>
          </form>
        </div>
      )}

      {/* ── First-time submission form ────────────────────────── */}
      {canSubmit && (
        <form onSubmit={onSubmit} noValidate style={{ marginTop: 12 }}>
          <div className="form-group">
            <label htmlFor="signed-offer-file">Signed offer PDF</label>
            <input
              ref={fileInputRef}
              id="signed-offer-file"
              type="file"
              accept=".pdf,application/pdf"
              onChange={onFileChange}
              disabled={!canSubmit || uploadLoading}
              aria-describedby="signed-offer-file-help"
            />
            <p id="signed-offer-file-help" className="page-subtitle">
              PDF only, maximum 10 MB.
            </p>
            {selectedFile && (
              <p className="page-subtitle">
                Selected file: <strong>{selectedFile.name}</strong> (
                {formatFileSize(selectedFile.size)})
              </p>
            )}
          </div>
          <button
            className="btn btn-primary"
            type="submit"
            disabled={!canSubmit || !selectedFile || uploadLoading}
            aria-busy={uploadLoading}
          >
            {uploadLoading ? "Uploading..." : "Submit Signed Offer"}
          </button>
        </form>
      )}
    </SummaryCard>
  );
}

export default function CandidatePortal() {
  const { user, candidateId } = useAuth();
  const [summary, setSummary] = useState(null);
  const [exitCase, setExitCase] = useState(null);
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
  const [selectedLeaveFile, setSelectedLeaveFile] = useState(null);
  const leaveFileInputRef = useRef(null);
  const [performanceCycles, setPerformanceCycles] = useState([]);
  const [performanceLoading, setPerformanceLoading] = useState(true);
  const [performanceError, setPerformanceError] = useState("");
  const [selectedResubmitFile, setSelectedResubmitFile] = useState(null);
  const [resubmitLoading, setResubmitLoading] = useState(false);
  const [resubmitError, setResubmitError] = useState("");
  const [resubmitSuccess, setResubmitSuccess] = useState("");
  const resubmitFileInputRef = useRef(null);

  const handleLeaveFileChange = (event) => {
    setLeaveSubmissionError("");
    setLeaveSubmissionSuccess("");
    const file = event.target.files?.[0] || null;
    if (file) {
      if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
        setLeaveSubmissionError("Only PDF files are allowed.");
        setSelectedLeaveFile(null);
        if (leaveFileInputRef.current) {
          leaveFileInputRef.current.value = "";
        }
        return;
      }
      if (file.size > 10 * 1024 * 1024) {
        setLeaveSubmissionError("PDF file size must be no larger than 10 MB.");
        setSelectedLeaveFile(null);
        if (leaveFileInputRef.current) {
          leaveFileInputRef.current.value = "";
        }
        return;
      }
    }
    setSelectedLeaveFile(file);
  };

  const handleRemoveLeaveFile = () => {
    setSelectedLeaveFile(null);
    if (leaveFileInputRef.current) {
      leaveFileInputRef.current.value = "";
    }
  };

  const handleViewLeaveDocument = async (docRef) => {
    if (!docRef) return;
    if (docRef.startsWith("http://") || docRef.startsWith("https://")) {
      window.open(docRef, "_blank", "noopener,noreferrer");
      return;
    }
    try {
      const url = await getSupportingDocumentUrl(docRef);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      alert("Unable to view document: " + err.message);
    }
  };

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
        const [nextSummary, nextExitCase] = await Promise.all([
          fetchCurrentCandidatePortalSummary(),
          getCandidateExitCase().catch(() => null),
        ]);

        if (!isMounted) {
          return;
        }

        setSummary(nextSummary);
        setExitCase(nextExitCase);
        setError("");
      } catch (loadError) {
        if (!isMounted) {
          return;
        }

        setSummary(null);
        setExitCase(null);
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

  useEffect(() => {
    let isMounted = true;

    const loadPerformanceHistory = async () => {
      try {
        const cycles = await fetchCurrentCandidatePerformanceHistory();

        if (!isMounted) return;

        setPerformanceCycles(cycles);
        setPerformanceError("");
      } catch (loadError) {
        if (!isMounted) return;

        setPerformanceCycles([]);
        setPerformanceError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to load your performance history.",
        );
      } finally {
        if (isMounted) {
          setPerformanceLoading(false);
        }
      }
    };

    void loadPerformanceHistory();

    return () => {
      isMounted = false;
    };
  }, []);

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

  const handleResubmitFileChange = (event) => {
    setResubmitError("");
    setResubmitSuccess("");
    const file = event.target.files?.[0] || null;
    if (file) {
      if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
        setResubmitError("Only PDF files are allowed.");
        setSelectedResubmitFile(null);
        if (resubmitFileInputRef.current) resubmitFileInputRef.current.value = "";
        return;
      }
      if (file.size > 10 * 1024 * 1024) {
        setResubmitError("PDF file size must be no larger than 10 MB.");
        setSelectedResubmitFile(null);
        if (resubmitFileInputRef.current) resubmitFileInputRef.current.value = "";
        return;
      }
    }
    setSelectedResubmitFile(file);
  };

  const handleResubmitSignedOffer = async (event) => {
    event.preventDefault();

    if (!summary?.signedOffer?.canResubmit || !selectedResubmitFile || resubmitLoading) {
      return;
    }

    const authenticatedCandidateId = formatValue(candidateId);
    const summaryCandidateId = formatValue(summary.profile?.candidateId);

    if (
      authenticatedCandidateId &&
      summaryCandidateId &&
      authenticatedCandidateId.toLowerCase() !== summaryCandidateId.toLowerCase()
    ) {
      setResubmitError("Candidate reference could not be verified.");
      setResubmitSuccess("");
      return;
    }

    const uploadCandidateId = authenticatedCandidateId || summaryCandidateId;

    setResubmitLoading(true);
    setResubmitError("");
    setResubmitSuccess("");

    try {
      await resubmitCurrentCandidateSignedOffer({
        candidateId: uploadCandidateId,
        file: selectedResubmitFile,
      });

      setSelectedResubmitFile(null);
      if (resubmitFileInputRef.current) resubmitFileInputRef.current.value = "";
      setResubmitSuccess(
        "Corrected signed offer submitted successfully. HR will review it shortly.",
      );
      setLoading(true);
      setSummary(null);
      setRetryKey((currentKey) => currentKey + 1);
    } catch (submitError) {
      const safeMessage =
        submitError instanceof Error
          ? submitError.message
          : "Unable to complete the re-upload. Please try again.";

      setResubmitError(safeMessage);
      setResubmitSuccess("");

      if (safeMessage.includes("clean up") || safeMessage.includes("contact HR")) {
        setSelectedResubmitFile(null);
        if (resubmitFileInputRef.current) resubmitFileInputRef.current.value = "";
      }
    } finally {
      setResubmitLoading(false);
    }
  };

  const handleLeaveFormChange = (event) => {
    const { name, value } = event.target;

    setLeaveForm((currentForm) => {
      const nextForm = {
        ...currentForm,
        [name]: value,
      };
      if (name === "leaveType" && value !== "Other") {
        nextForm.otherLeaveTypeReason = "";
      }
      return nextForm;
    });
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

    if (leaveForm.leaveType === "Other" && !String(leaveForm.otherLeaveTypeReason || "").trim()) {
      setLeaveSubmissionError("Specify reason is required for other leave type.");
      return;
    }

    if (exceedsRemainingLeave && !selectedLeaveFile) {
      setLeaveSubmissionError("A supporting document PDF is required when requested leave exceeds the remaining balance.");
      return;
    }

    setLeaveSubmitting(true);
    setLeaveSubmissionError("");
    setLeaveSubmissionSuccess("");

    const authenticatedCandidateId = formatValue(candidateId);
    const summaryCandidateId = formatValue(summary.profile?.candidateId);
    const uploadCandidateId = authenticatedCandidateId || summaryCandidateId;

    if (!uploadCandidateId) {
      setLeaveSubmissionError("Candidate reference is invalid.");
      setLeaveSubmitting(false);
      return;
    }

    let uploadedPath = null;

    try {
      if (selectedLeaveFile) {
        uploadedPath = await uploadLeaveDocument(uploadCandidateId, selectedLeaveFile);
      }

      const submittedRequest = await submitCurrentCandidateLeaveRequest({
        ...leaveForm,
        supportingDocument: uploadedPath || "",
        remainingLeaveDays: summary?.leave?.remainingLeaveDays,
      });

      setLeaveForm(INITIAL_LEAVE_FORM);
      setSelectedLeaveFile(null);
      if (leaveFileInputRef.current) {
        leaveFileInputRef.current.value = "";
      }
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
      if (uploadedPath) {
        await deleteLeaveDocument(uploadedPath);
      }
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
          exitCase={exitCase}
          selectedFile={selectedFile}
          uploadLoading={uploadLoading}
          resubmitLoading={resubmitLoading}
          fileInputRef={fileInputRef}
          resubmitFileInputRef={resubmitFileInputRef}
          selectedResubmitFile={selectedResubmitFile}
          onFileChange={handleFileChange}
          onResubmitFileChange={handleResubmitFileChange}
          onSubmit={handleSubmitSignedOffer}
          onResubmit={handleResubmitSignedOffer}
          performanceCycles={performanceCycles}
          performanceLoading={performanceLoading}
          performanceError={performanceError}
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
            selectedFile={selectedLeaveFile}
            fileInputRef={leaveFileInputRef}
            onFileChange={handleLeaveFileChange}
            onRemoveFile={handleRemoveLeaveFile}
            onViewDocument={handleViewLeaveDocument}
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

      {resubmitError && (
        <section className="card card-danger" role="alert">
          <p className="auth-inline-error">{resubmitError}</p>
        </section>
      )}

      {resubmitSuccess && (
        <section className="card card-success" role="status" aria-live="polite">
          <p className="auth-success-message">{resubmitSuccess}</p>
        </section>
      )}
    </main>
  );
}

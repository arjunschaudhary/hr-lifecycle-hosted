import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { BadgeCheck } from "lucide-react";

import CandidateDetailModal from "../components/CandidateDetailModal";
import {
  downloadSignedOfferFile,
  fetchSignedOfferReviewQueue,
  reviewSignedOffer,
} from "../services/signedOfferReviewService";

const SAFE_LOAD_ERROR = "Unable to load signed-offer review records.";
const SAFE_DOWNLOAD_ERROR = "Unable to download the signed-offer PDF.";
const SAFE_ACTION_ERROR =
  "Unable to complete the signed-offer review. Refresh the page and try again.";

const formatValue = (value, fallback = "") => {
  if (value === null || value === undefined) {
    return fallback;
  }

  const normalizedValue = String(value).trim();
  return normalizedValue || fallback;
};

const formatStatus = (value, fallback = "Not available") =>
  formatValue(value, fallback)
    .toLowerCase()
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");

const formatDate = (value) => {
  if (!value) {
    return "Not available";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Not available";
  }

  return new Intl.DateTimeFormat("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
};

const formatFileSize = (value) => {
  const size = Number(value);

  if (!Number.isFinite(size) || size <= 0) {
    return "Not available";
  }

  if (size < 1024) {
    return `${size} bytes`;
  }

  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`;
  }

  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
};

const getOverallMatchStatus = (record) => {
  if (
    record.emailMatchStatus === "MISMATCH" ||
    record.phoneMatchStatus === "MISMATCH"
  ) {
    return "MISMATCH";
  }

  if (
    record.emailMatchStatus === "MATCH" &&
    record.phoneMatchStatus === "MATCH"
  ) {
    return "MATCH";
  }

  return "PENDING";
};

const getMatchBadgeClass = (status) => {
  if (status === "MATCH") {
    return "badge-success";
  }

  if (status === "MISMATCH") {
    return "badge-warning";
  }

  return "badge-primary";
};

const getStatusBadgeClass = (status) => {
  if (status === "VERIFIED" || status === "SIGNED_OFFER_VERIFIED") {
    return "badge-success";
  }

  if (status === "MISMATCH_REVIEW") {
    return "badge-warning";
  }

  return "badge-primary";
};

const hasLinkedFile = (record) =>
  Boolean(record.fileId && record.objectPath && record.originalFilename);

const canReviewRecord = (record) =>
  Boolean(
    record.verificationId &&
      record.fileId &&
      record.objectPath &&
      record.fileStatus === "SUBMITTED" &&
      record.lifecycleStatus === "SIGNED_OFFER_SUBMITTED" &&
      record.signedOfferStatus === "SIGNED_OFFER_SUBMITTED",
  );

const isCompletedReviewRecord = (record) =>
  record.lifecycleStatus === "SIGNED_OFFER_VERIFIED" ||
  record.lifecycleStatus === "MISMATCH_REVIEW" ||
  record.signedOfferStatus === "SIGNED_OFFER_VERIFIED" ||
  record.signedOfferStatus === "MISMATCH_REVIEW";

export default function SignedOfferVerification() {
  const [records, setRecords] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState("");
  const [actionVerificationId, setActionVerificationId] = useState(null);
  const [downloadingFileId, setDownloadingFileId] = useState(null);
  const [actionError, setActionError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const [reviewNotes, setReviewNotes] = useState({});
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);
  const [selectedReviewRecord, setSelectedReviewRecord] = useState(null);

  const loadReviewQueue = useCallback(async (isActive = () => true) => {
    if (!isActive()) {
      return false;
    }

    setIsLoading(true);
    setPageError("");

    try {
      const nextRecords = await fetchSignedOfferReviewQueue();

      if (!isActive()) {
        return false;
      }

      setRecords(nextRecords);
      return true;
    } catch {
      if (isActive()) {
        setPageError(SAFE_LOAD_ERROR);
      }

      return false;
    } finally {
      if (isActive()) {
        setIsLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    let isMounted = true;

    const loadInitialReviewQueue = async () => {
      await Promise.resolve();

      if (isMounted) {
        await loadReviewQueue(() => isMounted);
      }
    };

    void loadInitialReviewQueue();

    return () => {
      isMounted = false;
    };
  }, [loadReviewQueue]);

  useEffect(() => {
    if (!selectedReviewRecord) {
      return undefined;
    }

    const handleEscape = (event) => {
      if (event.key === "Escape" && !actionVerificationId) {
        setSelectedReviewRecord(null);
      }
    };

    document.addEventListener("keydown", handleEscape);

    return () => {
      document.removeEventListener("keydown", handleEscape);
    };
  }, [actionVerificationId, selectedReviewRecord]);

  useEffect(() => {
    if (!selectedReviewRecord) {
      return undefined;
    }

    const previousBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.body.style.overflow = previousBodyOverflow;
    };
  }, [selectedReviewRecord]);

  const handleOpenReview = (record) => {
    setActionError("");
    setSelectedReviewRecord(record);
  };

  const handleCloseReview = () => {
    if (actionVerificationId) {
      return;
    }

    setSelectedReviewRecord(null);
  };

  const handleRetry = () => {
    void loadReviewQueue();
  };

  const handleDownload = async (record) => {
    if (!hasLinkedFile(record)) {
      return;
    }

    setDownloadingFileId(record.fileId);
    setActionError("");
    setSuccessMessage("");

    let objectUrl = "";
    let downloadLink = null;

    try {
      const { blob, filename } = await downloadSignedOfferFile({
        objectPath: record.objectPath,
        originalFilename: record.originalFilename,
      });

      objectUrl = URL.createObjectURL(blob);
      downloadLink = document.createElement("a");
      downloadLink.href = objectUrl;
      downloadLink.download = filename;
      document.body.appendChild(downloadLink);
      downloadLink.click();
    } catch {
      setActionError(SAFE_DOWNLOAD_ERROR);
    } finally {
      if (objectUrl) {
        URL.revokeObjectURL(objectUrl);
      }

      if (downloadLink) {
        downloadLink.remove();
      }

      setDownloadingFileId(null);
    }
  };

  const handleReview = async (record, targetStatus) => {
    if (!canReviewRecord(record)) {
      return;
    }

    const notes = reviewNotes[record.verificationId] || "";

    if (targetStatus === "MISMATCH_REVIEW" && !notes.trim()) {
      setActionError("Mismatch review notes are required.");
      setSuccessMessage("");
      return;
    }

    setActionVerificationId(record.verificationId);
    setActionError("");
    setSuccessMessage("");

    try {
      await reviewSignedOffer({
        verificationId: record.verificationId,
        targetStatus,
        verificationNotes: notes,
      });

      setReviewNotes((currentNotes) => {
        const nextNotes = { ...currentNotes };
        delete nextNotes[record.verificationId];
        return nextNotes;
      });

      await loadReviewQueue();
      setSelectedReviewRecord(null);
      setSuccessMessage(
        targetStatus === "SIGNED_OFFER_VERIFIED"
          ? "Signed offer verified successfully."
          : "Signed offer moved to mismatch review.",
      );
    } catch {
      setActionError(SAFE_ACTION_ERROR);
      setSuccessMessage("");
    } finally {
      setActionVerificationId(null);
    }
  };

  const selectedReviewOverallMatchStatus = selectedReviewRecord
    ? getOverallMatchStatus(selectedReviewRecord)
    : "PENDING";
  const selectedReviewIsPending = selectedReviewRecord
    ? canReviewRecord(selectedReviewRecord)
    : false;
  const selectedReviewActionIsRunning = selectedReviewRecord
    ? actionVerificationId === selectedReviewRecord.verificationId
    : false;
  const selectedReviewDownloadIsRunning = selectedReviewRecord
    ? downloadingFileId === selectedReviewRecord.fileId
    : false;

  return (
    <div className="app-page">
      <Link to="/" className="back-link">
        &larr; Back to Dashboard
      </Link>

      <div className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <BadgeCheck size={28} />
        </div>
        <div>
          <h1 className="page-title-modern">Signed Offer Verification</h1>
          <p className="page-subtitle">
            Verify signed offers and review candidate information matches.
          </p>
        </div>
      </div>

      {isLoading && (
        <p role="status" aria-live="polite">
          Loading signed-offer review records...
        </p>
      )}

      {pageError && (
        <div className="info-banner" role="alert">
          <p>{pageError}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </div>
      )}

      {actionError && (
        <p className="auth-inline-error" role="alert">
          {actionError}
        </p>
      )}

      {successMessage && (
        <p className="auth-success-message" role="status" aria-live="polite">
          {successMessage}
        </p>
      )}

      {!isLoading && !pageError && records.length === 0 && (
        <div className="info-banner" role="status">
          No signed-offer review records found.
        </div>
      )}

      {!isLoading && !pageError && records.length > 0 && (
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>Candidate Name</th>
                <th>Applied Role</th>
                <th>MID</th>
                <th>Submitted Date</th>
                <th>Signed-off Status</th>
                <th>File Status</th>
                <th>Overall Match</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {records.map((record) => {
                const isPendingReview = canReviewRecord(record);
                const isCompleted = isCompletedReviewRecord(record);
                const overallMatchStatus = getOverallMatchStatus(record);
                const hasFile = hasLinkedFile(record);

                return (
                  <tr key={record.verificationId}>
                    <td>
                      <button
                        type="button"
                        className="candidate-link"
                        onClick={() => setSelectedCandidateId(record.candidateId)}
                      >
                        {formatValue(record.fullName, "Unnamed candidate")}
                      </button>
                    </td>
                    <td>{formatValue(record.appliedRole, "Not available")}</td>
                    <td>{formatValue(record.mid, "Not available")}</td>
                    <td>{formatDate(record.signedOfferSubmittedAt)}</td>
                    <td>
                      <span
                        className={`badge ${getStatusBadgeClass(
                          record.signedOfferStatus,
                        )}`}
                      >
                        {formatStatus(record.signedOfferStatus)}
                      </span>
                    </td>
                    <td>
                      <span
                        className={`badge ${getStatusBadgeClass(
                          record.fileStatus,
                        )}`}
                      >
                        {formatStatus(record.fileStatus, "File unavailable")}
                      </span>
                    </td>
                    <td>
                      <span
                        className={`badge ${getMatchBadgeClass(
                          overallMatchStatus,
                        )}`}
                      >
                        {formatStatus(overallMatchStatus)}
                      </span>
                    </td>
                    <td>
                      {isPendingReview && hasFile ? (
                        <button
                          type="button"
                          className="btn btn-primary"
                          onClick={() => handleOpenReview(record)}
                        >
                          Review Signed Offer
                        </button>
                      ) : isCompleted && hasFile ? (
                        <button
                          type="button"
                          className="btn btn-secondary"
                          onClick={() => handleOpenReview(record)}
                        >
                          View Review
                        </button>
                      ) : (
                        <span>File unavailable</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {selectedReviewRecord && (
        <div
          className="modal-overlay"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) {
              handleCloseReview();
            }
          }}
        >
          <section
            className="candidate-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="signed-offer-review-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <div className="candidate-modal-header">
              <div>
                <h2 id="signed-offer-review-title">Signed Offer Review</h2>
                <p>
                  {formatValue(
                    selectedReviewRecord.fullName,
                    "Unnamed candidate",
                  )}
                </p>
              </div>
              <button
                type="button"
                className="modal-close-btn"
                onClick={handleCloseReview}
                disabled={Boolean(actionVerificationId)}
                aria-label="Close signed offer review"
              >
                &times;
              </button>
            </div>

            <h3>Candidate Summary</h3>
            <div className="candidate-details-grid">
              <div className="candidate-detail-card">
                <span>Full Name</span>
                <strong>
                  {formatValue(selectedReviewRecord.fullName, "Not available")}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Email</span>
                <strong style={{ overflowWrap: "anywhere" }}>
                  {formatValue(selectedReviewRecord.email, "Not available")}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Phone</span>
                <strong>
                  {formatValue(selectedReviewRecord.phone, "Not available")}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Applied Role</span>
                <strong>
                  {formatValue(selectedReviewRecord.appliedRole, "Not available")}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>MID</span>
                <strong>
                  {formatValue(selectedReviewRecord.mid, "Not available")}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Lifecycle Status</span>
                <strong>
                  {formatStatus(selectedReviewRecord.lifecycleStatus)}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Signed-off Status</span>
                <strong>
                  <span
                    className={`badge ${getStatusBadgeClass(
                      selectedReviewRecord.signedOfferStatus,
                    )}`}
                  >
                    {formatStatus(selectedReviewRecord.signedOfferStatus)}
                  </span>
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Submitted Date</span>
                <strong>
                  {formatDate(selectedReviewRecord.signedOfferSubmittedAt)}
                </strong>
              </div>
            </div>

            <h3>File Summary</h3>
            <div className="candidate-details-grid">
              <div className="candidate-detail-card">
                <span>Original Filename</span>
                <strong style={{ overflowWrap: "anywhere" }}>
                  {formatValue(
                    selectedReviewRecord.originalFilename,
                    "File unavailable",
                  )}
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>File Size</span>
                <strong>{formatFileSize(selectedReviewRecord.fileSizeBytes)}</strong>
              </div>
              <div className="candidate-detail-card">
                <span>File Status</span>
                <strong>
                  <span
                    className={`badge ${getStatusBadgeClass(
                      selectedReviewRecord.fileStatus,
                    )}`}
                  >
                    {formatStatus(
                      selectedReviewRecord.fileStatus,
                      "File unavailable",
                    )}
                  </span>
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Uploaded Date</span>
                <strong>{formatDate(selectedReviewRecord.uploadedAt)}</strong>
              </div>
            </div>
            <div className="action-group">
              <button
                type="button"
                className="btn btn-secondary"
                disabled={selectedReviewDownloadIsRunning}
                onClick={() => handleDownload(selectedReviewRecord)}
              >
                {selectedReviewDownloadIsRunning
                  ? "Downloading..."
                  : "Download PDF"}
              </button>
            </div>

            <h3>Verification Summary</h3>
            <div className="candidate-details-grid">
              <div className="candidate-detail-card">
                <span>Email Match</span>
                <strong>
                  <span
                    className={`badge ${getMatchBadgeClass(
                      selectedReviewRecord.emailMatchStatus,
                    )}`}
                  >
                    {formatStatus(selectedReviewRecord.emailMatchStatus, "Pending")}
                  </span>
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Phone Match</span>
                <strong>
                  <span
                    className={`badge ${getMatchBadgeClass(
                      selectedReviewRecord.phoneMatchStatus,
                    )}`}
                  >
                    {formatStatus(selectedReviewRecord.phoneMatchStatus, "Pending")}
                  </span>
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Overall Match</span>
                <strong>
                  <span
                    className={`badge ${getMatchBadgeClass(
                      selectedReviewOverallMatchStatus,
                    )}`}
                  >
                    {formatStatus(selectedReviewOverallMatchStatus)}
                  </span>
                </strong>
              </div>
              <div className="candidate-detail-card">
                <span>Verified Date</span>
                <strong>{formatDate(selectedReviewRecord.verifiedAt)}</strong>
              </div>
              <div className="candidate-detail-card">
                <span>Existing Verification Notes</span>
                <strong style={{ overflowWrap: "anywhere" }}>
                  {formatValue(
                    selectedReviewRecord.verificationNotes,
                    "Not available",
                  )}
                </strong>
              </div>
            </div>

            {selectedReviewIsPending ? (
              <div className="form-group">
                <label htmlFor={`verification-notes-${selectedReviewRecord.verificationId}`}>
                  Verification notes
                </label>
                <textarea
                  id={`verification-notes-${selectedReviewRecord.verificationId}`}
                  value={reviewNotes[selectedReviewRecord.verificationId] || ""}
                  onChange={(event) =>
                    setReviewNotes((currentNotes) => ({
                      ...currentNotes,
                      [selectedReviewRecord.verificationId]: event.target.value,
                    }))
                  }
                  maxLength={2000}
                  rows={4}
                  disabled={selectedReviewActionIsRunning}
                  aria-describedby="signed-offer-review-notes-help"
                />
                <small id="signed-offer-review-notes-help">
                  Notes are required when marking a signed offer for mismatch review.
                </small>
                <div className="action-group">
                  <button
                    type="button"
                    className="btn btn-success"
                    disabled={selectedReviewActionIsRunning}
                    onClick={() =>
                      handleReview(
                        selectedReviewRecord,
                        "SIGNED_OFFER_VERIFIED",
                      )
                    }
                  >
                    {selectedReviewActionIsRunning
                      ? "Saving..."
                      : "Verify Signed Offer"}
                  </button>
                  <button
                    type="button"
                    className="btn btn-warning"
                    disabled={selectedReviewActionIsRunning}
                    onClick={() =>
                      handleReview(selectedReviewRecord, "MISMATCH_REVIEW")
                    }
                  >
                    {selectedReviewActionIsRunning
                      ? "Saving..."
                      : "Mark Mismatch Review"}
                  </button>
                </div>
              </div>
            ) : (
              <p role="status">This review is complete and read-only.</p>
            )}
          </section>
        </div>
      )}

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </div>
  );
}

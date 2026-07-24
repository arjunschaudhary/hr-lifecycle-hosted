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
                <th>Email</th>
                <th>Phone</th>
                <th>Role</th>
                <th>MID</th>
                <th>Submitted At</th>
                <th>Email Match</th>
                <th>Phone Match</th>
                <th>Overall Match</th>
                <th>Verified At</th>
                <th>Verification Notes</th>
                <th>Original Filename</th>
                <th>File Size</th>
                <th>File Status</th>
                <th>Uploaded Date</th>
                <th>Status</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
  {records.map((record) => {
    const isPendingReview = canReviewRecord(record);
    const isActionRunning =
      actionVerificationId === record.verificationId;
    const isDownloadRunning = downloadingFileId === record.fileId;
    const overallMatchStatus = getOverallMatchStatus(record);

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
                    <td>{formatValue(record.email, "Not available")}</td>
                    <td>{formatValue(record.phone, "Not available")}</td>
                    <td>{formatValue(record.appliedRole, "Not available")}</td>
                    <td>{formatValue(record.mid, "Not available")}</td>
                    <td>{formatDate(record.signedOfferSubmittedAt)}</td>
                <td>
                  <span
                    className={`badge ${getMatchBadgeClass(
                      record.emailMatchStatus,
                    )}`}
                  >
                    {formatStatus(record.emailMatchStatus, "Pending")}
                  </span>
                </td>
                <td>
                  <span
                    className={`badge ${getMatchBadgeClass(
                      record.phoneMatchStatus,
                    )}`}
                  >
                    {formatStatus(record.phoneMatchStatus, "Pending")}
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
                    <td>{formatDate(record.verifiedAt)}</td>
                    <td>{formatValue(record.verificationNotes, "Not available")}</td>
                    <td>{formatValue(record.originalFilename, "File unavailable")}</td>
                    <td>{formatFileSize(record.fileSizeBytes)}</td>
                    <td>{formatStatus(record.fileStatus, "File unavailable")}</td>
                    <td>{formatDate(record.uploadedAt)}</td>
                    <td>
                      <span className="badge badge-primary">
                        {formatStatus(record.signedOfferStatus)}
                      </span>
                    </td>
                    <td>
                      {hasLinkedFile(record) && (
                        <button
                          type="button"
                          className="btn btn-secondary"
                          disabled={isDownloadRunning}
                          onClick={() => handleDownload(record)}
                        >
                          {isDownloadRunning ? "Downloading..." : "Download PDF"}
                        </button>
                      )}

                      {isPendingReview ? (
                        <div className="form-group">
                          <label htmlFor={`verification-notes-${record.verificationId}`}>
                            Verification notes
                          </label>
                          <textarea
                            id={`verification-notes-${record.verificationId}`}
                            value={reviewNotes[record.verificationId] || ""}
                            onChange={(event) =>
                              setReviewNotes((currentNotes) => ({
                                ...currentNotes,
                                [record.verificationId]: event.target.value,
                              }))
                            }
                            maxLength={2000}
                            rows={3}
                            disabled={isActionRunning}
                          />
                          <button
                            type="button"
                            className="btn btn-success"
                            disabled={isActionRunning}
                            onClick={() =>
                              handleReview(record, "SIGNED_OFFER_VERIFIED")
                            }
                          >
                            {isActionRunning ? "Saving..." : "Verify Signed Offer"}
                          </button>{" "}
                          <button
                            type="button"
                            className="btn btn-primary"
                            disabled={isActionRunning}
                            onClick={() => handleReview(record, "MISMATCH_REVIEW")}
                          >
                            {isActionRunning ? "Saving..." : "Mark Mismatch Review"}
                          </button>
                        </div>
                      ) : (
                        <span>No action</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </div>
  );
}

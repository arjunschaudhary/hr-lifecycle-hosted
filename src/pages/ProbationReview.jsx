import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { ClipboardCheck } from "lucide-react";
import { dummyCandidates, dummyProbationAttempts } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import {
  extendCandidateProbation,
  generateCandidateMidAfterProbation,
  updateCandidateLifecycleStatus,
  approveCandidateForProbation,
} from "../services/lifecycleActionService";
import { fetchProbationReviewCandidates } from "../services/probationReviewService";
import { sendCandidateWelcomeEmail } from "../services/welcomeMailService";
import { markCandidateInProbation } from "../services/inProbationActionService";
import ApproveProbationModal from "../components/ApproveProbationModal";
const reviewStatuses = [
  "HR_REVIEW_PENDING",
  "HR_APPROVED_FOR_PROBATION",
  "WELCOME_MAIL_SENT",
  "IN_PROBATION",
  "PROBATION_REVIEW",
  "PROBATION_PASSED",
  "PROBATION_REJECTED",
  "PROBATION_EXTENDED",
  "UNDER_REVIEW",
  "RECONSIDERATION",
];

function requiresWelcomeMailManualCheck(message) {
  return message.includes("Check the sender Sent folder before retrying.");
}

function buildFallbackProbationRecords() {
  return dummyProbationAttempts
    .filter((attempt) => reviewStatuses.includes(attempt.status))
    .map((attempt) => {
      const candidate = dummyCandidates.find(
        (candidate) => candidate.id === attempt.candidateId
      );

      return {
        id: attempt.id,
        candidateId: attempt.candidateId,
        fullName: candidate?.fullName,
        email: candidate?.email,
        phone: candidate?.phone,
        appliedRole: candidate?.roleAppliedFor,
        roleCode: null,
        department: candidate?.department,
        source: candidate?.createdSource,
        attemptNo: attempt.attemptNo,
        probationStartDate: attempt.probationStartDate,
        probationEndDate: attempt.probationEndDate,
        probationExtensionCount: attempt.probationExtensionCount || 0,
        probationStatus: attempt.status,
        probationReviewNotes: attempt.hrRemarks,
        hrDecision: reviewStatuses.includes(attempt.status) ? attempt.status : null,
        mid: null,
      };
    });
}

function mapSupabaseProbationRecord(row) {
  return {
    id: row.candidate_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    roleCode: row.role_code,
    department: "",
    source: row.source,
    attemptNo: "",
    probationStartDate: row.probation_start_date,
    probationEndDate: row.probation_end_date,
    probationExtensionCount: row.probation_extension_count || 0,
    probationStatus: row.probation_status,
    probationReviewNotes: row.probation_review_notes,
    hrDecision: row.hr_decision,
    mid: row.mid,
  };
}

function getStatusClass(status) {

  switch (status) {

    case "HR_REVIEW_PENDING":
      return "badge-warning";

    case "PROBATION_PASSED":
      return "badge-success";

    case "PROBATION_REJECTED":
      return "badge-danger";

    default:
      return "badge-primary";
  }
}

export default function ProbationReview() {
  const fallbackRecords = useMemo(() => buildFallbackProbationRecords(), []);
  const [probationRecords, setProbationRecords] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [actionCandidateId, setActionCandidateId] = useState(null);
  const [actionMessage, setActionMessage] = useState("");
  const [sendingWelcomeMailCandidateIds, setSendingWelcomeMailCandidateIds] =
    useState(() => new Set());
  const [welcomeMailError, setWelcomeMailError] = useState("");
  const [welcomeMailSuccessMessage, setWelcomeMailSuccessMessage] =
    useState("");
  const [markingInProbationCandidateIds, setMarkingInProbationCandidateIds] =
    useState(() => new Set());
  const [inProbationLifecycleMessage, setInProbationLifecycleMessage] =
    useState("");
  const [performanceAssignmentMessage, setPerformanceAssignmentMessage] =
    useState("");
  const [
    welcomeMailRetryBlockedCandidateIds,
    setWelcomeMailRetryBlockedCandidateIds,
  ] = useState(() => new Set());
  const welcomeMailInFlightCandidateIdsRef = useRef(new Set());
  const markInProbationInFlightCandidateIdsRef = useRef(new Set());
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);
  const [showApproveModal, setShowApproveModal] = useState(false);
  const [approveCandidate, setApproveCandidate] = useState(null);
  async function refreshProbationRecords() {
    try {
      const records = await fetchProbationReviewCandidates();

      if (records?.length) {
        setProbationRecords(records.map(mapSupabaseProbationRecord));
        setErrorMessage("");
      } else {
        setProbationRecords(fallbackRecords);
        setErrorMessage("No Supabase probation review data found. Showing dummy data.");
      }
    } catch (error) {
      console.error("Unable to load probation review candidates:", error);
      setProbationRecords(fallbackRecords);
      setErrorMessage("Unable to load Supabase probation review data. Showing dummy data.");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    let isMounted = true;

    async function loadInitialProbationRecords() {
      try {
        const records = await fetchProbationReviewCandidates();

        if (!isMounted) return;

        if (records?.length) {
          setProbationRecords(records.map(mapSupabaseProbationRecord));
          setErrorMessage("");
        } else {
          setProbationRecords(fallbackRecords);
          setErrorMessage("No Supabase probation review data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load probation review candidates:", error);
        setProbationRecords(fallbackRecords);
        setErrorMessage("Unable to load Supabase probation review data. Showing dummy data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadInitialProbationRecords();

    return () => {
      isMounted = false;
    };
  }, [fallbackRecords]);

  
    function openApproveModal(record) {
      setApproveCandidate(record);
      setShowApproveModal(true);
    }

    function closeApproveModal() {
      setShowApproveModal(false);
      setApproveCandidate(null);
    }

    async function confirmApprove({
      candidateId,
      joiningDate,
      durationMonths,
    }) {
      setActionCandidateId(candidateId);
      setActionMessage("");
      setErrorMessage("");

      try {
        await approveCandidateForProbation({
          candidateId,
          joiningDate,
          durationMonths,
          performedBy: "HR",
        });

        closeApproveModal();

        setActionMessage("Candidate approved for probation.");

        await refreshProbationRecords();
      } catch (error) {
        console.error("Unable to approve probation:", error);

        setErrorMessage(
          error.message || "Unable to approve probation."
        );
      } finally {
        setActionCandidateId(null);
      }
    }

  async function handleLifecycleAction({
    candidateId,
    fromStatus,
    toStatus,
    activityType,
    remarks,
    successMessage,
  }) {
    setActionCandidateId(candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await updateCandidateLifecycleStatus({
        candidateId,
        fromStatus,
        toStatus,
        activityType,
        remarks,
        performedBy: "HR",
      });

      setActionMessage(successMessage);
      await refreshProbationRecords();
    } catch (error) {
      console.error("Unable to update candidate lifecycle status:", error);
      setErrorMessage("Unable to update candidate lifecycle status.");
    } finally {
      setActionCandidateId(null);
    }
  }

  async function handleSendWelcomeEmail(candidateId) {
    if (
      welcomeMailInFlightCandidateIdsRef.current.has(candidateId) ||
      welcomeMailRetryBlockedCandidateIds.has(candidateId)
    ) {
      return;
    }

    welcomeMailInFlightCandidateIdsRef.current.add(candidateId);
    setSendingWelcomeMailCandidateIds((currentCandidateIds) => {
      const nextCandidateIds = new Set(currentCandidateIds);
      nextCandidateIds.add(candidateId);
      return nextCandidateIds;
    });
    setWelcomeMailError("");
    setWelcomeMailSuccessMessage("");

    try {
      const result = await sendCandidateWelcomeEmail(candidateId);

      setWelcomeMailRetryBlockedCandidateIds((currentCandidateIds) => {
        const nextCandidateIds = new Set(currentCandidateIds);
        nextCandidateIds.delete(candidateId);
        return nextCandidateIds;
      });
      setWelcomeMailSuccessMessage(
        result.alreadyCompleted
          ? "Welcome email was already sent."
          : "Welcome email sent successfully."
      );
      await refreshProbationRecords();
    } catch (error) {
      const safeMessage =
        error instanceof Error
          ? error.message
          : "Unable to send the welcome email. Please try again.";

      setWelcomeMailError(safeMessage);

      if (requiresWelcomeMailManualCheck(safeMessage)) {
        setWelcomeMailRetryBlockedCandidateIds((currentCandidateIds) => {
          const nextCandidateIds = new Set(currentCandidateIds);
          nextCandidateIds.add(candidateId);
          return nextCandidateIds;
        });
      } else {
        setWelcomeMailRetryBlockedCandidateIds((currentCandidateIds) => {
          const nextCandidateIds = new Set(currentCandidateIds);
          nextCandidateIds.delete(candidateId);
          return nextCandidateIds;
        });
      }
    } finally {
      welcomeMailInFlightCandidateIdsRef.current.delete(candidateId);
      setSendingWelcomeMailCandidateIds((currentCandidateIds) => {
        const nextCandidateIds = new Set(currentCandidateIds);
        nextCandidateIds.delete(candidateId);
        return nextCandidateIds;
      });
    }
  }

  async function handleMarkInProbation(candidateId) {
    if (markInProbationInFlightCandidateIdsRef.current.has(candidateId)) {
      return;
    }

    markInProbationInFlightCandidateIdsRef.current.add(candidateId);
    setMarkingInProbationCandidateIds((currentCandidateIds) => {
      const nextCandidateIds = new Set(currentCandidateIds);
      nextCandidateIds.add(candidateId);
      return nextCandidateIds;
    });
    setActionMessage("");
    setErrorMessage("");
    setInProbationLifecycleMessage("");
    setPerformanceAssignmentMessage("");

    try {
      const result = await markCandidateInProbation(candidateId);

      setInProbationLifecycleMessage(
        result.transitionCompleted
          ? "Candidate marked as in probation."
          : "Candidate is already marked as in probation."
      );

      switch (result.performanceOutcome) {
        case "PERFORMANCE_ASSIGNED":
          setPerformanceAssignmentMessage(
            "Performance cycle assigned and eligible days refreshed."
          );
          break;
        case "PERFORMANCE_PENDING_POD":
          setPerformanceAssignmentMessage(
            "Performance assignment is pending a valid pod membership."
          );
          break;
        case "PERFORMANCE_PENDING_CYCLE":
          setPerformanceAssignmentMessage(
            "Performance assignment is pending an OPEN performance cycle."
          );
          break;
        default:
          setPerformanceAssignmentMessage(
            "Performance assignment could not be completed and was recorded for review."
          );
      }

      await refreshProbationRecords();
    } catch (error) {
      setErrorMessage(
        error instanceof Error
          ? error.message
          : "Unable to mark the candidate in probation. Please try again."
      );
    } finally {
      markInProbationInFlightCandidateIdsRef.current.delete(candidateId);
      setMarkingInProbationCandidateIds((currentCandidateIds) => {
        const nextCandidateIds = new Set(currentCandidateIds);
        nextCandidateIds.delete(candidateId);
        return nextCandidateIds;
      });
    }
  }

  async function handleGenerateMid(record) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      const { mid } = await generateCandidateMidAfterProbation({
        candidateId: record.candidateId,
        fullName: record.fullName,
        roleCode: record.roleCode,
        existingMid: record.mid,
        performedBy: "HR",
      });

      setActionMessage(`MID generated: ${mid}`);
      await refreshProbationRecords();
    } catch (error) {
      console.error("Unable to generate MID:", error);
      setErrorMessage(error.message || "Unable to generate MID.");
    } finally {
      setActionCandidateId(null);
    }
  }

  async function handleExtendProbation(record) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await extendCandidateProbation({
        candidateId: record.candidateId,
        performedBy: "HR",
      });

      setActionMessage("Candidate probation extended.");
      await refreshProbationRecords();
    } catch (error) {
      console.error("Unable to extend probation:", error);
      setErrorMessage(error.message || "Unable to extend probation.");
    } finally {
      setActionCandidateId(null);
    }
  }

  return (
    <div className="app-page">
      
      <Link
  to="/"
  className="back-link"
>
  ← Back to Dashboard
</Link>
      <div className="page-header-modern">

  <div className="page-icon">
    <ClipboardCheck size={28} />
  </div>

  <div>
    <h1 className="page-title-modern">
      Probation Review
    </h1>

    <p className="page-subtitle">
      Review candidates and manage probation lifecycle transitions.
    </p>
  </div>

</div>

      {isLoading && <p>Loading probation review candidates...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {actionMessage && <p>{actionMessage}</p>}

      {welcomeMailError && <p role="alert">{welcomeMailError}</p>}

      {welcomeMailSuccessMessage && (
        <p role="status">{welcomeMailSuccessMessage}</p>
      )}

      {inProbationLifecycleMessage && (
        <p role="status">{inProbationLifecycleMessage}</p>
      )}

      {performanceAssignmentMessage && (
        <p role="status">{performanceAssignmentMessage}</p>
      )}

      <div className="table-container">

      <table>
        <thead>
          <tr>
            <th>Candidate Name</th>
            <th>Email</th>
            <th>Phone</th>
            <th>Role</th>
            <th>Department</th>
            <th>Attempt No</th>
            <th>Source</th>
            <th>Start Date</th>
            <th>End Date</th>
            <th>Status</th>
            <th>HR Decision</th>
            <th>MID</th>
            <th>HR Remarks</th>
            <th>Action</th>
          </tr>
        </thead>

        <tbody>
          {probationRecords.map((record) => (
            <tr key={record.id}>
              <td>
                <button
  type="button"
  className="candidate-link"
  onClick={() => setSelectedCandidateId(record.candidateId)}
>
                  {record.fullName}
                </button>
              </td>
              <td>{record.email}</td>
              <td>{record.phone}</td>
              <td>{record.appliedRole}</td>
              <td>{record.department}</td>
              <td>{record.attemptNo}</td>
              <td>{record.source}</td>
              <td>{record.probationStartDate}</td>
              <td>{record.probationEndDate}</td>
              <td>

  <span
    className={`badge ${getStatusClass(record.probationStatus)}`}
  >
    {record.probationStatus
      .replaceAll("_"," ")}
  </span>

</td>
              <td>{record.hrDecision}</td>
              <td>{record.mid}</td>
              <td>{record.probationReviewNotes}</td>
              <td>
                {record.probationStatus === "HR_REVIEW_PENDING" && (
                  <button
                    type="button"
                     className="btn btn-success"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() => openApproveModal(record)}
                  >
                    {actionCandidateId === record.candidateId
                      ? "Approving..."
                      : "Approve for Probation"}
                  </button>
                )}

                {record.probationStatus === "HR_APPROVED_FOR_PROBATION" && (
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={
                      sendingWelcomeMailCandidateIds.has(record.candidateId) ||
                      welcomeMailRetryBlockedCandidateIds.has(
                        record.candidateId
                      )
                    }
                    onClick={() =>
                      handleSendWelcomeEmail(record.candidateId)
                    }
                  >
                    {sendingWelcomeMailCandidateIds.has(record.candidateId)
                      ? "Sending Email..."
                      : "Send Welcome Email"}
                  </button>
                )}

                {record.probationStatus === "WELCOME_MAIL_SENT" && (
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={markingInProbationCandidateIds.has(
                      record.candidateId
                    )}
                    onClick={() =>
                      handleMarkInProbation(record.candidateId)
                    }
                  >
                    {markingInProbationCandidateIds.has(record.candidateId)
                      ? "Assigning..."
                      : "Mark In Probation"}
                  </button>
                )}

                {record.probationStatus === "IN_PROBATION" && (
                  <button
                    type="button"
                    className="btn btn-warning"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() =>
                      handleLifecycleAction({
                        candidateId: record.candidateId,
                        fromStatus: "IN_PROBATION",
                        toStatus: "PROBATION_REVIEW",
                        activityType: "PROBATION_REVIEW",
                        remarks: "Candidate marked ready for probation review by HR",
                        successMessage: "Candidate marked ready for probation review.",
                      })
                    }
                  >
                    {actionCandidateId === record.candidateId
                      ? "Marking..."
                      : "Mark Ready for Review"}
                  </button>
                )}

                {record.probationStatus === "PROBATION_REVIEW" && (
                  <>
                    <button
                      type="button"
                      className="btn btn-success"
                      disabled={actionCandidateId === record.candidateId}
                      onClick={() =>
                        handleLifecycleAction({
                          candidateId: record.candidateId,
                          fromStatus: "PROBATION_REVIEW",
                          toStatus: "PROBATION_PASSED",
                          activityType: "PROBATION_PASSED",
                          remarks: "Candidate passed probation review by HR",
                          successMessage: "Candidate marked as probation passed.",
                        })
                      }
                    >
                      {actionCandidateId === record.candidateId
                        ? "Saving..."
                        : "Pass Probation"}
                    </button>

                    <button
                      type="button"
                      className="btn btn-danger"
                      disabled={actionCandidateId === record.candidateId}
                      onClick={() =>
                        handleLifecycleAction({
                          candidateId: record.candidateId,
                          fromStatus: "PROBATION_REVIEW",
                          toStatus: "PROBATION_REJECTED",
                          activityType: "PROBATION_REJECTED",
                          remarks: "Candidate rejected after probation review by HR",
                          successMessage: "Candidate marked as probation rejected.",
                        })
                      }
                    >
                      {actionCandidateId === record.candidateId
                        ? "Saving..."
                        : "Reject Probation"}
                    </button>

                    {record.probationExtensionCount === 0 && (
                      <button
                        type="button"
                         className="btn btn-warning"
                        disabled={actionCandidateId === record.candidateId}
                        onClick={() => handleExtendProbation(record)}
                      >
                        {actionCandidateId === record.candidateId
                          ? "Saving..."
                          : "Extend Probation"}
                      </button>
                    )}
                  </>
                )}

                {record.probationStatus === "PROBATION_EXTENDED" && (
                  <button
                    type="button"
                    className="btn btn-warning"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() =>
                      handleLifecycleAction({
                        candidateId: record.candidateId,
                        fromStatus: "PROBATION_EXTENDED",
                        toStatus: "PROBATION_REVIEW",
                        activityType: "PROBATION_READY_FOR_REVIEW",
                        remarks: "Extended probation marked ready for review by HR",
                        successMessage: "Extended probation marked ready for review.",
                      })
                    }
                  >
                    {actionCandidateId === record.candidateId
                      ? "Marking..."
                      : "Mark Ready for Review Again"}
                  </button>
                )}

                {record.probationStatus === "PROBATION_PASSED" && (
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() => handleGenerateMid(record)}
                  >
                    {actionCandidateId === record.candidateId
                      ? "Generating..."
                      : "Generate MID"}
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      </div>
      <br />
      
      <ApproveProbationModal
        isOpen={showApproveModal}
        candidate={approveCandidate}
        onClose={closeApproveModal}
        onConfirm={confirmApprove}
      />

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </div>
  );
}

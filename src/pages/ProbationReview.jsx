import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { dummyCandidates, dummyProbationAttempts } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { fetchProbationReviewCandidates } from "../services/probationReviewService";

const reviewStatuses = [
  "HR_REVIEW_PENDING",
  "HR_APPROVED_FOR_PROBATION",
  "PROBATION_INITIATED",
  "WELCOME_MAIL_SENT",
  "IN_PROBATION",
  "PROBATION_REVIEW",
  "PROBATION_PASSED",
  "PROBATION_REJECTED",
  "PROBATION_EXTENDED",
  "UNDER_REVIEW",
  "RECONSIDERATION",
];

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
        department: candidate?.department,
        source: candidate?.createdSource,
        attemptNo: attempt.attemptNo,
        probationStartDate: attempt.probationStartDate,
        probationEndDate: attempt.probationEndDate,
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
    department: "",
    source: row.source,
    attemptNo: "",
    probationStartDate: row.probation_start_date,
    probationEndDate: row.probation_end_date,
    probationStatus: row.probation_status,
    probationReviewNotes: row.probation_review_notes,
    hrDecision: row.hr_decision,
    mid: row.mid,
  };
}

export default function ProbationReview() {
  const fallbackRecords = useMemo(() => buildFallbackProbationRecords(), []);
  const [probationRecords, setProbationRecords] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  useEffect(() => {
    let isMounted = true;

    async function loadProbationRecords() {
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

    loadProbationRecords();

    return () => {
      isMounted = false;
    };
  }, [fallbackRecords]);

  return (
    <div style={{ padding: "20px" }}>
      <h1>Probation Review</h1>

      {isLoading && <p>Loading probation review candidates...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <table border="1" cellPadding="10">
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
          </tr>
        </thead>

        <tbody>
          {probationRecords.map((record) => (
            <tr key={record.id}>
              <td>
                <button
                  type="button"
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
              <td>{record.probationStatus}</td>
              <td>{record.hrDecision}</td>
              <td>{record.mid}</td>
              <td>{record.probationReviewNotes}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <br />

      <Link to="/">
        <button>Back to Dashboard</button>
      </Link>

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </div>
  );
}

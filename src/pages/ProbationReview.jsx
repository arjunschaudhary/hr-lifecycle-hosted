import { Link } from "react-router-dom";

import { dummyCandidates, dummyProbationAttempts } from "../data";

export default function ProbationReview() {
  const reviewStatuses = [
    "IN_PROBATION",
    "UNDER_REVIEW",
    "PROBATION_EXTENDED",
    "RECONSIDERATION",
  ];

  const probationRecords = dummyProbationAttempts.filter((attempt) =>
    reviewStatuses.includes(attempt.status)
  );

  return (
    <div style={{ padding: "20px" }}>
      <h1>Probation Review</h1>

      <table border="1" cellPadding="10">
        <thead>
          <tr>
            <th>Candidate Name</th>
            <th>Role</th>
            <th>Department</th>
            <th>Attempt No</th>
            <th>Start Date</th>
            <th>End Date</th>
            <th>Status</th>
            <th>HR Remarks</th>
          </tr>
        </thead>

        <tbody>
          {probationRecords.map((attempt) => {
            const candidate = dummyCandidates.find(
              (candidate) => candidate.id === attempt.candidateId
            );

            return (
              <tr key={attempt.id}>
                <td>{candidate?.fullName}</td>
                <td>{candidate?.roleAppliedFor}</td>
                <td>{candidate?.department}</td>
                <td>{attempt.attemptNo}</td>
                <td>{attempt.probationStartDate}</td>
                <td>{attempt.probationEndDate}</td>
                <td>{attempt.status}</td>
                <td>{attempt.hrRemarks}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <br />

      <Link to="/">
        <button>Back to Dashboard</button>
      </Link>
    </div>
  );
}
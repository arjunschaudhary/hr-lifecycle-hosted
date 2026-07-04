import { useEffect, useState } from "react";
import CandidateDetailModal from "./CandidateDetailModal";
import leaveDashboardService from "../services/leaveDashboardService";

export default function UpcomingLeaveTable() {
  const [leaves, setLeaves] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  useEffect(() => {
    let isMounted = true;

    async function loadLeaves() {
      try {
        const data =
          await leaveDashboardService.getUpcomingLeaves();

        if (isMounted) {
          setLeaves(data);
        }
      } catch (error) {
        console.error(error);
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    }

    loadLeaves();

    return () => {
      isMounted = false;
    };
  }, []);

  if (loading) {
    return <p>Loading upcoming leaves...</p>;
  }

  return (
    <>
      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>Candidate</th>
              <th>MID</th>
              <th>Role</th>
              <th>Leave Type</th>
              <th>Start Date</th>
              <th>End Date</th>
              <th>Leave Days</th>
            </tr>
          </thead>

          <tbody>
            {leaves.length === 0 ? (
              <tr>
                <td
                  colSpan={7}
                  style={{
                    textAlign: "center",
                    padding: "20px",
                  }}
                >
                  No upcoming approved leaves.
                </td>
              </tr>
            ) : (
              leaves.map((leave) => (
                <tr key={leave.leave_request_id}>
                  <td>
                    <button
                      type="button"
                      className="candidate-link"
                      onClick={() =>
                        setSelectedCandidateId(
                          leave.candidate_id
                        )
                      }
                    >
                      {leave.full_name}
                    </button>
                  </td>

                  <td>
                    <strong>{leave.mid || "-"}</strong>
                  </td>

                  <td>{leave.applied_role}</td>

                  <td>{leave.leave_type}</td>

                  <td>{leave.start_date}</td>

                  <td>{leave.end_date}</td>

                  <td>{leave.requested_leave_days}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </>
  );
}

import { useEffect, useState } from "react";
import CandidateDetailModal from "./CandidateDetailModal";
import {
  getPendingLeaveRequests,
  approveLeave,
  rejectLeave,
} from "../services/leaveApprovalService";

export default function PendingLeaveTable() {
  const [leaveRequests, setLeaveRequests] = useState([]);
  const [loading, setLoading] = useState(true);

  const [actionId, setActionId] = useState(null);

  const [selectedCandidateId, setSelectedCandidateId] =
    useState(null);

  async function loadRequests() {
    try {
      setLoading(true);

      const data = await getPendingLeaveRequests();

      setLeaveRequests(data);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    let isMounted = true;

    async function loadInitialRequests() {
      try {
        const data = await getPendingLeaveRequests();

        if (isMounted) {
          setLeaveRequests(data);
        }
      } catch (err) {
        console.error(err);
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    }

    loadInitialRequests();

    return () => {
      isMounted = false;
    };
  }, []);

  async function handleApprove(id) {
    try {
      setActionId(id);

      await approveLeave(id);

      await loadRequests();
    } catch (err) {
      alert(err.message);
    } finally {
      setActionId(null);
    }
  }

  async function handleReject(id) {
    try {
      setActionId(id);

      await rejectLeave(id);

      await loadRequests();
    } catch (err) {
      alert(err.message);
    } finally {
      setActionId(null);
    }
  }

  if (loading) {
    return <p>Loading pending leave requests...</p>;
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
              <th>From</th>
              <th>To</th>
              <th>Days</th>
              <th>Reason</th>
              <th>Status</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody>
            {leaveRequests.length === 0 ? (
              <tr>
                <td
                  colSpan={10}
                  style={{
                    textAlign: "center",
                    padding: "20px",
                  }}
                >
                  No pending leave requests.
                </td>
              </tr>
            ) : (
              leaveRequests.map((leave) => (
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

                  <td>{leave.mid || "-"}</td>

                  <td>{leave.applied_role}</td>

                  <td>{leave.leave_type}</td>

                  <td>{leave.start_date}</td>

                  <td>{leave.end_date}</td>

                  <td>{leave.requested_leave_days}</td>

                  <td>{leave.reason}</td>

                  <td>
                    <span className="badge badge-warning">
                      Pending
                    </span>
                  </td>

                  <td>
                    <div
                      style={{
                        display: "flex",
                        gap: "8px",
                      }}
                    >
                      <button
                        className="btn btn-success"
                        disabled={
                          actionId === leave.leave_request_id
                        }
                        onClick={() =>
                          handleApprove(
                            leave.leave_request_id
                          )
                        }
                      >
                        {actionId === leave.leave_request_id
                          ? "..."
                          : "Approve"}
                      </button>

                      <button
                        className="btn btn-danger"
                        disabled={
                          actionId === leave.leave_request_id
                        }
                        onClick={() =>
                          handleReject(
                            leave.leave_request_id
                          )
                        }
                      >
                        {actionId === leave.leave_request_id
                          ? "..."
                          : "Reject"}
                      </button>
                    </div>
                  </td>
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

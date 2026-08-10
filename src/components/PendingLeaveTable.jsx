import { useEffect, useState } from "react";
import CandidateDetailModal from "./CandidateDetailModal";
import {
  getPendingLeaveRequests,
  approveLeave,
  rejectLeave,
  getLeaveDocumentSignedUrl,
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

  const handleViewDocument = async (docRef) => {
    if (!docRef) return;
    if (docRef.startsWith("http://") || docRef.startsWith("https://")) {
      window.open(docRef, "_blank", "noopener,noreferrer");
      return;
    }
    try {
      const url = await getLeaveDocumentSignedUrl(docRef);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      alert("Unable to view document: " + err.message);
    }
  };

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
              <th>Document</th>
              <th>Status</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody>
            {leaveRequests.length === 0 ? (
              <tr>
                <td
                  colSpan={11}
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

                  <td>
                    {leave.leave_type === "Other" && leave.other_leave_type_reason
                      ? `Other (${leave.other_leave_type_reason})`
                      : leave.leave_type}
                  </td>

                  <td>{leave.start_date}</td>

                  <td>{leave.end_date}</td>

                  <td>{leave.requested_leave_days}</td>

                  <td>{leave.reason}</td>

                  <td>
                    {leave.supporting_document ? (
                      <button
                        type="button"
                        className="candidate-link"
                        onClick={() => handleViewDocument(leave.supporting_document)}
                      >
                        View Document
                      </button>
                    ) : (
                      "-"
                    )}
                  </td>

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

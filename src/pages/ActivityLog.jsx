import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { History } from "lucide-react";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { fetchActivityLogs } from "../services/activityLogService";

function mapSupabaseActivityLog(row) {
  return {
    id: row.activity_log_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    activityType: row.activity_type,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    remarks: row.remarks,
    activityStatus: row.activity_status,
    errorMessage: row.error_message,
    performedBy: row.performed_by,
    performedAt: row.performed_at,
  };
}

export default function ActivityLog() {
  const [activityLogs, setActivityLogs] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  useEffect(() => {
    let isMounted = true;

    async function loadActivityLogs() {
      try {
        const records = await fetchActivityLogs();

        if (!isMounted) return;

        setActivityLogs((records ?? []).map(mapSupabaseActivityLog));
        setErrorMessage("");
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load activity logs:", error);
        setActivityLogs([]);
        setErrorMessage("Unable to load activity log data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadActivityLogs();

    return () => {
      isMounted = false;
    };
  }, []);

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

<History size={28}/>

</div>



<div>

<h1 className="page-title-modern">
Activity Log
</h1>


<p className="page-subtitle">
Track candidate lifecycle actions and HR workflow history.
</p>


</div>


</div>


      {isLoading && <p>Loading activity logs...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {!isLoading && !errorMessage && activityLogs.length === 0 && (
        <div className="info-banner" role="status">No activity logs found.</div>
      )}

      <div className="table-container">

      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Candidate</th>
            <th>Email</th>
            <th>Action</th>
            <th>Old Status</th>
            <th>New Status</th>
            <th>Remarks</th>
            <th>Activity Status</th>
            <th>Error Message</th>
            <th>Performed By</th>
          </tr>
        </thead>

        <tbody>
          {activityLogs.map((log) => (
            <tr key={log.id}>
              <td>{log.performedAt}</td>
              <td>
                <button
                  type="button"
                  className="candidate-link"
                  onClick={() => setSelectedCandidateId(log.candidateId)}
                >
                  {log.fullName}
                </button>
              </td>
              <td>{log.email}</td>
              <td>{log.activityType}</td>
              <td>

{log.fromStatus ? (

<span className="badge badge-primary">

{log.fromStatus.replaceAll("_"," ")}

</span>

) : "-"}

</td>



<td>

{log.toStatus ? (

<span className="badge badge-success">

{log.toStatus.replaceAll("_"," ")}

</span>

) : "-"}

</td>
              <td>{log.remarks}</td>
              <td>

<span
className={
`badge ${
log.activityStatus === "SUCCESS"
?
"badge-success"
:
"badge-warning"
}`
}
>

{log.activityStatus}

</span>

</td>
              <td>{log.errorMessage || "-"}</td>
              <td>{log.performedBy}</td>
            </tr>
          ))}
        </tbody>
      </table>
      </div>
      <br />

      

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </div>
  );
}

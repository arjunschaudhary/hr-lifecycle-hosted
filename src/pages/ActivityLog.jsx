import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { dummyCandidates, dummyActivityLogs } from "../data";
import { fetchActivityLogs } from "../services/activityLogService";

function buildFallbackActivityLogs() {
  return dummyActivityLogs.map((log) => {
    const candidate = dummyCandidates.find(
      (candidate) => candidate.id === log.candidateId
    );

    return {
      id: log.id,
      fullName: candidate?.fullName,
      email: candidate?.email,
      activityType: log.actionType,
      fromStatus: log.oldStatus,
      toStatus: log.newStatus,
      remarks: log.remarks,
      activityStatus: "SUCCESS",
      errorMessage: "",
      performedBy: log.performedBy,
      performedAt: log.createdAt,
    };
  });
}

function mapSupabaseActivityLog(row) {
  return {
    id: row.activity_log_id,
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
  const fallbackLogs = useMemo(() => buildFallbackActivityLogs(), []);
  const [activityLogs, setActivityLogs] = useState(fallbackLogs);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadActivityLogs() {
      try {
        const records = await fetchActivityLogs();

        if (!isMounted) return;

        if (records?.length) {
          setActivityLogs(records.map(mapSupabaseActivityLog));
          setErrorMessage("");
        } else {
          setActivityLogs(fallbackLogs);
          setErrorMessage("No Supabase activity log data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load activity logs:", error);
        setActivityLogs(fallbackLogs);
        setErrorMessage("Unable to load Supabase activity log data. Showing dummy data.");
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
  }, [fallbackLogs]);

  return (
    <div style={{ padding: "20px" }}>
      <h1>Activity Log</h1>

      {isLoading && <p>Loading activity logs...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <table border="1" cellPadding="10">
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
              <td>{log.fullName}</td>
              <td>{log.email}</td>
              <td>{log.activityType}</td>
              <td>{log.fromStatus || "-"}</td>
              <td>{log.toStatus || "-"}</td>
              <td>{log.remarks}</td>
              <td>{log.activityStatus}</td>
              <td>{log.errorMessage || "-"}</td>
              <td>{log.performedBy}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <br />

      <Link to="/">
        <button>Back to Dashboard</button>
      </Link>
    </div>
  );
}

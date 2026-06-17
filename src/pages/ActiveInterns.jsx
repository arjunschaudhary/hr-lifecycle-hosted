import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { dummyActiveInterns } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { fetchActiveInterns } from "../services/activeInternsService";

function buildFallbackActiveInternRecords() {
  return dummyActiveInterns.map((intern) => ({
    id: intern.id,
    candidateId: intern.candidateId,
    fullName: intern.fullName,
    email: "",
    phone: "",
    appliedRole: intern.role,
    department: intern.department,
    team: intern.team,
    project: intern.project,
    lifecycleStatus: intern.status,
    mid: intern.mid,
    offerStatus: "",
    sentAt: intern.activeStartDate,
    signedOfferStatus: "",
  }));
}

function mapSupabaseActiveInternRecord(row) {
  return {
    id: row.candidate_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    department: row.department,
    team: "",
    project: "",
    lifecycleStatus: row.lifecycle_status,
    mid: row.mid,
    offerStatus: row.offer_status,
    sentAt: row.sent_at ?? row.offer_letter_sent_at,
    signedOfferStatus: row.signed_offer_status,
  };
}

export default function ActiveInterns() {
  const fallbackRecords = useMemo(() => buildFallbackActiveInternRecords(), []);
  const [activeInterns, setActiveInterns] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  useEffect(() => {
    let isMounted = true;

    async function loadActiveInterns() {
      try {
        const records = await fetchActiveInterns();

        if (!isMounted) return;

        if (records?.length) {
          setActiveInterns(records.map(mapSupabaseActiveInternRecord));
          setErrorMessage("");
        } else {
          setActiveInterns(fallbackRecords);
          setErrorMessage("No Supabase active interns data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load active interns:", error);
        setActiveInterns(fallbackRecords);
        setErrorMessage("Unable to load Supabase active interns data. Showing dummy data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadActiveInterns();

    return () => {
      isMounted = false;
    };
  }, [fallbackRecords]);

  return (
    <div style={{ padding: "20px" }}>
      <h1>Active Interns</h1>

      {isLoading && <p>Loading active interns...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <table border="1" cellPadding="10">
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Phone</th>
            <th>MID</th>
            <th>Role</th>
            <th>Department</th>
            <th>Team</th>
            <th>Project</th>
            <th>Lifecycle Status</th>
            <th>Offer Status</th>
            <th>Sent At</th>
            <th>Signed Offer Status</th>
          </tr>
        </thead>

        <tbody>
          {activeInterns.map((intern) => (
            <tr key={intern.id}>
              <td>
                <button
                  type="button"
                  onClick={() => setSelectedCandidateId(intern.candidateId)}
                >
                  {intern.fullName}
                </button>
              </td>
              <td>{intern.email}</td>
              <td>{intern.phone}</td>
              <td>{intern.mid}</td>
              <td>{intern.appliedRole}</td>
              <td>{intern.department}</td>
              <td>{intern.team}</td>
              <td>{intern.project}</td>
              <td>{intern.lifecycleStatus}</td>
              <td>{intern.offerStatus}</td>
              <td>{intern.sentAt}</td>
              <td>{intern.signedOfferStatus}</td>
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

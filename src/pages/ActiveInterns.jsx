import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { BriefcaseBusiness } from "lucide-react";
import { dummyActiveInterns } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { markSignedOfferSubmitted } from "../services/lifecycleActionService";
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
function getStatusClass(status) {

  switch (status) {

    case "ACTIVE":
      return "badge-success";

    case "SIGNED_OFFER_SUBMITTED":
      return "badge-primary";

    default:
      return "badge-warning";
  }
}

export default function ActiveInterns() {
  const fallbackRecords = useMemo(() => buildFallbackActiveInternRecords(), []);
  const [activeInterns, setActiveInterns] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [actionCandidateId, setActionCandidateId] = useState(null);
  const [actionMessage, setActionMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  async function refreshActiveInterns() {
    try {
      const records = await fetchActiveInterns();

      if (records?.length) {
        setActiveInterns(records.map(mapSupabaseActiveInternRecord));
        setErrorMessage("");
      } else {
        setActiveInterns(fallbackRecords);
        setErrorMessage("No Supabase active interns data found. Showing dummy data.");
      }
    } catch (error) {
      console.error("Unable to load active interns:", error);
      setActiveInterns(fallbackRecords);
      setErrorMessage("Unable to load Supabase active interns data. Showing dummy data.");
    } finally {
      setIsLoading(false);
    }
  }

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

  async function handleMarkSignedOfferSubmitted(intern) {
    setActionCandidateId(intern.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await markSignedOfferSubmitted({
        candidateId: intern.candidateId,
        performedBy: "HR",
      });

      setActionMessage("Signed offer marked as submitted.");
      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to mark signed offer as submitted:", error);
      setErrorMessage(error.message || "Unable to mark signed offer as submitted.");
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
    <BriefcaseBusiness size={28} />
  </div>

  <div>
    <h1 className="page-title-modern">
      Active Interns
    </h1>

    <p className="page-subtitle">
      Manage active interns and track signed offer submissions.
    </p>
  </div>

</div>

      {isLoading && <p>Loading active interns...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {actionMessage && <p>{actionMessage}</p>}

      <div className="table-container">

      <table>
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
            <th>Action</th>
          </tr>
        </thead>

        <tbody>
          {activeInterns.map((intern) => (
            <tr key={intern.id}>
              <td>
                <button
                  type="button"
                  className="candidate-link"
                  onClick={() => setSelectedCandidateId(intern.candidateId)}
                >
                  {intern.fullName}
                </button>
              </td>
              <td>{intern.email}</td>
              <td>{intern.phone}</td>
              <td>
  <strong>{intern.mid}</strong>
</td>
              <td>{intern.appliedRole}</td>
              <td>{intern.department}</td>
              <td>{intern.team}</td>
              <td>{intern.project}</td>
              <td>
  <span
    className={`badge ${getStatusClass(intern.lifecycleStatus)}`}
  >
    {intern.lifecycleStatus.replaceAll("_", " ")}
  </span>
</td>
              <td>{intern.offerStatus}</td>
              <td>{intern.sentAt}</td>
              <td>{intern.signedOfferStatus}</td>
              <td>
                {intern.lifecycleStatus === "ACTIVE" && (
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={actionCandidateId === intern.candidateId}
                    onClick={() => handleMarkSignedOfferSubmitted(intern)}
                  >
                    {actionCandidateId === intern.candidateId
                      ? "Marking..."
                      : "Mark Signed Offer Submitted"}
                  </button>
                )}
              </td>
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

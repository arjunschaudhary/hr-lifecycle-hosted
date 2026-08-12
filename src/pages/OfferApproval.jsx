import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { FileSignature } from "lucide-react";
import CandidateDetailModal from "../components/CandidateDetailModal";
import {
  generateOfferLetterRecordAfterMid,
  markCandidateActiveAfterOfferSent,
  markOfferLetterSent,
} from "../services/lifecycleActionService";
import { fetchOfferLetterProcessCandidates } from "../services/offerLetterProcessService";

function mapSupabaseOfferRecord(row) {
  return {
    id: row.candidate_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    mid: row.mid,
    appliedRole: row.applied_role,
    department: row.department,
    lifecycleStatus: row.lifecycle_status,
    offerStatus: row.offer_status,
    offerLetterNumber: row.offer_letter_number,
    generatedAt: row.generated_at,
    sentAt: row.sent_at,
    startDate: "",
    endDate: "",
  };
}
function getStatusClass(status) {

  switch (status) {

    case "MID_GENERATED":
      return "badge-warning";

    case "OFFER_LETTER_SENT":
      return "badge-success";

    default:
      return "badge-primary";
  }
}

export default function OfferApproval() {
  const [offerRecords, setOfferRecords] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [actionCandidateId, setActionCandidateId] = useState(null);
  const [actionMessage, setActionMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  async function refreshOfferRecords() {
    try {
      const records = await fetchOfferLetterProcessCandidates();

      setOfferRecords((records ?? []).map(mapSupabaseOfferRecord));
      setErrorMessage("");
    } catch (error) {
      console.error("Unable to load offer letter process candidates:", error);
      setOfferRecords([]);
      setErrorMessage("Unable to load offer letter process data.");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    let isMounted = true;

    async function loadOfferRecords() {
      try {
        const records = await fetchOfferLetterProcessCandidates();

        if (!isMounted) return;

        setOfferRecords((records ?? []).map(mapSupabaseOfferRecord));
        setErrorMessage("");
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load offer letter process candidates:", error);
        setOfferRecords([]);
        setErrorMessage("Unable to load offer letter process data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadOfferRecords();

    return () => {
      isMounted = false;
    };
  }, []);

  async function handleGenerateOfferLetterRecord(record) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      const { offerLetterNumber } = await generateOfferLetterRecordAfterMid({
        candidateId: record.candidateId,
        existingMid: record.mid,
        performedBy: "HR",
      });

      setActionMessage(`Offer letter record generated: ${offerLetterNumber}`);
      await refreshOfferRecords();
    } catch (error) {
      console.error("Unable to generate offer letter record:", error);
      setErrorMessage(error.message || "Unable to generate offer letter record.");
    } finally {
      setActionCandidateId(null);
    }
  }

  async function handleMarkOfferLetterSent(record) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await markOfferLetterSent({
        candidateId: record.candidateId,
        performedBy: "HR",
      });

      setActionMessage("Offer letter marked as sent.");
      await refreshOfferRecords();
    } catch (error) {
      console.error("Unable to mark offer letter as sent:", error);
      setErrorMessage(error.message || "Unable to mark offer letter as sent.");
    } finally {
      setActionCandidateId(null);
    }
  }

  async function handleMarkActiveIntern(record) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await markCandidateActiveAfterOfferSent({
        candidateId: record.candidateId,
        performedBy: "HR",
      });

      setActionMessage("Candidate marked as active intern.");
      await refreshOfferRecords();
    } catch (error) {
      console.error("Unable to mark candidate as active intern:", error);
      setErrorMessage(error.message || "Unable to mark candidate as active intern.");
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
    <FileSignature size={28} />
  </div>

  <div>
    <h1 className="page-title-modern">
      Offer Letter Process
    </h1>

    <p className="page-subtitle">
      Generate offer records, send offer letters, and activate interns.
    </p>
  </div>

</div>

      {isLoading && <p>Loading offer letter process candidates...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {actionMessage && <p>{actionMessage}</p>}

      {!isLoading && !errorMessage && offerRecords.length === 0 && (
        <div className="info-banner" role="status">No offer letter process records found.</div>
      )}

      <div className="table-container">

      <table>
        <thead>
          <tr>
            <th>Candidate Name</th>
            <th>Email</th>
            <th>Phone</th>
            <th>MID</th>
            <th>Role</th>
            <th>Department</th>
            <th>Lifecycle Status</th>
            <th>Offer Status</th>
            <th>Offer Letter Number</th>
            <th>Generated At</th>
            <th>Sent At</th>
            <th>Start Date</th>
            <th>End Date</th>
            <th>Action</th>
          </tr>
        </thead>

        <tbody>
          {offerRecords.map((record) => (
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
              <td>{record.mid}</td>
              <td>{record.appliedRole}</td>
              <td>{record.department}</td>
              <td>
  <span
    className={`badge ${getStatusClass(record.lifecycleStatus)}`}
  >
    {record.lifecycleStatus?.replaceAll("_", " ")}
  </span>
</td>
              <td>
  <span className="badge badge-primary">
    {record.offerStatus?.replaceAll("_", " ")}
  </span>
</td>
              <td>{record.offerLetterNumber}</td>
              <td>{record.generatedAt}</td>
              <td>{record.sentAt}</td>
              <td>{record.startDate}</td>
              <td>{record.endDate}</td>
              <td>
                {record.lifecycleStatus === "MID_GENERATED" && (
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() => handleGenerateOfferLetterRecord(record)}
                  >
                    {actionCandidateId === record.candidateId
                      ? "Generating..."
                      : "Generate Offer Letter Record"}
                  </button>
                )}

                {record.lifecycleStatus === "OFFER_LETTER_GENERATED" && (
                  <button
                    type="button"
                    className="btn btn-success"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() => handleMarkOfferLetterSent(record)}
                  >
                    {actionCandidateId === record.candidateId
                      ? "Marking..."
                      : "Mark Offer Letter Sent"}
                  </button>
                )}

                {record.lifecycleStatus === "OFFER_LETTER_SENT" && (
                  <button
                    type="button"
                    className="btn btn-success"
                    disabled={actionCandidateId === record.candidateId}
                    onClick={() => handleMarkActiveIntern(record)}
                  >
                    {actionCandidateId === record.candidateId
                      ? "Marking..."
                      : "Mark Active Intern"}
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

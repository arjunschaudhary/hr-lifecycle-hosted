import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { dummyCandidates, dummyOffers } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { fetchOfferLetterProcessCandidates } from "../services/offerLetterProcessService";

function buildFallbackOfferRecords() {
  return dummyOffers.map((offer) => {
    const candidate = dummyCandidates.find(
      (candidate) => candidate.id === offer.candidateId
    );

    return {
      id: offer.id,
      candidateId: offer.candidateId,
      fullName: candidate?.fullName,
      email: candidate?.email,
      phone: candidate?.phone,
      mid: offer.mid,
      appliedRole: candidate?.roleAppliedFor ?? offer.role,
      department: candidate?.department,
      lifecycleStatus: candidate?.currentStatus,
      offerStatus: offer.offerStatus,
      offerLetterNumber: offer.id,
      generatedAt: offer.offerLetterGeneratedAt,
      sentAt: offer.offerLetterSentAt,
      startDate: offer.startDate,
      endDate: offer.endDate,
    };
  });
}

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

export default function OfferApproval() {
  const fallbackRecords = useMemo(() => buildFallbackOfferRecords(), []);
  const [offerRecords, setOfferRecords] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  useEffect(() => {
    let isMounted = true;

    async function loadOfferRecords() {
      try {
        const records = await fetchOfferLetterProcessCandidates();

        if (!isMounted) return;

        if (records?.length) {
          setOfferRecords(records.map(mapSupabaseOfferRecord));
          setErrorMessage("");
        } else {
          setOfferRecords(fallbackRecords);
          setErrorMessage("No Supabase offer letter process data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load offer letter process candidates:", error);
        setOfferRecords(fallbackRecords);
        setErrorMessage("Unable to load Supabase offer letter process data. Showing dummy data.");
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
  }, [fallbackRecords]);

  return (
    <div style={{ padding: "20px" }}>
      <h1>Offer Letter Process</h1>

      {isLoading && <p>Loading offer letter process candidates...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <table border="1" cellPadding="10">
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
          </tr>
        </thead>

        <tbody>
          {offerRecords.map((record) => (
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
              <td>{record.mid}</td>
              <td>{record.appliedRole}</td>
              <td>{record.department}</td>
              <td>{record.lifecycleStatus}</td>
              <td>{record.offerStatus}</td>
              <td>{record.offerLetterNumber}</td>
              <td>{record.generatedAt}</td>
              <td>{record.sentAt}</td>
              <td>{record.startDate}</td>
              <td>{record.endDate}</td>
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

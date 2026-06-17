import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { dummyCandidates, dummySignedOffers } from "../data";
import { fetchSignedOfferVerifications } from "../services/signedOfferVerificationService";

function getOverallMatchStatus(emailMatchStatus, phoneMatchStatus) {
  if (emailMatchStatus === "MISMATCH" || phoneMatchStatus === "MISMATCH") {
    return "MISMATCH";
  }

  if (emailMatchStatus || phoneMatchStatus) {
    return "MATCH";
  }

  return "PENDING";
}

function buildFallbackSignedOfferRecords() {
  return dummySignedOffers.map((offer) => {
    const candidate = dummyCandidates.find(
      (candidate) => candidate.id === offer.candidateId
    );

    return {
      id: offer.id,
      fullName: candidate?.fullName,
      email: candidate?.email,
      phone: candidate?.phone,
      appliedRole: candidate?.roleAppliedFor,
      mid: offer.mid,
      signedOfferStatus: offer.status,
      signedOfferSubmittedAt: offer.submittedAt,
      emailMatchStatus: offer.emailMatchStatus,
      phoneMatchStatus: offer.phoneMatchStatus,
      overallMatchStatus: getOverallMatchStatus(
        offer.emailMatchStatus,
        offer.phoneMatchStatus
      ),
      verifiedAt: offer.verifiedAt,
      verificationNotes: offer.rejectionReason,
    };
  });
}

function mapSupabaseSignedOfferRecord(row) {
  return {
    id: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    mid: row.mid,
    signedOfferStatus: row.signed_offer_status,
    signedOfferSubmittedAt: row.signed_offer_submitted_at,
    emailMatchStatus: row.email_match_status,
    phoneMatchStatus: row.phone_match_status,
    overallMatchStatus: row.overall_match_status,
    verifiedAt: row.verified_at,
    verificationNotes: row.verification_notes,
  };
}

export default function SignedOfferVerification() {
  const fallbackRecords = useMemo(() => buildFallbackSignedOfferRecords(), []);
  const [signedOfferRecords, setSignedOfferRecords] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadSignedOfferRecords() {
      try {
        const records = await fetchSignedOfferVerifications();

        if (!isMounted) return;

        if (records?.length) {
          setSignedOfferRecords(records.map(mapSupabaseSignedOfferRecord));
          setErrorMessage("");
        } else {
          setSignedOfferRecords(fallbackRecords);
          setErrorMessage("No Supabase signed offer verification data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load signed offer verifications:", error);
        setSignedOfferRecords(fallbackRecords);
        setErrorMessage("Unable to load Supabase signed offer verification data. Showing dummy data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadSignedOfferRecords();

    return () => {
      isMounted = false;
    };
  }, [fallbackRecords]);

  return (
    <div style={{ padding: "20px" }}>
      <h1>Signed Offer Verification</h1>

      {isLoading && <p>Loading signed offer verifications...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <table border="1" cellPadding="10">
        <thead>
          <tr>
            <th>Candidate Name</th>
            <th>Email</th>
            <th>Phone</th>
            <th>Role</th>
            <th>MID</th>
            <th>Submitted At</th>
            <th>Email Match</th>
            <th>Phone Match</th>
            <th>Overall Match</th>
            <th>Verified At</th>
            <th>Verification Notes</th>
            <th>Status</th>
          </tr>
        </thead>

        <tbody>
          {signedOfferRecords.map((record) => (
            <tr key={record.id}>
              <td>{record.fullName}</td>
              <td>{record.email}</td>
              <td>{record.phone}</td>
              <td>{record.appliedRole}</td>
              <td>{record.mid}</td>
              <td>{record.signedOfferSubmittedAt}</td>
              <td>{record.emailMatchStatus}</td>
              <td>{record.phoneMatchStatus}</td>
              <td>{record.overallMatchStatus}</td>
              <td>{record.verifiedAt}</td>
              <td>{record.verificationNotes}</td>
              <td>{record.signedOfferStatus}</td>
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

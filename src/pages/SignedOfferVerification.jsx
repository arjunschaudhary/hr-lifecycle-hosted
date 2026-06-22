import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { BadgeCheck } from "lucide-react";
import { dummyCandidates, dummySignedOffers } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { decideSignedOfferVerification } from "../services/lifecycleActionService";
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
      candidateId: offer.candidateId,
      fullName: candidate?.fullName,
      email: candidate?.email,
      phone: candidate?.phone,
      appliedRole: candidate?.roleAppliedFor,
      lifecycleStatus: offer.status,
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
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    lifecycleStatus: row.lifecycle_status,
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
  const [actionCandidateId, setActionCandidateId] = useState(null);
  const [actionMessage, setActionMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);

  const refreshSignedOfferRecords = useCallback(async () => {
    const records = await fetchSignedOfferVerifications();

    if (records?.length) {
      setSignedOfferRecords(records.map(mapSupabaseSignedOfferRecord));
      setErrorMessage("");
    } else {
      setSignedOfferRecords(fallbackRecords);
      setErrorMessage("No Supabase signed offer verification data found. Showing dummy data.");
    }
  }, [fallbackRecords]);

  async function handleSignedOfferDecision({
    record,
    toStatus,
    activityType,
    remarks,
    verificationNotes,
    markAsMatched,
    successMessage,
  }) {
    setActionCandidateId(record.candidateId);
    setActionMessage("");

    try {
      await decideSignedOfferVerification({
        candidateId: record.candidateId,
        toStatus,
        activityType,
        remarks,
        verificationNotes,
        markAsMatched,
        performedBy: "HR",
      });

      await refreshSignedOfferRecords();
      setActionMessage(successMessage);
    } catch (error) {
      console.error("Unable to update signed offer verification:", error);
      setActionMessage(error.message || "Unable to update signed offer verification.");
    } finally {
      setActionCandidateId(null);
    }
  }

  useEffect(() => {
    let isMounted = true;

    async function loadSignedOfferRecords() {
      try {
        if (!isMounted) return;

        await refreshSignedOfferRecords();
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
  }, [fallbackRecords, refreshSignedOfferRecords]);

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

<BadgeCheck size={28}/>

</div>



<div>

<h1 className="page-title-modern">
Signed Offer Verification
</h1>


<p className="page-subtitle">
Verify signed offers and review candidate information matches.
</p>


</div>


</div>


      {isLoading && <p>Loading signed offer verifications...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {actionMessage && <p>{actionMessage}</p>}

      <div className="table-container">

      <table>
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
            <th>Action</th>
          </tr>
        </thead>

        <tbody>
          {signedOfferRecords.map((record) => (
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
              <td>{record.appliedRole}</td>
              <td>{record.mid}</td>
              <td>{record.signedOfferSubmittedAt}</td>
              <td>
<span className="badge badge-success">
{record.emailMatchStatus}
</span>
</td>


<td>
<span className="badge badge-success">
{record.phoneMatchStatus}
</span>
</td>


<td>

<span
className={
`badge ${
record.overallMatchStatus === "MISMATCH"
?
"badge-warning"
:
"badge-success"
}`
}
>

{record.overallMatchStatus}

</span>

</td>
              <td>{record.verifiedAt}</td>
              <td>{record.verificationNotes}</td>
              <td>

<span className="badge badge-primary">

{record.signedOfferStatus?.replaceAll("_"," ")}

</span>

</td>
              <td>
                {record.lifecycleStatus === "SIGNED_OFFER_SUBMITTED" ? (
                  <>
                    <button
                      type="button"
                      className="btn btn-success"
                      disabled={actionCandidateId === record.candidateId}
                      onClick={() =>
                        handleSignedOfferDecision({
                          record,
                          toStatus: "SIGNED_OFFER_VERIFIED",
                          activityType: "SIGNED_OFFER_VERIFIED",
                          remarks: "Signed offer verified by HR",
                          verificationNotes: "Signed offer verified by HR",
                          markAsMatched: true,
                          successMessage: "Signed offer verified.",
                        })
                      }
                    >
                      {actionCandidateId === record.candidateId
                        ? "Saving..."
                        : "Verify Signed Offer"}
                    </button>{" "}
                    <button
                      type="button"
                      className="btn btn-primary"
                      disabled={actionCandidateId === record.candidateId}
                      onClick={() =>
                        handleSignedOfferDecision({
                          record,
                          toStatus: "MISMATCH_REVIEW",
                          activityType: "MISMATCH_REVIEW",
                          remarks: "Signed offer marked for mismatch review by HR",
                          verificationNotes: "Signed offer requires mismatch review",
                          markAsMatched: false,
                          successMessage: "Signed offer marked for mismatch review.",
                        })
                      }
                    >
                      {actionCandidateId === record.candidateId
                        ? "Saving..."
                        : "Mark Mismatch Review"}
                    </button>
                  </>
                ) : (
                  "No action"
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

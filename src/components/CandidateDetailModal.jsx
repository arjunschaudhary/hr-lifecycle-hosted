import { useEffect, useState } from "react";

import { fetchCandidateDetail } from "../services/candidateDetailService";

const detailFields = [
  ["Full Name", "full_name"],
  ["Email", "email"],
  ["Phone", "phone"],
  ["Alternate Phone", "alternate_phone"],
  ["Address", "address"],
  ["City", "city"],
  ["State", "state"],
  ["Applied Role", "applied_role"],
  ["Department", "department"],
  ["Qualification", "qualification"],
  ["College Name", "college_name"],
  ["Source", "source"],
  ["Availability Status", "availability_status"],
  ["Lifecycle Status", "lifecycle_status"],
  ["Internship / Probation Start Date", "probation_start_date"],
  ["Probation End Date", "probation_end_date"],
  ["Internship Duration Months", "internship_duration_months"],
  ["Original Internship End Date", "original_end_date"],
  ["Current Internship End Date", "current_end_date"],
  ["Probation Extension Count", "probation_extension_count"],
  ["Probation Review Notes", "probation_review_notes"],
  ["HR Decision", "hr_decision"],
  ["MID", "mid"],
  ["Allocated Leave", "allocated_leave_days"],
  ["Approved Leave", "approved_leave_days"],
  ["Remaining Leave", "remaining_leave_days"],
  ["Extra Leave", "extra_leave_days"],
  ["Offer Status", "offer_status"],
  ["Offer Letter Number", "offer_letter_number"],
  ["Generated At", "generated_at"],
  ["Sent At", "sent_at"],
  ["Signed Offer Status", "signed_offer_status"],
  ["Signed Offer Submitted At", "signed_offer_submitted_at"],
  ["Email Match Status", "email_match_status"],
  ["Phone Match Status", "phone_match_status"],
  ["Verification Notes", "verification_notes"],
];

export default function CandidateDetailModal({ candidateId, onClose }) {
  const [candidateDetail, setCandidateDetail] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    if (!candidateId) return;

    let isMounted = true;

    async function loadCandidateDetail() {
      setIsLoading(true);
      setErrorMessage("");

      try {
        const detail = await fetchCandidateDetail(candidateId);

        if (!isMounted) return;

        if (detail) {
          setCandidateDetail(detail);
        } else {
          setCandidateDetail(null);
          setErrorMessage("Candidate detail was not found.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load candidate detail:", error);
        setCandidateDetail(null);
        setErrorMessage("Unable to load candidate detail.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadCandidateDetail();

    return () => {
      isMounted = false;
    };
  }, [candidateId]);

  if (!candidateId) return null;
   
  return (
  <div className="modal-overlay">

    <div className="candidate-modal">

      <div className="candidate-modal-header">

        <div className="candidate-profile">

          <div className="candidate-avatar">
            👤
          </div>

          <div>
            <h2>
              {candidateDetail?.full_name || "Candidate Details"}
            </h2>

            <p>
              Candidate Lifecycle Information
            </p>
          </div>

        </div>


        <button
          className="modal-close-btn"
          onClick={onClose}
        >
          ×
        </button>


      </div>



      {isLoading && (
        <div className="info-banner">
          Loading candidate details...
        </div>
      )}

      {errorMessage && (
        <div className="info-banner">
          {errorMessage}
        </div>
      )}


      {candidateDetail && (

        <div className="candidate-details-grid">

          {detailFields.map(([label,key]) => (

            <div
              className="candidate-detail-card"
              key={key}
            >

              <span>
                {label}
              </span>


              <strong>
                {candidateDetail[key] === null ||
                candidateDetail[key] === undefined ||
                candidateDetail[key] === ""
                  ? "-"
                  : candidateDetail[key]}
              </strong>


            </div>

          ))}


        </div>

      )}


    </div>

  </div>
);
    
}

import { useEffect, useState } from "react";

import { fetchCandidateDetail } from "../services/candidateDetailService";

function formatWithUnit(value, unit) {
  if (value === null || value === undefined || value === "") {
    return "-";
  }

  return `${value} ${unit}`;
}

function formatDetailValue(value, formatter) {
  if (formatter) {
    return formatter(value);
  }

  if (value === null || value === undefined || value === "") {
    return "-";
  }

  return value;
}

const detailFields = [
  ["Full Name", "full_name"],
  ["Email", "email"],
  ["Phone", "phone"],
  ["Alternate Phone", "alternate_phone"],
  ["Address", "address"],
  ["City", "city"],
  ["State", "state"],
  ["Applied Role", "applied_role"],
  ["Role Code", "role_code"],
  ["Department", "department"],
  ["Qualification", "qualification"],
  ["College Name", "college_name"],
  ["Source", "source"],
  ["Availability Status", "availability_status"],
  ["Lifecycle Status", "lifecycle_status"],
  ["Internship / Probation Start Date", "probation_start_date"],
  ["Probation End Date", "probation_end_date"],
  [
    "Original Internship Duration",
    "internship_duration_months",
    (value) => formatWithUnit(value, "months"),
  ],
  [
    "Extension Added",
    "extension_months",
    (value) => formatWithUnit(value, "months"),
  ],
  [
    "Extension Duration Days",
    "extension_duration_days",
    (value) => formatWithUnit(value, "days"),
  ],
  [
    "Total Duration Days",
    "total_duration_days",
    (value) => formatWithUnit(value, "days"),
  ],
  [
    "Total Internship Duration",
    "total_internship_duration_months",
    (value) => formatWithUnit(value, "months"),
  ],
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

  useEffect(() => {
    if (!candidateId) {
      return undefined;
    }

    const handleKeyDown = (event) => {
      if (event.key === "Escape") {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [candidateId, onClose]);

  const handleOverlayClick = (event) => {
    if (event.target === event.currentTarget) {
      onClose();
    }
  };

  if (!candidateId) return null;
   
  return (
  <div className="modal-overlay" onClick={handleOverlayClick}>

    <div
      className="candidate-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="candidate-detail-modal-title"
    >

      <div className="candidate-modal-header">

        <div className="candidate-profile">

          <div className="candidate-avatar">
            👤
          </div>

          <div>
            <h2 id="candidate-detail-modal-title">
              {candidateDetail?.full_name || "Candidate Details"}
            </h2>

            <p>
              Candidate Lifecycle Information
            </p>
          </div>

        </div>


        <button
          type="button"
          className="modal-close-btn"
          onClick={onClose}
          aria-label="Close candidate details"
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

          {detailFields.map(([label,key,formatter]) => (

            <div
              className="candidate-detail-card"
              key={key}
            >

              <span>
                {label}
              </span>


              <strong>
                {formatDetailValue(candidateDetail[key], formatter)}
              </strong>


            </div>

          ))}


        </div>

      )}


    </div>

  </div>
);
    
}

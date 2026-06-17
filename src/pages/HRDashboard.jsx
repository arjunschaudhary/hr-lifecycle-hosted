import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import DashboardCard from "../components/DashboardCard";

import {
  dummyCandidates,
  dummyProbationAttempts,
  dummyOffers,
  dummyActiveInterns,
  dummySignedOffers,
} from "../data";

import { getDashboardCounts } from "../utils/dashboardCounts";
import { fetchDashboardCounts } from "../services/hrDashboardService";

function buildFallbackDashboardCounts() {
  const dummyCounts = getDashboardCounts({
    candidates: dummyCandidates,
    probationAttempts: dummyProbationAttempts,
    offers: dummyOffers,
    activeInterns: dummyActiveInterns,
    signedOffers: dummySignedOffers,
  });

  return {
    totalCandidates: dummyCounts.totalCandidates,
    hrReviewPending: dummyCandidates.filter(
      (candidate) => candidate.currentStatus === "HR_REVIEW_PENDING"
    ).length,
    inProbation: dummyCounts.inProbation,
    probationReview: dummyProbationAttempts.filter(
      (attempt) => attempt.status === "PROBATION_REVIEW"
    ).length,
    probationPassed: dummyCounts.probationPassed,
    probationRejected: dummyCounts.probationRejected,
    probationExtended: dummyCounts.probationExtended,
    offerLetterProcess: dummyOffers.filter((offer) =>
      ["MID_GENERATED", "OFFER_LETTER_GENERATED"].includes(offer.offerStatus)
    ).length,
    activeInterns: dummyCounts.activeInterns,
    signedOfferSubmitted: dummyCounts.signedOfferSubmitted,
    signedOfferVerified: dummySignedOffers.filter((signedOffer) =>
      ["SIGNED_OFFER_VERIFIED", "VERIFIED"].includes(signedOffer.status)
    ).length,
    mismatchReview: dummyCounts.signedOfferMismatch,
  };
}

export default function HRDashboard() {
  const fallbackCounts = useMemo(() => buildFallbackDashboardCounts(), []);
  const [counts, setCounts] = useState(fallbackCounts);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadDashboardCounts() {
      try {
        const supabaseCounts = await fetchDashboardCounts();

        if (!isMounted) return;

        if (supabaseCounts) {
          setCounts({ ...fallbackCounts, ...supabaseCounts });
          setErrorMessage("");
        } else {
          setCounts(fallbackCounts);
          setErrorMessage("No Supabase dashboard data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load dashboard counts:", error);
        setCounts(fallbackCounts);
        setErrorMessage("Unable to load Supabase dashboard data. Showing dummy data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadDashboardCounts();

    return () => {
      isMounted = false;
    };
  }, [fallbackCounts]);

  const dashboardCards = [
    ["Total Candidates", counts.totalCandidates],
    ["HR Review Pending", counts.hrReviewPending],
    ["In Probation", counts.inProbation],
    ["Probation Review", counts.probationReview],
    ["Probation Passed", counts.probationPassed],
    ["Probation Rejected", counts.probationRejected],
    ["Probation Extended", counts.probationExtended],
    ["Offer Letter Process", counts.offerLetterProcess],
    ["Active Interns", counts.activeInterns],
    ["Signed Offer Submitted", counts.signedOfferSubmitted],
    ["Signed Offer Verified", counts.signedOfferVerified],
    ["Mismatch Review", counts.mismatchReview],
  ];

  return (
    <div style={{ padding: "20px" }}>
      <h1>HR Dashboard</h1>

      <h2>Summary</h2>

      {isLoading && <p>Loading dashboard counts...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      {dashboardCards.map(([title, value]) => (
        <DashboardCard key={title} title={title} value={value} />
      ))}

      <hr />

      <h2>Modules</h2>

      <Link to="/candidate-form">
        <button>Candidate Probation Form</button>
      </Link>

      <br /><br />

      <Link to="/probation-review">
        <button>Probation Review</button>
      </Link>

      <br /><br />

      <Link to="/offer-approval">
        <button>Offer Letter Process</button>
      </Link>

      <br /><br />

      <Link to="/active-interns">
        <button>Active Interns</button>
      </Link>

      <br /><br />

      <Link to="/signed-offer-upload">
        <button>Signed Offer Upload</button>
      </Link>

      <br /><br />

      <Link to="/signed-offer-verification">
        <button>Signed Offer Verification</button>
      </Link>

      <br /><br />

      <Link to="/activity-log">
        <button>Activity Log</button>
      </Link>
    </div>
  );
}

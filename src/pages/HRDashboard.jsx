import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import {
  dummyCandidates,
  dummyProbationAttempts,
  dummyOffers,
  dummyActiveInterns,
  dummySignedOffers,
} from "../data";

import { getDashboardCounts } from "../utils/dashboardCounts";
import { fetchDashboardCounts } from "../services/hrDashboardService";

const pageStyle = {
  padding: "24px",
  maxWidth: "1200px",
  margin: "0 auto",
};

const sectionHeaderStyle = {
  marginTop: "28px",
  marginBottom: "12px",
};

const cardGridStyle = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))",
  gap: "14px",
};

const decisionGridStyle = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
  gap: "12px",
  maxWidth: "720px",
};

const cardStyle = {
  border: "1px solid #d7dde8",
  borderRadius: "8px",
  padding: "16px",
  background: "#ffffff",
  boxShadow: "0 1px 3px rgba(15, 23, 42, 0.08)",
};

const cardTitleStyle = {
  margin: "0 0 10px",
  color: "#475569",
  fontSize: "14px",
  fontWeight: 600,
};

const cardValueStyle = {
  margin: 0,
  color: "#0f172a",
  fontSize: "28px",
  fontWeight: 700,
};

const moduleGridStyle = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))",
  gap: "12px",
};

const moduleButtonStyle = {
  width: "100%",
  minHeight: "44px",
  cursor: "pointer",
};

function MetricCard({ title, value }) {
  return (
    <div style={cardStyle}>
      <h3 style={cardTitleStyle}>{title}</h3>
      <p style={cardValueStyle}>{value}</p>
    </div>
  );
}

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

  const mainDashboardCards = [
    ["Total Candidates", counts.totalCandidates],
    ["HR Review Pending", counts.hrReviewPending],
    ["In Probation", counts.inProbation],
    ["Probation Review", counts.probationReview],
    ["Offer Letter Process", counts.offerLetterProcess],
    ["Active Interns", counts.activeInterns],
    ["Signed Offer Pending Verification", counts.signedOfferSubmitted],
    ["Signed Offer Verified", counts.signedOfferVerified],
    ["Mismatch Review", counts.mismatchReview],
  ];

  const probationDecisionCards = [
    ["Probation Passed", counts.probationPassed],
    ["Probation Rejected", counts.probationRejected],
    ["Probation Extended", counts.probationExtended],
  ];

  return (
    <div style={pageStyle}>
      <h1>HR Dashboard</h1>

      <h2 style={sectionHeaderStyle}>Summary</h2>

      {isLoading && <p>Loading dashboard counts...</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <div style={cardGridStyle}>
        {mainDashboardCards.map(([title, value]) => (
          <MetricCard key={title} title={title} value={value} />
        ))}
      </div>

      <h2 style={sectionHeaderStyle}>Probation Decisions</h2>

      <div style={decisionGridStyle}>
        {probationDecisionCards.map(([title, value]) => (
          <MetricCard key={title} title={title} value={value} />
        ))}
      </div>

      <hr />

      <h2 style={sectionHeaderStyle}>Modules</h2>

      <div style={moduleGridStyle}>
        <Link to="/candidate-form">
          <button style={moduleButtonStyle}>Candidate Probation Form</button>
        </Link>

        <Link to="/probation-review">
          <button style={moduleButtonStyle}>Probation Review</button>
        </Link>

        <Link to="/offer-approval">
          <button style={moduleButtonStyle}>Offer Letter Process</button>
        </Link>

        <Link to="/active-interns">
          <button style={moduleButtonStyle}>Active Interns</button>
        </Link>

        <Link to="/signed-offer-upload">
          <button style={moduleButtonStyle}>Signed Offer Upload</button>
        </Link>

        <Link to="/signed-offer-verification">
          <button style={moduleButtonStyle}>Signed Offer Verification</button>
        </Link>

        <Link to="/activity-log">
          <button style={moduleButtonStyle}>Activity Log</button>
        </Link>
      </div>
    </div>
  );
}

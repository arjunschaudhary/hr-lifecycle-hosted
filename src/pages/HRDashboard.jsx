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

export default function HRDashboard() {
  const counts = getDashboardCounts({
    candidates: dummyCandidates,
    probationAttempts: dummyProbationAttempts,
    offers: dummyOffers,
    activeInterns: dummyActiveInterns,
    signedOffers: dummySignedOffers,
  });

  return (
    <div style={{ padding: "20px" }}>
      <h1>HR Dashboard</h1>

      <h2>Summary</h2>

      <DashboardCard
        title="Total Candidates"
        value={counts.totalCandidates}
      />

      <DashboardCard
        title="In Probation"
        value={counts.inProbation}
      />

      <DashboardCard
        title="Probation Passed"
        value={counts.probationPassed}
      />

      <DashboardCard
        title="Probation Rejected"
        value={counts.probationRejected}
      />

      <DashboardCard
        title="Offer Letter Generated"
        value={counts.offerLetterGenerated}
      />

      <DashboardCard
        title="Offer Letter Sent"
        value={counts.offerLetterSent}
      />

      <DashboardCard
        title="Active Interns"
        value={counts.activeInterns}
      />

      <DashboardCard
        title="Signed Offer Submitted"
        value={counts.signedOfferSubmitted}
      />

      <DashboardCard
        title="Signed Offer Mismatch"
        value={counts.signedOfferMismatch}
      />

      <DashboardCard
        title="Signed Offer Rejected"
        value={counts.signedOfferRejected}
      />

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
import "./App.css";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import HRDashboard from "./pages/HRDashboard";
import CandidateProbationForm from "./pages/CandidateProbationForm";
import ProbationReview from "./pages/ProbationReview";
import OfferApproval from "./pages/OfferApproval";
import ActiveInterns from "./pages/ActiveInterns";
import SignedOfferUpload from "./pages/SignedOfferUpload";
import SignedOfferVerification from "./pages/SignedOfferVerification";
import ActivityLog from "./pages/ActivityLog";
import LeaveDashboard from "./pages/LeaveDashboard";
import LeaveApplication from "./pages/LeaveApplication";
import InternshipExtension from "./pages/InternshipExtension";


function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<HRDashboard />} />
        <Route path="/candidate-form" element={<CandidateProbationForm />} />
        <Route path="/probation-review" element={<ProbationReview />} />
        <Route path="/offer-approval" element={<OfferApproval />} />
        <Route path="/active-interns" element={<ActiveInterns />} />
        <Route path="/signed-offer-upload" element={<SignedOfferUpload />} />
        <Route
          path="/signed-offer-verification"
          element={<SignedOfferVerification />}
        />
        <Route path="/activity-log" element={<ActivityLog />} />
        <Route path="/leave-dashboard" element={<LeaveDashboard />} />
        <Route path="/leave-application" element={<LeaveApplication />} />
        <Route path="/internship-extension" element={<InternshipExtension />} />
        
      </Routes>
    </BrowserRouter>
  );
}

export default App;

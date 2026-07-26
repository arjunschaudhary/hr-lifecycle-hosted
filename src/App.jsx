import "./App.css";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";

import ProtectedRoute from "./components/ProtectedRoute";
import CandidateProtectedRoute from "./components/CandidateProtectedRoute";
import HRDashboard from "./pages/HRDashboard";
import HRLogin from "./pages/HRLogin";
import ForgotPassword from "./pages/ForgotPassword";
import ResetPassword from "./pages/ResetPassword";
import SetPassword from "./pages/SetPassword";
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
import CandidatePortal from "./pages/CandidatePortal";
import PerformanceDashboard from "./pages/PerformanceDashboard";
import DailyPerformanceMarking from "./pages/DailyPerformanceMarking";


function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<HRLogin />} />
        <Route path="/forgot-password" element={<ForgotPassword />} />
        <Route path="/reset-password" element={<ResetPassword />} />
        <Route path="/set-password" element={<SetPassword />} />
        <Route path="/candidate-form" element={<CandidateProbationForm />} />
        <Route element={<CandidateProtectedRoute />}>
          <Route path="/portal" element={<CandidatePortal />} />
        </Route>
        <Route element={<ProtectedRoute />}>
          <Route path="/" element={<HRDashboard />} />
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
          <Route
            path="/performance-dashboard"
            element={<PerformanceDashboard />}
          />
          <Route
            path="/performance-dashboard/:candidateCycleId/daily"
            element={<DailyPerformanceMarking />}
          />
        </Route>
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;

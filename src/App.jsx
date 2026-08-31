import "./App.css";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";

import ProtectedRoute from "./components/ProtectedRoute";
import CandidateProtectedRoute from "./components/CandidateProtectedRoute";
import LeadReviewProtectedRoute from "./components/LeadReviewProtectedRoute";
import PerformanceProtectedRoute from "./components/PerformanceProtectedRoute";
import PodManagementProtectedRoute from "./components/PodManagementProtectedRoute";
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
import CandidateExitForm from "./pages/CandidateExitForm";
import PerformanceDashboard from "./pages/PerformanceDashboard";
import DailyPerformanceMarking from "./pages/DailyPerformanceMarking";
import HrReviewQueue from "./pages/HrReviewQueue";
import HrReviewDetail from "./pages/HrReviewDetail";
import LeadReviews from "./pages/LeadReviews";
import LeadReviewDetail from "./pages/LeadReviewDetail";
import PodManagement from "./pages/PodManagement";
import HRExitEvaluation from "./pages/HRExitEvaluation";
import ExitAnalytics from "./pages/ExitAnalytics";
import CertificateLor from "./pages/CertificateLor";
import { useAuth } from "./context/authContext";

function CertificateLorRoute() {
  const { hasCertificateLorAccess } = useAuth();

  return (
    <ProtectedRoute
      requiredAccess={hasCertificateLorAccess}
      accessLabel="Certificate & LOR module"
    />
  );
}

function InternshipExtensionRoute() {
  const { hasInternshipExtensionAccess } = useAuth();

  return (
    <ProtectedRoute
      requiredAccess={hasInternshipExtensionAccess}
      accessLabel="Internship Extension module"
    />
  );
}

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
          <Route path="/candidate-exit-form" element={<CandidateExitForm />} />
        </Route>
        <Route element={<LeadReviewProtectedRoute />}>
          <Route path="/lead-reviews" element={<LeadReviews />} />
          <Route
            path="/lead-reviews/:candidateCycleId"
            element={<LeadReviewDetail />}
          />
        </Route>
        <Route element={<PodManagementProtectedRoute />}>
          <Route path="/pod-management" element={<PodManagement />} />
        </Route>
        <Route element={<PerformanceProtectedRoute />}>
          <Route
            path="/performance-dashboard"
            element={<PerformanceDashboard />}
          />
          <Route
            path="/performance-dashboard/:candidateCycleId/daily"
            element={<DailyPerformanceMarking />}
          />
        </Route>
        <Route element={<ProtectedRoute />}>
          <Route path="/" element={<HRDashboard />} />
          <Route path="/probation-review" element={<ProbationReview />} />
          <Route path="/hr-exit-evaluations" element={<HRExitEvaluation />} />
          <Route path="/hr-exit-evaluation" element={<HRExitEvaluation />} />
          <Route path="/hr-exit-evaluation/:exitCaseId" element={<HRExitEvaluation />} />
          <Route path="/exit-analytics" element={<ExitAnalytics />} />
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
          <Route
            path="/performance/hr-review"
            element={<HrReviewQueue />}
          />
          <Route
            path="/performance/hr-review/:candidateCycleId"
            element={<HrReviewDetail />}
          />
        </Route>
        <Route element={<CertificateLorRoute />}>
          <Route path="/certificate-lor" element={<CertificateLor />} />
        </Route>
        <Route element={<InternshipExtensionRoute />}>
          <Route path="/internship-extension" element={<InternshipExtension />} />
        </Route>
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;

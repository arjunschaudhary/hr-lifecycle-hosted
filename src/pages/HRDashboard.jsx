import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  Menu,
  UserPlus,
  ClipboardCheck,
  BriefcaseBusiness,
  Upload,
  BadgeCheck,
  Users,
  Clock3,
  Search,
  FileText,
  PenSquare,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  RefreshCw,
  CalendarClock,
  Gauge,
  Network,
  LogOut,
  BarChart3,
  FileBadge,
} from "lucide-react";

import { fetchDashboardCounts, fetchPendingExitCases } from "../services/hrDashboardService";
import { useAuth } from "../context/authContext";

const EMPTY_DASHBOARD_COUNTS = Object.freeze({
  totalCandidates: 0, hrReviewPending: 0, inProbation: 0, probationReview: 0,
  probationPassed: 0, probationRejected: 0, probationExtended: 0,
  offerLetterProcess: 0, activeInterns: 0, signedOfferSubmitted: 0,
  signedOfferVerified: 0, mismatchReview: 0,
});

function MetricCard({ title, value, icon }) {
  return (
    <div className="metric-card">
      <div className="metric-card__icon">{icon}</div>
      <div>
        <p className="metric-title">{title}</p>
        <h2 className="metric-value">{value}</h2>
      </div>
    </div>
  );
}

export default function HRDashboard() {
  const {
    hasPerformanceDashboardAccess,
    hasHrReviewAccess,
    hasPodManagementAccess,
    hasCertificateLorAccess,
    hasInternshipExtensionAccess,
  } = useAuth();

  const [counts, setCounts] = useState(EMPTY_DASHBOARD_COUNTS);
  const [pendingExitCases, setPendingExitCases] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [showModules, setShowModules] = useState(true);

  useEffect(() => {
    let mounted = true;

    async function load() {
      try {
        const [countsResult, pendingCasesResult] = await Promise.allSettled([
          fetchDashboardCounts(),
          fetchPendingExitCases(),
        ]);

        if (!mounted) return;

        const errors = [];
        if (countsResult.status === "fulfilled" && countsResult.value) {
          setCounts(countsResult.value);
        } else {
          setCounts(EMPTY_DASHBOARD_COUNTS);
          errors.push("Unable to load dashboard metrics.");
        }

        if (pendingCasesResult.status === "fulfilled") {
          setPendingExitCases(pendingCasesResult.value);
        } else {
          setPendingExitCases([]);
          errors.push("Unable to load pending exit evaluations.");
        }
        setErrorMessage(errors.join(" "));
      } catch (err) {
        console.error(err);
        setCounts(EMPTY_DASHBOARD_COUNTS);
        setPendingExitCases([]);
        setErrorMessage("Unable to load dashboard data.");
      } finally {
        if (mounted) setIsLoading(false);
      }
    }

    load();

    return () => (mounted = false);
  }, []);

  const cards = [
    ["Total Candidates", counts.totalCandidates, <Users size={22} />],
    ["HR Review Pending", counts.hrReviewPending, <ClipboardCheck size={22} />],
    ["Exit Evaluations", pendingExitCases.length, <LogOut size={22} />],
    ["In Probation", counts.inProbation, <Clock3 size={22} />],
    ["Probation Review", counts.probationReview, <Search size={22} />],
    ["Offer Process", counts.offerLetterProcess, <FileText size={22} />],
    ["Active Interns", counts.activeInterns, <BriefcaseBusiness size={22} />],
    ["Signed Offer Pending", counts.signedOfferSubmitted, <PenSquare size={22} />],
    ["Verified Offers", counts.signedOfferVerified, <BadgeCheck size={22} />],
    ["Mismatch Review", counts.mismatchReview, <AlertTriangle size={22} />],
  ];

  const decisions = [
    ["Passed", counts.probationPassed, <CheckCircle2 size={22} />],
    ["Rejected", counts.probationRejected, <XCircle size={22} />],
    ["Extended", counts.probationExtended, <RefreshCw size={22} />],
  ];

  const modules = [
    {
      path: "/candidate-form",
      label: "Candidate Form",
      icon: <UserPlus size={18} />,
    },
    {
      path: "/probation-review",
      label: "Probation Review",
      icon: <ClipboardCheck size={18} />,
    },
    {
      path: "/active-interns",
      label: "Active Interns",
      icon: <BriefcaseBusiness size={18} />,
    },
    {
      path: "/signed-offer-upload",
      label: "Signed Offer Upload",
      icon: <Upload size={18} />,
    },
    {
      path: "/signed-offer-verification",
      label: "Offer Verification",
      icon: <BadgeCheck size={18} />,
    },
    ...(hasPodManagementAccess
      ? [
          {
            path: "/pod-management",
            label: "Pod Management",
            icon: <Network size={18} />,
          },
        ]
      : []),
    ...(hasPerformanceDashboardAccess
      ? [
          {
            path: "/performance-dashboard",
            label: "Performance Dashboard",
            icon: <Gauge size={18} />,
          },
        ]
      : []),
    ...(hasHrReviewAccess
      ? [
          {
            path: "/performance/hr-review",
            label: "HR Review",
            icon: <ClipboardCheck size={18} />,
          },
        ]
      : []),
    {
      label: "Leave Dashboard",
      path: "/leave-dashboard",
    },
    {
      label: "Leave Application",
      path: "/leave-application",
    },
    ...(hasInternshipExtensionAccess
      ? [
          {
            label: "Internship Extension",
            path: "/internship-extension",
            icon: <CalendarClock size={18} />,
          },
        ]
      : []),
    {
      path: "/hr-exit-evaluations",
      label: "Exit Evaluations",
      icon: <LogOut size={18} />,
    },
    {
      path: "/exit-analytics",
      label: "Exit Analytics",
      icon: <BarChart3 size={18} />,
    },
    ...(hasCertificateLorAccess
      ? [
          {
            path: "/certificate-lor",
            label: "Certificate & LOR",
            icon: <FileBadge size={18} />,
          },
        ]
      : []),
  ];

  return (
    <div className="dashboard-layout">
      <aside className={`sidebar ${showModules ? "" : "sidebar-collapsed"}`}>
        <div className="sidebar-header">{showModules && <h2>Modules</h2>}</div>

        <div className="sidebar-menu">
          {modules.map((module) => (
            <Link key={module.path} to={module.path} className="sidebar-link">
              <button className="sidebar-btn" title={module.label}>
                <span className="sidebar-icon">{module.icon}</span>
                {showModules && <span className="sidebar-label">{module.label}</span>}
              </button>
            </Link>
          ))}
        </div>
      </aside>

      <main className="dashboard-content">
        <div className="dashboard-header">
          <button className="sidebar-toggle" onClick={() => setShowModules(!showModules)}>
            <Menu size={22} />
          </button>

          <h1 className="dashboard-title">HR Dashboard</h1>
          <p className="dashboard-subtitle">Internship Lifecycle Management</p>
        </div>

        {isLoading && <div className="alert-card">Loading dashboard...</div>}
        {errorMessage && <div className="alert-card">{errorMessage}</div>}

        {!isLoading && <>
        <h2 className="section-title">Lifecycle Overview</h2>

        <div className="metric-grid">
          {cards.map((item) => (
            <MetricCard key={item[0]} title={item[0]} value={item[1]} icon={item[2]} />
          ))}
        </div>

        <h2 className="section-title">Probation Decisions</h2>

        <div className="metric-grid">
          {decisions.map((item) => (
            <MetricCard key={item[0]} title={item[0]} value={item[1]} icon={item[2]} />
          ))}
        </div>
        </>}
      </main>
    </div>
  );
}

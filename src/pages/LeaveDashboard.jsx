import { Link } from "react-router-dom";
import { CalendarDays } from "lucide-react";
import { useEffect, useState } from "react";
import leaveDashboardService from "../services/leaveDashboardService";

import LeaveStatsCards from "../components/LeaveStatsCards";
import PendingLeaveTable from "../components/PendingLeaveTable";
import OnLeaveTodayTable from "../components/OnLeaveTodayTable";
import UpcomingLeaveTable from "../components/UpcomingLeaveTable";

export default function LeaveDashboard() {
  const [counts, setCounts] = useState({
    pending: 0,
    approved: 0,
    rejected: 0,
    onLeaveToday: 0,
    upcomingLeaves: 0,
  });

  const [refreshKey] = useState(0);

  useEffect(() => {
    let isMounted = true;

    async function refreshDashboard() {
      try {
        const data = await leaveDashboardService.getDashboardCounts();

        if (isMounted) {
          setCounts(data);
        }
      } catch (err) {
        console.error(err);
      }
    }

    refreshDashboard();

    return () => {
      isMounted = false;
    };
  }, [refreshKey]);
  return (
    <div className="app-page">
      <Link to="/" className="back-link">
        ← Back to Dashboard
      </Link>

      <div className="page-header-modern">
        <div className="page-icon">
          <CalendarDays size={28} />
        </div>

        <div>
          <h1 className="page-title-modern">
            Leave Management
          </h1>

          <p className="page-subtitle">
            Manage leave requests, approvals and monitor intern leave activity.
          </p>
        </div>
      </div>

      {/* KPI Cards */}

      <LeaveStatsCards counts={counts} />

      <br />

      {/* Pending Requests */}

      <div className="section-card">
        <h2 className="section-title">
          Pending Leave Requests
        </h2>

        <PendingLeaveTable refreshKey={refreshKey} />
      </div>

      <br />

      {/* On Leave Today */}

      <div className="section-card">
        <h2 className="section-title">
          On Leave Today
        </h2>

        <OnLeaveTodayTable refreshKey={refreshKey} />
      </div>

      <br />

      {/* Upcoming */}

      <div className="section-card">
        <h2 className="section-title">
          Upcoming Approved Leaves
        </h2>

        <UpcomingLeaveTable refreshKey={refreshKey} />
      </div>
    </div>
  );
}

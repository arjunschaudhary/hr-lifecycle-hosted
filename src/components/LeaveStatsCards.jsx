import {
  Clock3,
  CheckCircle2,
  XCircle,
  CalendarCheck2,
  CalendarDays,
} from "lucide-react";

const stats = [
  {
    key: "pending",
    label: "Pending Requests",
    icon: Clock3,
    className: "card-warning",
  },
  {
    key: "approved",
    label: "Approved",
    icon: CheckCircle2,
    className: "card-success",
  },
  {
    key: "rejected",
    label: "Rejected",
    icon: XCircle,
    className: "card-danger",
  },
  {
    key: "onLeaveToday",
    label: "On Leave Today",
    icon: CalendarCheck2,
    className: "card-primary",
  },
  {
    key: "upcomingLeaves",
    label: "Upcoming Leaves",
    icon: CalendarDays,
    className: "card-info",
  },
];

export default function LeaveStatsCards({ counts }) {
  return (
    <div className="stats-grid">
      {stats.map((item) => {
        const Icon = item.icon;

        return (
          <div key={item.key} className={`stat-card ${item.className}`}>
            <div className="stat-card-header">
              <div>
                <p className="stat-label">{item.label}</p>

                <h2 className="stat-value">
                  {counts?.[item.key] ?? 0}
                </h2>
              </div>

              <div className="stat-icon">
                <Icon size={28} />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
/**
 * AnalyticsSummaryCards.jsx
 * Grid of top-level metric summary cards for Exit Analytics.
 */

import { Users, CheckCircle, Clock, Award, Star, TrendingUp, AlertTriangle, MessageSquare } from "lucide-react";

export default function AnalyticsSummaryCards({ summary = {} }) {
  const cards = [
    {
      title: "Total Exits",
      value: summary.totalExits ?? 0,
      icon: Users,
      color: "#3b82f6",
      bg: "#eff6ff",
    },
    {
      title: "Completed Exit Process",
      value: summary.completedExitProcess ?? 0,
      icon: CheckCircle,
      color: "#16a34a",
      bg: "#f0fdf4",
    },
    {
      title: "Pending Candidate Forms",
      value: summary.pendingCandidateForms ?? 0,
      icon: Clock,
      color: "#eab308",
      bg: "#fefce8",
    },
    {
      title: "Pending HR Reviews",
      value: summary.pendingHRReviews ?? 0,
      icon: MessageSquare,
      color: "#f97316",
      bg: "#fff7ed",
    },
    {
      title: "Avg Overall Experience",
      value: `${summary.avgOverallExperience ?? 0} / 5`,
      icon: Star,
      color: "#8b5cf6",
      bg: "#f5f3ff",
    },
    {
      title: "Average NPS",
      value: summary.avgNps ?? 0,
      icon: TrendingUp,
      color: "#06b6d4",
      bg: "#ecfeff",
    },
    {
      title: "Avg Performance Rating",
      value: `${summary.avgPerformanceRating ?? 0} / 5`,
      icon: Award,
      color: "#10b981",
      bg: "#ecfdf5",
    },
    {
      title: "Preventable Exit %",
      value: `${summary.preventableExitPercentage ?? 0}%`,
      icon: AlertTriangle,
      color: "#ef4444",
      bg: "#fef2f2",
    },
  ];

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
        gap: 16,
        marginBottom: 28,
      }}
    >
      {cards.map((card, idx) => {
        const IconComponent = card.icon;
        return (
          <div
            key={idx}
            className="card"
            style={{
              padding: 16,
              display: "flex",
              alignItems: "center",
              gap: 14,
              borderRadius: 10,
              boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
            }}
          >
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: 10,
                backgroundColor: card.bg,
                color: card.color,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
              }}
            >
              <IconComponent size={22} />
            </div>

            <div>
              <span style={{ fontSize: 12, fontWeight: 600, color: "#64748b", display: "block" }}>
                {card.title}
              </span>
              <span style={{ fontSize: 20, fontWeight: 800, color: "#0f172a", marginTop: 2, display: "block" }}>
                {card.value}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

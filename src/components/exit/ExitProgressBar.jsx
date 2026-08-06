/**
 * ExitProgressBar.jsx
 * Displays the user's current section progress through the exit form.
 */

export default function ExitProgressBar({ current, total, sectionLabel }) {
  const pct = Math.round(((current) / total) * 100);

  return (
    <div
      aria-label={`Section ${current} of ${total}: ${sectionLabel}`}
      style={{ marginBottom: 24 }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontSize: 13,
          color: "#64748b",
          marginBottom: 6,
          fontWeight: 600,
        }}
      >
        <span>{sectionLabel}</span>
        <span>
          {current} / {total}
        </span>
      </div>
      <div
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
        style={{
          height: 8,
          background: "#e2e8f0",
          borderRadius: 999,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${pct}%`,
            background: "linear-gradient(90deg, #2563eb, #60a5fa)",
            borderRadius: 999,
            transition: "width 0.4s ease",
          }}
        />
      </div>
    </div>
  );
}

/**
 * ExitFormFooter.jsx
 * Form navigation/action buttons (Previous, Next, Submit).
 */

export default function ExitFormFooter({
  currentSection,
  totalSections,
  onPrev,
  onNext,
  onSubmitClick,
  submitting,
  isValid = true,
}) {
  const isFirst = currentSection === 1;
  const isLast = currentSection === totalSections;

  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        marginTop: 24,
        paddingTop: 16,
        borderTop: "1px solid #e2e8f0",
      }}
    >
      <div>
        {!isFirst && (
          <button
            type="button"
            className="btn btn-secondary"
            onClick={onPrev}
            disabled={submitting}
          >
            ← Previous Section
          </button>
        )}
      </div>

      <div style={{ display: "flex", gap: 12 }}>
        {!isLast ? (
          <button
            type="button"
            className="btn btn-primary"
            onClick={onNext}
            disabled={submitting}
          >
            Next Section →
          </button>
        ) : (
          <button
            type="button"
            className="btn btn-success"
            onClick={onSubmitClick}
            disabled={submitting || !isValid}
            aria-busy={submitting}
          >
            {submitting ? "Submitting..." : "Submit Exit Questionnaire"}
          </button>
        )}
      </div>
    </div>
  );
}

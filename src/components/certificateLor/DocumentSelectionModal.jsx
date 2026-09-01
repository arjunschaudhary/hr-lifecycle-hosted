import { useMemo, useState } from "react";
import { Send, X } from "lucide-react";

const VARIANT_DETAILS = {
  INTERN_CERTIFICATE: { label: "Intern Certificate", group: "certificate" },
  POD_LEAD_CERTIFICATE: { label: "Pod Lead Certificate", group: "certificate" },
  VOLUNTEER_CERTIFICATE: { label: "Volunteer Certificate", group: "certificate" },
  INTERN_LOR: { label: "Intern LOR", group: "lor" },
  POD_LEAD_LOR: { label: "Pod Lead LOR", group: "lor" },
  OPERATIONS_ASSOCIATE_LOR: { label: "Operations Associate LOR", group: "lor" },
};

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("en-IN", {
        day: "numeric",
        month: "short",
        year: "numeric",
      }).format(date);
}

function VariantChecklist({ title, variants, selected, onToggle }) {
  return (
    <section className="document-variant-section">
      <h3>{title}</h3>
      {variants.length === 0 ? (
        <p className="document-variant-empty">
          No {title.toLowerCase()} available.
        </p>
      ) : (
        <div className="document-variant-grid">
          {variants.map((variant) => {
            const isSelected = selected.includes(variant);

            return (
              <label
                key={variant}
                className={`document-variant-option${isSelected ? " is-selected" : ""}`}
              >
                <input
                  className="document-variant-checkbox"
                  type="checkbox"
                  checked={isSelected}
                  onChange={() => onToggle(variant)}
                />
                <span>{VARIANT_DETAILS[variant]?.label || variant}</span>
              </label>
            );
          })}
        </div>
      )}
    </section>
  );
}

export default function DocumentSelectionModal({
  candidate,
  isOpen,
  isSubmitting,
  onClose,
  onSubmit,
}) {
  const [selectedVariants, setSelectedVariants] = useState([]);
  const [validationError, setValidationError] = useState("");
  const [confirmingMismatch, setConfirmingMismatch] = useState(false);

  const certificateVariants = useMemo(
    () => candidate?.allowedCertificateVariants || [],
    [candidate],
  );
  const lorVariants = useMemo(() => candidate?.allowedLorVariants || [], [candidate]);

  if (!isOpen || !candidate) return null;

  const toggleVariant = (variant) => {
    setSelectedVariants((current) =>
      current.includes(variant)
        ? current.filter((item) => item !== variant)
        : [...current, variant],
    );
    setValidationError("");
  };

  const selectedCertificates = selectedVariants.filter(
    (variant) => VARIANT_DETAILS[variant]?.group === "certificate",
  );
  const selectedLors = selectedVariants.filter(
    (variant) => VARIANT_DETAILS[variant]?.group === "lor",
  );

  const handleSubmit = (event) => {
    event.preventDefault();
    if (selectedVariants.length === 0) {
      setValidationError("Select at least one document before continuing.");
      return;
    }

    if (candidate.warningRequired) {
      setConfirmingMismatch(true);
      return;
    }

    onSubmit({
      exitCaseId: candidate.exitCaseId,
      documentVariants: selectedVariants,
      allowDateMismatch: false,
    });
  };

  const handleContinueAnyway = () => {
    onSubmit({
      exitCaseId: candidate.exitCaseId,
      documentVariants: selectedVariants,
      allowDateMismatch: true,
    });
  };

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="document-selection-title">
      <div className="candidate-modal document-selection-modal">
        <div className="candidate-modal-header document-selection-header">
          <div>
            <h2 id="document-selection-title">Generate &amp; Send Documents</h2>
            <p>{candidate.candidateName}</p>
          </div>
          <button type="button" className="modal-close-btn" onClick={onClose} disabled={isSubmitting} aria-label="Close modal">
            <X size={18} />
          </button>
        </div>

        <form className="document-selection-form" onSubmit={handleSubmit}>
          <div className="document-selection-body">
            {!confirmingMismatch && (
              <>
                <VariantChecklist title="Certificates" variants={certificateVariants} selected={selectedVariants} onToggle={toggleVariant} />
                <VariantChecklist title="LORs" variants={lorVariants} selected={selectedVariants} onToggle={toggleVariant} />
              </>
            )}

            <section className="document-selection-summary">
              <h3>Confirm selection</h3>
              <dl className="document-selection-summary-grid">
                <dt>Candidate</dt>
                <dd>{candidate.candidateName}</dd>
                <dt>Email</dt>
                <dd>{candidate.candidateEmail}</dd>
                <dt>Exit Date</dt>
                <dd>{formatDate(candidate.exitDate)}</dd>
                <dt>Current Internship End Date</dt>
                <dd>{formatDate(candidate.currentEndDate)}</dd>
                <dt>Selected Certificates</dt>
                <dd>{selectedCertificates.map((item) => VARIANT_DETAILS[item].label).join(", ") || "None"}</dd>
                <dt>Selected LORs</dt>
                <dd>{selectedLors.map((item) => VARIANT_DETAILS[item].label).join(", ") || "None"}</dd>
              </dl>
            </section>

            {confirmingMismatch && (
              <section className="card card-danger document-selection-warning" role="alert">
                <h3>Warning</h3>
                <p>The candidate&apos;s exit date does not match their current internship end date.</p>
                <p><strong>Current internship end date:</strong> {formatDate(candidate.currentEndDate)}</p>
                <p><strong>Exit date:</strong> {formatDate(candidate.exitDate)}</p>
                <p>Certificate/LOR issuance would normally require these dates to match. Are you sure you want to continue?</p>
              </section>
            )}

            {validationError && <p className="auth-inline-error" role="alert">{validationError}</p>}
          </div>

          <div className="document-selection-footer">
            <button
              type="button"
              className="btn btn-secondary"
              onClick={confirmingMismatch ? () => setConfirmingMismatch(false) : onClose}
              disabled={isSubmitting}
            >
              {confirmingMismatch ? "Cancel" : "Cancel"}
            </button>
            {confirmingMismatch ? (
              <button type="button" className="btn btn-warning" onClick={handleContinueAnyway} disabled={isSubmitting}>
                <Send size={16} /> {isSubmitting ? "Creating requests..." : "Continue Anyway"}
              </button>
            ) : (
              <button type="submit" className="btn btn-primary" disabled={isSubmitting}>
                <Send size={16} /> {isSubmitting ? "Creating requests..." : "Confirm document selection"}
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}

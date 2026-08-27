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
    <section style={{ marginTop: 18 }}>
      <h3 style={{ margin: "0 0 8px", fontSize: 15 }}>{title}</h3>
      {variants.length === 0 ? (
        <p className="page-subtitle" style={{ margin: 0 }}>No {title.toLowerCase()} available.</p>
      ) : (
        <div style={{ display: "grid", gap: 8 }}>
          {variants.map((variant) => (
            <label key={variant} style={{ display: "flex", alignItems: "center", gap: 8, cursor: "pointer" }}>
              <input
                type="checkbox"
                checked={selected.includes(variant)}
                onChange={() => onToggle(variant)}
              />
              <span>{VARIANT_DETAILS[variant]?.label || variant}</span>
            </label>
          ))}
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
      <div className="candidate-modal" style={{ maxWidth: 620 }}>
        <div className="candidate-modal-header">
          <div>
            <h2 id="document-selection-title" style={{ margin: 0, fontSize: 18 }}>Generate &amp; Send Documents</h2>
            <p className="page-subtitle" style={{ margin: "4px 0 0" }}>{candidate.candidateName}</p>
          </div>
          <button type="button" className="modal-close-btn" onClick={onClose} disabled={isSubmitting} aria-label="Close modal">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} style={{ marginTop: 16 }}>
          {!confirmingMismatch && (
            <>
              <VariantChecklist title="Certificate" variants={certificateVariants} selected={selectedVariants} onToggle={toggleVariant} />
              <VariantChecklist title="LOR" variants={lorVariants} selected={selectedVariants} onToggle={toggleVariant} />
            </>
          )}

          <section style={{ marginTop: 22, padding: 14, background: "#f8fafc", border: "1px solid #e2e8f0", borderRadius: 8 }}>
            <h3 style={{ margin: "0 0 10px", fontSize: 15 }}>Confirm selection</h3>
            <div style={{ display: "grid", gap: 5, fontSize: 13 }}>
              <div><strong>Candidate:</strong> {candidate.candidateName}</div>
              <div><strong>Email:</strong> {candidate.candidateEmail}</div>
              <div><strong>Exit Date:</strong> {formatDate(candidate.exitDate)}</div>
              <div><strong>Current Internship End Date:</strong> {formatDate(candidate.currentEndDate)}</div>
              <div><strong>Selected Certificates:</strong> {selectedCertificates.map((item) => VARIANT_DETAILS[item].label).join(", ") || "None"}</div>
              <div><strong>Selected LORs:</strong> {selectedLors.map((item) => VARIANT_DETAILS[item].label).join(", ") || "None"}</div>
            </div>
          </section>

          {confirmingMismatch && (
            <section className="card card-danger" role="alert" style={{ marginTop: 18, padding: 14 }}>
              <h3 style={{ margin: "0 0 8px", fontSize: 15 }}>Warning</h3>
              <p style={{ margin: "0 0 8px" }}>The candidate&apos;s exit date does not match their current internship end date.</p>
              <p style={{ margin: "0 0 4px" }}><strong>Current internship end date:</strong> {formatDate(candidate.currentEndDate)}</p>
              <p style={{ margin: "0 0 8px" }}><strong>Exit date:</strong> {formatDate(candidate.exitDate)}</p>
              <p style={{ margin: 0 }}>Certificate/LOR issuance would normally require these dates to match. Are you sure you want to continue?</p>
            </section>
          )}

          {validationError && <p className="auth-inline-error" role="alert">{validationError}</p>}

          <div style={{ display: "flex", justifyContent: "flex-end", gap: 10, marginTop: 20 }}>
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

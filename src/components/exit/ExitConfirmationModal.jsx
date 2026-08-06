/**
 * ExitConfirmationModal.jsx
 * Modal dialog to confirm submission of the Exit Questionnaire.
 */

import { AlertTriangle, X } from "lucide-react";

export default function ExitConfirmationModal({
  isOpen,
  onClose,
  onConfirm,
  submitting,
}) {
  if (!isOpen) return null;

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="confirm-modal-title">
      <div className="candidate-modal" style={{ maxWidth: 500 }}>
        <div className="candidate-modal-header" style={{ marginBottom: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 12,
                background: "#fef3c7",
                color: "#d97706",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <AlertTriangle size={20} />
            </div>
            <h2 id="confirm-modal-title" style={{ margin: 0, fontSize: 20 }}>
              Submit Exit Questionnaire?
            </h2>
          </div>
          <button
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close modal"
          >
            <X size={18} />
          </button>
        </div>

        <div style={{ marginBottom: 24, color: "#475569", lineHeight: 1.5 }}>
          <p style={{ margin: "0 0 12px 0" }}>
            Please review your answers before submitting. Once submitted, you will not be able to modify your exit feedback responses.
          </p>
          <p style={{ margin: 0, fontSize: 13, color: "#64748b" }}>
            Are you sure you want to finalize your submission?
          </p>
        </div>

        <div style={{ display: "flex", justifyContent: "flex-end", gap: 12 }}>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={onClose}
            disabled={submitting}
          >
            Cancel
          </button>
          <button
            type="button"
            className="btn btn-success"
            onClick={onConfirm}
            disabled={submitting}
            aria-busy={submitting}
          >
            {submitting ? "Submitting..." : "Yes, Confirm & Submit"}
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * InitiateExitModal.jsx
 * Modal dialog for HR to initiate an exit process for an active intern.
 */

import { useEffect, useState } from "react";
import { AlertCircle, LogOut, X } from "lucide-react";

function getTodayInputValue() {
  const today = new Date();
  const timezoneOffset = today.getTimezoneOffset() * 60000;
  return new Date(today.getTime() - timezoneOffset)
    .toISOString()
    .split("T")[0];
}

export default function InitiateExitModal({
  isOpen,
  intern,
  onClose,
  onConfirm,
  isSubmitting,
}) {
  const today = getTodayInputValue();

  const [exitType, setExitType] = useState("COMPLETED_TERM");
  const [exitDate, setExitDate] = useState(today);
  const [notes, setNotes] = useState("");
  const [validationError, setValidationError] = useState("");

  useEffect(() => {
    if (!isOpen || !intern) return;

    setExitType("COMPLETED_TERM");
    setExitDate(today);
    setNotes("");
    setValidationError("");
  }, [intern, isOpen, today]);

  if (!isOpen || !intern) return null;

  const handleSubmit = (e) => {
    e.preventDefault();
    setValidationError("");

    if (!exitType) {
      setValidationError("Please select an Exit Type.");
      return;
    }

    if (!exitDate) {
      setValidationError("Please select an Exit Date.");
      return;
    }

    onConfirm({
      candidateId: intern.candidateId || intern.id,
      exitType,
      exitDate,
      notes,
    });
  };

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="initiate-exit-modal-title">
      <div className="candidate-modal" style={{ maxWidth: 520 }}>
        <div className="candidate-modal-header">
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div
              style={{
                width: 36,
                height: 36,
                borderRadius: 8,
                background: "#fef3c7",
                color: "#d97706",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <LogOut size={20} />
            </div>
            <div>
              <h2 id="initiate-exit-modal-title" style={{ margin: 0, fontSize: 18, fontWeight: 700 }}>
                Initiate Exit Process
              </h2>
              <p style={{ margin: "2px 0 0 0", fontSize: 13, color: "#64748b" }}>
                {intern.fullName} {intern.mid ? `(${intern.mid})` : ""}
              </p>
            </div>
          </div>

          <button
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close modal"
          >
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} style={{ marginTop: 20 }}>
          {validationError && (
            <div style={{ marginBottom: 16, padding: 10, background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: 6, color: "#dc2626", fontSize: 13, display: "flex", alignItems: "center", gap: 6 }}>
              <AlertCircle size={16} />
              <span>{validationError}</span>
            </div>
          )}

          <div style={{ marginBottom: 16 }}>
            <label style={{ display: "block", fontWeight: 600, fontSize: 14, marginBottom: 6 }}>
              Exit Type <span style={{ color: "#dc2626" }}>*</span>
            </label>
            <select
              value={exitType}
              onChange={(e) => setExitType(e.target.value)}
              required
              disabled={isSubmitting}
              style={{
                width: "100%",
                padding: "10px",
                borderRadius: 8,
                border: "1px solid #cbd5e1",
                fontSize: 14,
              }}
            >
              <option value="COMPLETED_TERM">Completed Term</option>
              <option value="EARLY_EXIT">Early Exit</option>
              <option value="TERMINATED">Terminated</option>
            </select>
          </div>

          <div style={{ marginBottom: 16 }}>
            <label style={{ display: "block", fontWeight: 600, fontSize: 14, marginBottom: 6 }}>
              Exit Date <span style={{ color: "#dc2626" }}>*</span>
            </label>
            <input
              type="date"
              value={exitDate}
              onChange={(e) => setExitDate(e.target.value)}
              required
              disabled={isSubmitting}
              style={{
                width: "100%",
                padding: "10px",
                borderRadius: 8,
                border: "1px solid #cbd5e1",
                fontSize: 14,
              }}
            />
          </div>

          <div style={{ marginBottom: 24 }}>
            <label style={{ display: "block", fontWeight: 600, fontSize: 14, marginBottom: 6 }}>
              Optional Notes
            </label>
            <textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Add any internal notes regarding this exit initiation..."
              disabled={isSubmitting}
              style={{
                width: "100%",
                padding: "10px",
                borderRadius: 8,
                border: "1px solid #cbd5e1",
                fontSize: 14,
                resize: "vertical",
                fontFamily: "inherit",
              }}
            />
          </div>

          <div style={{ display: "flex", justifyContent: "flex-end", gap: 10 }}>
            <button
              type="button"
              className="btn btn-secondary"
              onClick={onClose}
              disabled={isSubmitting}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="btn btn-warning"
              disabled={isSubmitting}
            >
              {isSubmitting ? "Initiating..." : "Initiate Exit"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

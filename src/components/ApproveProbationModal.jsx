import { useEffect, useState } from "react";

function getTodayInputValue() {
  const today = new Date();
  const timezoneOffset = today.getTimezoneOffset() * 60000;

  return new Date(today.getTime() - timezoneOffset)
    .toISOString()
    .split("T")[0];
}

export default function ApproveProbationModal({
  isOpen,
  candidate,
  onClose,
  onConfirm,
}) {
  const today = getTodayInputValue();

  const [joiningDate, setJoiningDate] = useState(today);
  const [durationMonths, setDurationMonths] = useState(4);

  useEffect(() => {
    if (!isOpen || !candidate) return;

    let isCurrent = true;

    queueMicrotask(() => {
      if (!isCurrent) return;

      setJoiningDate(today);
      setDurationMonths(4);
    });

    return () => {
      isCurrent = false;
    };
  }, [candidate, isOpen, today]);

  if (!isOpen || !candidate) return null;

  return (
    <div className="modal-overlay">
      <div className="candidate-modal">

        <div className="candidate-modal-header">

          <div>
            <h2>Approve Candidate for Probation</h2>
            <p>{candidate.fullName}</p>
          </div>

          <button
            className="modal-close-btn"
            onClick={onClose}
          >
            ×
          </button>

        </div>

        <div style={{ marginTop: "25px" }}>

          <label>
            <strong>Internship / Probation Start Date</strong>
          </label>

          <br />

          <input
            type="date"
            value={joiningDate}
            onChange={(e) => setJoiningDate(e.target.value)}
            style={{
              width: "100%",
              marginTop: "8px",
              marginBottom: "20px",
              padding: "10px",
            }}
          />

          <label>
            <strong>Internship Duration</strong>
          </label>

          <br />

          <select
            value={durationMonths}
            onChange={(e) =>
              setDurationMonths(Number(e.target.value))
            }
            style={{
              width: "100%",
              marginTop: "8px",
              padding: "10px",
            }}
          >
            <option value={4}>4 months / 120 days</option>
            <option value={3}>3 months / 90 days</option>
          </select>

        </div>

        <div
          style={{
            marginTop: "30px",
            display: "flex",
            justifyContent: "flex-end",
            gap: "10px",
          }}
        >
          <button
            className="btn"
            onClick={onClose}
          >
            Cancel
          </button>

          <button
            className="btn btn-success"
            onClick={() =>
              onConfirm({
                candidateId: candidate.candidateId,
                joiningDate,
                durationMonths,
              })
            }
          >
            Approve
          </button>
        </div>

      </div>
    </div>
  );
}

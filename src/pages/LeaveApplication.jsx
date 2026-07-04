import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { CalendarPlus } from "lucide-react";

import {
  getEligibleCandidates,
  submitLeaveApplication,
} from "../services/leaveApplicationService";

export default function LeaveApplication() {
  const [candidates, setCandidates] = useState([]);

  const [form, setForm] = useState({
    candidate_id: "",
    leave_type: "Casual Leave",
    start_date: "",
    end_date: "",
    reason: "",
    supporting_document: "",
  });

  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadCandidates() {
      try {
        const data = await getEligibleCandidates();

        if (isMounted) {
          setCandidates(data || []);
        }
      } catch (err) {
        console.error(err);
      }
    }

    loadCandidates();

    return () => {
      isMounted = false;
    };
  }, []);

  function handleChange(e) {
    setForm({
      ...form,
      [e.target.name]: e.target.value,
    });
  }

  async function handleSubmit(e) {
    e.preventDefault();

    setLoading(true);
    setMessage("");

    try {
      await submitLeaveApplication(form);

      setMessage("Leave application submitted successfully.");

      setForm({
        candidate_id: "",
        leave_type: "Casual Leave",
        start_date: "",
        end_date: "",
        reason: "",
        supporting_document: "",
      });
    } catch (err) {
      alert(err.message);
    }

    setLoading(false);
  }

  return (
    <div className="app-page">

      <Link
        to="/"
        className="back-link"
      >
        ← Back to Dashboard
      </Link>

      <div className="page-header-modern">

        <div className="page-icon">
          <CalendarPlus size={28} />
        </div>

        <div>
          <h1 className="page-title-modern">
            Leave Application
          </h1>

          <p className="page-subtitle">
            Submit a leave request for an intern.
          </p>
        </div>

      </div>

      {message && (
        <p className="success-message">
          {message}
        </p>
      )}

      <form
        onSubmit={handleSubmit}
        className="form-card"
      >

        <div className="form-group">
          <label>Candidate</label>

          <select
            name="candidate_id"
            value={form.candidate_id}
            onChange={handleChange}
            required
          >
            <option value="">
              Select Candidate
            </option>

            {candidates.map((candidate) => (
              <option
                key={candidate.candidate_id}
                value={candidate.candidate_id}
              >
                {candidate.full_name}
                {" "}
                (
                {candidate.lifecycle_status}
                )
              </option>
            ))}
          </select>
        </div>

        <div className="form-group">
          <label>Leave Type</label>

          <select
            name="leave_type"
            value={form.leave_type}
            onChange={handleChange}
          >
            <option>Casual Leave</option>
            <option>Sick Leave</option>
            <option>Emergency Leave</option>
            <option>Work From Home</option>
          </select>
        </div>

        <div className="form-group">
          <label>Start Date</label>

          <input
            type="date"
            name="start_date"
            value={form.start_date}
            onChange={handleChange}
            required
          />
        </div>

        <div className="form-group">
          <label>End Date</label>

          <input
            type="date"
            name="end_date"
            value={form.end_date}
            onChange={handleChange}
            required
          />
        </div>

        <div className="form-group">
          <label>Reason</label>

          <textarea
            rows="4"
            name="reason"
            value={form.reason}
            onChange={handleChange}
            required
          />
        </div>

        <div className="form-group">
          <label>Supporting Document (optional)</label>

          <input
            type="text"
            name="supporting_document"
            placeholder="Document URL or filename"
            value={form.supporting_document}
            onChange={handleChange}
          />
        </div>

        <button
          className="btn btn-primary"
          disabled={loading}
        >
          {loading
            ? "Submitting..."
            : "Submit Leave Request"}
        </button>

      </form>
    </div>
  );
}

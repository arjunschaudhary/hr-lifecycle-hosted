import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { CalendarClock } from "lucide-react";
import {
  extendInternship,
  fetchExtensionCandidates,
} from "../services/internshipExtensionService";

const extensionMonthOptions = [1, 2, 3, 4, 5, 6];

function displayValue(value) {
  return value === null || value === undefined || value === "" ? "-" : value;
}

export default function InternshipExtension() {
  const [candidates, setCandidates] = useState([]);
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState("");
  const [extensionMonths, setExtensionMonths] = useState(1);
  const [reason, setReason] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState("");
  const [errorMessage, setErrorMessage] = useState("");

  const selectedCandidate = useMemo(
    () =>
      candidates.find(
        (candidate) => candidate.candidate_id === selectedCandidateId
      ),
    [candidates, selectedCandidateId]
  );

  async function loadCandidates(term = searchTerm) {
    try {
      setIsLoading(true);
      const data = await fetchExtensionCandidates(term);
      setCandidates(data);

      if (
        selectedCandidateId &&
        !data.some((candidate) => candidate.candidate_id === selectedCandidateId)
      ) {
        setSelectedCandidateId("");
      }
    } catch (error) {
      console.error("Unable to load extension candidates:", error);
      setErrorMessage(error.message || "Unable to load extension candidates.");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    loadCandidates("");
  }, []);

  async function handleSearch(event) {
    event.preventDefault();
    setErrorMessage("");
    setMessage("");
    await loadCandidates(searchTerm);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setErrorMessage("");
    setMessage("");

    try {
      setIsSubmitting(true);

      const result = await extendInternship({
        candidateId: selectedCandidateId,
        extensionMonths,
        reason,
        performedBy: "HR",
      });

      setMessage(
        `Internship extended. New end date: ${result.currentEndDate}.`
      );
      setReason("");
      setExtensionMonths(1);
      await loadCandidates(searchTerm);
    } catch (error) {
      console.error("Unable to extend internship:", error);
      setErrorMessage(error.message || "Unable to extend internship.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="app-page">
      <Link to="/" className="back-link">
        {"<- Back to Dashboard"}
      </Link>

      <div className="page-header-modern">
        <div className="page-icon">
          <CalendarClock size={28} />
        </div>

        <div>
          <h1 className="page-title-modern">
            Internship Extension
          </h1>

          <p className="page-subtitle">
            Extend internship duration and update leave allocation.
          </p>
        </div>
      </div>

      {message && <p className="success-message">{message}</p>}
      {errorMessage && <p className="error-message">{errorMessage}</p>}

      <form onSubmit={handleSearch} className="form-card">
        <div className="form-group">
          <label>Search Candidates</label>

          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Search by name, email, phone, MID or role"
          />
        </div>

        <button type="submit" className="btn btn-secondary">
          Search
        </button>
      </form>

      <br />

      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>Candidate</th>
              <th>MID</th>
              <th>Email</th>
              <th>Phone</th>
              <th>Status</th>
              <th>Current End Date</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody>
            {isLoading ? (
              <tr>
                <td colSpan={7}>Loading candidates...</td>
              </tr>
            ) : candidates.length === 0 ? (
              <tr>
                <td colSpan={7}>No eligible candidates found.</td>
              </tr>
            ) : (
              candidates.map((candidate) => (
                <tr key={candidate.candidate_id}>
                  <td>{candidate.full_name}</td>
                  <td>{displayValue(candidate.mid)}</td>
                  <td>{candidate.email}</td>
                  <td>{displayValue(candidate.phone)}</td>
                  <td>{candidate.lifecycle_status}</td>
                  <td>{displayValue(candidate.current_end_date)}</td>
                  <td>
                    <button
                      type="button"
                      className="btn btn-primary"
                      onClick={() =>
                        setSelectedCandidateId(candidate.candidate_id)
                      }
                    >
                      Select
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <br />

      {selectedCandidate && (
        <form onSubmit={handleSubmit} className="form-card">
          <h2 className="section-title">
            Extension Details
          </h2>

          <div className="candidate-details-grid">
            <div className="candidate-detail-card">
              <span>Candidate</span>
              <strong>{selectedCandidate.full_name}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>MID</span>
              <strong>{displayValue(selectedCandidate.mid)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Email</span>
              <strong>{selectedCandidate.email}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Phone</span>
              <strong>{displayValue(selectedCandidate.phone)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Current End Date</span>
              <strong>{displayValue(selectedCandidate.current_end_date)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Allocated Leaves</span>
              <strong>{displayValue(selectedCandidate.allocated_leave_days)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Approved Leaves</span>
              <strong>{displayValue(selectedCandidate.approved_leave_days)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Extra Leaves</span>
              <strong>{displayValue(selectedCandidate.extra_leave_days)}</strong>
            </div>

            <div className="candidate-detail-card">
              <span>Remaining Leaves</span>
              <strong>{displayValue(selectedCandidate.remaining_leave_days)}</strong>
            </div>
          </div>

          <br />

          <div className="form-group">
            <label>Extension Months</label>

            <select
              className="form-select"
              value={extensionMonths}
              onChange={(event) =>
                setExtensionMonths(Number(event.target.value))
              }
            >
              {extensionMonthOptions.map((month) => (
                <option key={month} value={month}>
                  {month} month{month > 1 ? "s" : ""}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label>Reason / Remarks</label>

            <textarea
              className="form-textarea"
              rows="4"
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              required
            />
          </div>

          <button
            type="submit"
            className="btn btn-success submit-btn"
            disabled={isSubmitting}
          >
            {isSubmitting ? "Saving..." : "Confirm Extension"}
          </button>
        </form>
      )}
    </div>
  );
}

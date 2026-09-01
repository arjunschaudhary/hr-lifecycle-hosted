import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { ArrowLeft, FileBadge, RefreshCw } from "lucide-react";

import DocumentSelectionModal from "../components/certificateLor/DocumentSelectionModal";
import {
  fetchCertificateLorExitCases,
  requestExitDocuments,
} from "../services/certificateLorService";

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

function StatusBadge({ status }) {
  return <span className="badge badge-secondary">{status === "NOT_REQUESTED" ? "Not requested" : status}</span>;
}

export default function CertificateLor() {
  const [exitCases, setExitCases] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [actionMessage, setActionMessage] = useState("");
  const [selectedCandidate, setSelectedCandidate] = useState(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const loadExitCases = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setExitCases(await fetchCertificateLorExitCases());
    } catch (loadError) {
      setExitCases([]);
      setError(loadError.message || "Unable to load Certificate & LOR exit cases.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let isMounted = true;

    async function loadInitialExitCases() {
      try {
        const results = await fetchCertificateLorExitCases();
        if (isMounted) setExitCases(results);
      } catch (loadError) {
        if (isMounted) {
          setExitCases([]);
          setError(loadError.message || "Unable to load Certificate & LOR exit cases.");
        }
      } finally {
        if (isMounted) setLoading(false);
      }
    }

    void loadInitialExitCases();
    return () => {
      isMounted = false;
    };
  }, []);

  const matchingDateCount = useMemo(
    () => exitCases.filter((exitCase) => exitCase.dateMatches).length,
    [exitCases],
  );

  const handleRequest = async ({ exitCaseId, documentVariants, allowDateMismatch }) => {
    setIsSubmitting(true);
    setError("");
    setActionMessage("");
    try {
      const result = await requestExitDocuments({
        exitCaseId,
        documentVariants,
        allowDateMismatch,
      });
      setActionMessage(result.message);
      setSelectedCandidate(null);
      await loadExitCases();
    } catch (requestError) {
      setError(requestError.message || "Unable to prepare the document selection.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="page-container">
      <div className="page-header certificate-lor-page-header">
        <div>
          <h1 className="page-title">Certificate &amp; LOR</h1>
          <p className="page-subtitle">Review all initiated exit cases and create Certificate and LOR requests.</p>
        </div>
        <div className="certificate-lor-header-actions">
          <Link className="btn btn-secondary" to="/">
            <ArrowLeft size={16} /> Back to Dashboard
          </Link>
          <button className="btn btn-secondary" type="button" onClick={loadExitCases} disabled={loading}>
            <RefreshCw size={16} /> Refresh
          </button>
        </div>
      </div>

      <div className="card" style={{ marginBottom: 20, padding: 16 }}>
        <strong>{matchingDateCount}</strong> exit case{matchingDateCount === 1 ? "" : "s"} with matching dates out of {exitCases.length} loaded.
        <p className="page-subtitle" style={{ margin: "6px 0 0" }}>
          Date mismatches require an explicit HR confirmation; allowed variants are supplied by the secure server-side issuance RPC.
        </p>
      </div>

      {actionMessage && <div className="auth-success-message" role="status">{actionMessage}</div>}
      {error && (
        <div className="card card-danger" role="alert" style={{ marginBottom: 20 }}>
          <p style={{ margin: 0 }}>{error}</p>
        </div>
      )}

      {loading ? (
        <div className="card" role="status">Loading Certificate &amp; LOR exit cases...</div>
      ) : !error && exitCases.length === 0 ? (
        <div className="card">No initiated or completed exit cases are available.</div>
      ) : !error ? (
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>Full Name</th>
                <th>Email</th>
                <th>Applied Role</th>
                <th>Internship Ended On</th>
                <th>Current Internship End Date</th>
                <th>Date Check</th>
                <th>Certificate Status</th>
                <th>LOR Status</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {exitCases.map((exitCase) => (
                <tr key={exitCase.exitCaseId}>
                  <td><strong>{exitCase.candidateName}</strong></td>
                  <td>{exitCase.candidateEmail}</td>
                  <td>{exitCase.appliedRole}</td>
                  <td>{formatDate(exitCase.exitDate)}</td>
                  <td>{formatDate(exitCase.currentEndDate)}</td>
                  <td>
                    {exitCase.dateMatches ? (
                      <span className="badge badge-success">Dates match</span>
                    ) : (
                      <div>
                        <span className="badge badge-warning">Warning required</span>
                        <p className="page-subtitle" style={{ margin: "5px 0 0", maxWidth: 220 }}>Internship end date does not match the exit date.</p>
                      </div>
                    )}
                  </td>
                  <td><StatusBadge status={exitCase.certificateStatus} /></td>
                  <td><StatusBadge status={exitCase.lorStatus} /></td>
                  <td>
                    <button
                      className="btn btn-primary"
                      type="button"
                      onClick={() => setSelectedCandidate(exitCase)}
                      style={{ whiteSpace: "nowrap" }}
                    >
                      <FileBadge size={16} /> Generate &amp; Send Documents
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {selectedCandidate && (
        <DocumentSelectionModal
          candidate={selectedCandidate}
          isOpen
          isSubmitting={isSubmitting}
          onClose={() => setSelectedCandidate(null)}
          onSubmit={handleRequest}
        />
      )}
    </div>
  );
}

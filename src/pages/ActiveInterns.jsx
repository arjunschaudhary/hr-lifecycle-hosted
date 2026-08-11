import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { BriefcaseBusiness } from "lucide-react";
import { dummyActiveInterns } from "../data";
import CandidateDetailModal from "../components/CandidateDetailModal";
import { useAuth } from "../context/authContext";
import InitiateExitModal from "../components/exit/InitiateExitModal";
import { markSignedOfferSubmitted } from "../services/lifecycleActionService";
import {
  fetchActiveInterns,
  initiateExitForCandidate,
} from "../services/activeInternsService";
import { createCandidatePortalAccount } from "../services/candidatePortalAccountService";
import {
  grantHrPsyconnectAccess,
  revokeHrPsyconnectAccess,
} from "../services/hrPsyconnectAccessService";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function buildFallbackActiveInternRecords() {
  return dummyActiveInterns.map((intern) => ({
    id: intern.id,
    candidateId: intern.candidateId,
    fullName: intern.fullName,
    email: "",
    phone: "",
    appliedRole: intern.role,
    department: intern.department,
    team: intern.team,
    project: intern.project,
    lifecycleStatus: intern.status,
    mid: intern.mid,
    offerStatus: "",
    sentAt: intern.activeStartDate,
    signedOfferStatus: "",
    portalAccountStatus: null,
    portalUserId: null,
    roleCode: null,
    hrPsyconnectAccessActive: false,
    hrPsyconnectAccessGrantedAt: null,
    hrPsyconnectUserRoleId: null,
    hasActiveExit: false,
    exitCaseStatus: null,
  }));
}

function mapSupabaseActiveInternRecord(row) {
  return {
    id: row.candidate_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    department: row.department,
    team: "",
    project: "",
    lifecycleStatus: row.lifecycle_status,
    mid: row.mid,
    offerStatus: row.offer_status,
    sentAt: row.sent_at ?? row.offer_letter_sent_at,
    signedOfferStatus: row.signed_offer_status,
    portalAccountStatus: row.portal_account_status,
    portalUserId: row.portal_user_id,
    roleCode: row.role_code ?? null,
    hrPsyconnectAccessActive:
      row.hr_psyconnect_access_active === true,
    hrPsyconnectAccessGrantedAt:
      row.hr_psyconnect_access_granted_at ?? null,
    hrPsyconnectUserRoleId: row.hr_psyconnect_user_role_id ?? null,
    hasActiveExit: Boolean(row.has_active_exit),
    exitCaseStatus: row.exit_case_status || null,
  };
}

function isHrPsyconnectIntern(intern) {
  return (
    intern.appliedRole === "HR Psyconnect Intern" && intern.roleCode === "HPI"
  );
}

function hasActivePortalAccount(intern) {
  return (
    intern.portalAccountStatus === "ACTIVE" &&
    isValidUuid(intern.portalUserId)
  );
}

function getStatusClass(status) {
  switch (status) {
    case "ACTIVE":
      return "badge-success";

    case "SIGNED_OFFER_SUBMITTED":
      return "badge-primary";

    default:
      return "badge-warning";
  }
}

const LIFECYCLE_STATUS_OPTIONS = [
  { value: "", label: "All Statuses" },
  { value: "ACTIVE", label: "Active" },
  { value: "SIGNED_OFFER_SUBMITTED", label: "Signed Offer Submitted" },
  { value: "SIGNED_OFFER_VERIFIED", label: "Signed Offer Verified" },
  { value: "MISMATCH_REVIEW", label: "Mismatch Review" },
];

const SORT_OPTIONS = [
  { value: "name_asc", label: "Name A \u2192 Z" },
  { value: "name_desc", label: "Name Z \u2192 A" },
  { value: "date_asc", label: "Sent Date Oldest \u2192 Newest" },
  { value: "date_desc", label: "Sent Date Newest \u2192 Oldest" },
];

function applyInternsSort(arr, sortKey) {
  return [...arr].sort((a, b) => {
    if (sortKey === "name_asc" || sortKey === "name_desc") {
      const cmp = (a.fullName || "").localeCompare(b.fullName || "");
      return sortKey === "name_asc" ? cmp : -cmp;
    }
    const aMs = a.sentAt ? new Date(a.sentAt).getTime() : -Infinity;
    const bMs = b.sentAt ? new Date(b.sentAt).getTime() : -Infinity;
    if (aMs !== bMs) return sortKey === "date_asc" ? aMs - bMs : bMs - aMs;
    return (a.fullName || "").localeCompare(b.fullName || "");
  });
}

export default function ActiveInterns() {
  const { hasPodManagementAccess } = useAuth();
  const fallbackRecords = useMemo(() => buildFallbackActiveInternRecords(), []);
  const [activeInterns, setActiveInterns] = useState(fallbackRecords);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [actionCandidateId, setActionCandidateId] = useState(null);
  const [portalActionCandidateId, setPortalActionCandidateId] = useState(null);
  const [accessActionCandidateIds, setAccessActionCandidateIds] = useState(
    () => new Set(),
  );
  const [actionMessage, setActionMessage] = useState("");
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);
  const [initiateExitCandidate, setInitiateExitCandidate] = useState(null);
  const [isInitiatingExit, setIsInitiatingExit] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const [filterStatus, setFilterStatus] = useState("");
  const [filterDepartment, setFilterDepartment] = useState("");
  const [sortKey, setSortKey] = useState("name_asc");

  const departmentOptions = useMemo(() => {
    const depts = new Set();
    activeInterns.forEach((i) => { if (i.department) depts.add(i.department); });
    return Array.from(depts).sort();
  }, [activeInterns]);

  const hasActiveControls =
    searchTerm.trim() !== "" || filterStatus !== "" || filterDepartment !== "" || sortKey !== "name_asc";

  const handleResetControls = useCallback(() => {
    setSearchTerm("");
    setFilterStatus("");
    setFilterDepartment("");
    setSortKey("name_asc");
  }, []);

  // STABLE ORDERING FIX: displayedInterns is derived purely from raw data + control state.
  // Action state (actionCandidateId, portalActionCandidateId, etc.) is NOT a dependency,
  // so clicking action buttons never reorders rows.
  const displayedInterns = useMemo(() => {
    const q = searchTerm.trim().toLowerCase();
    const filtered = activeInterns.filter((i) => {
      if (q && ![
        i.fullName, i.email, i.appliedRole,
      ].some((v) => (v || "").toLowerCase().includes(q))) return false;
      if (filterStatus && i.lifecycleStatus !== filterStatus) return false;
      if (filterDepartment && i.department !== filterDepartment) return false;
      return true;
    });
    return applyInternsSort(filtered, sortKey);
  }, [activeInterns, searchTerm, filterStatus, filterDepartment, sortKey]);

  async function refreshActiveInterns() {
    try {
      const records = await fetchActiveInterns();

      if (records?.length) {
        setActiveInterns(records.map(mapSupabaseActiveInternRecord));
        setErrorMessage("");
      } else {
        setActiveInterns(fallbackRecords);
        setErrorMessage("No Supabase active interns data found. Showing dummy data.");
      }
    } catch (error) {
      console.error("Unable to load active interns:", error);
      setActiveInterns(fallbackRecords);
      setErrorMessage("Unable to load Supabase active interns data. Showing dummy data.");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    let isMounted = true;

    async function loadActiveInterns() {
      try {
        const records = await fetchActiveInterns();

        if (!isMounted) return;

        if (records?.length) {
          setActiveInterns(records.map(mapSupabaseActiveInternRecord));
          setErrorMessage("");
        } else {
          setActiveInterns(fallbackRecords);
          setErrorMessage("No Supabase active interns data found. Showing dummy data.");
        }
      } catch (error) {
        if (!isMounted) return;

        console.error("Unable to load active interns:", error);
        setActiveInterns(fallbackRecords);
        setErrorMessage("Unable to load Supabase active interns data. Showing dummy data.");
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadActiveInterns();

    return () => {
      isMounted = false;
    };
  }, [fallbackRecords]);

  async function handleMarkSignedOfferSubmitted(intern) {
    setActionCandidateId(intern.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      await markSignedOfferSubmitted({
        candidateId: intern.candidateId,
        performedBy: "HR",
      });

      setActionMessage("Signed offer marked as submitted.");
      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to mark signed offer as submitted:", error);
      setErrorMessage(error.message || "Unable to mark signed offer as submitted.");
    } finally {
      setActionCandidateId(null);
    }
  }

  async function handleCreatePortalAccount(intern) {
    setPortalActionCandidateId(intern.candidateId);
    setActionMessage("");
    setErrorMessage("");

    try {
      const response = await createCandidatePortalAccount({
        candidateId: intern.candidateId,
      });

      if (response.outcome === "ACTIVATED") {
        setActionMessage(
          response.invitation_sent
            ? `Portal account created and invitation sent to ${response.email}.`
            : "Portal account activated for the existing authentication user.",
        );
      } else if (response.outcome === "REACTIVATED") {
        setActionMessage("Portal account reactivated successfully.");
      } else if (response.outcome === "REPAIRED") {
        setActionMessage("Portal account records repaired successfully.");
      } else {
        setActionMessage("Portal account is already active.");
      }

      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to create candidate portal account:", error);
      setErrorMessage(
        error instanceof Error
          ? error.message
          : "Unable to create the candidate portal account.",
      );
    } finally {
      setPortalActionCandidateId(null);
    }
  }

  async function handleGrantHrPsyconnectAccess(intern) {
    setAccessActionCandidateIds((currentIds) => {
      const nextIds = new Set(currentIds);
      nextIds.add(intern.candidateId);
      return nextIds;
    });
    setActionMessage("");
    setErrorMessage("");

    try {
      const response = await grantHrPsyconnectAccess(intern.candidateId);

      setActionMessage(
        response?.changed === false
          ? "HR Psyconnect access is already active."
          : "HR Psyconnect access granted successfully.",
      );
      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to grant HR Psyconnect access:", error);
      setErrorMessage(
        error instanceof Error && error.message
          ? error.message
          : "Unable to grant HR Psyconnect access.",
      );
    } finally {
      setAccessActionCandidateIds((currentIds) => {
        const nextIds = new Set(currentIds);
        nextIds.delete(intern.candidateId);
        return nextIds;
      });
    }
  }

  async function handleRevokeHrPsyconnectAccess(intern) {
    const confirmed = window.confirm(
      `Revoke HR Psyconnect workspace access for ${intern.fullName}?`,
    );

    if (!confirmed) {
      return;
    }

    setAccessActionCandidateIds((currentIds) => {
      const nextIds = new Set(currentIds);
      nextIds.add(intern.candidateId);
      return nextIds;
    });
    setActionMessage("");
    setErrorMessage("");

    try {
      const response = await revokeHrPsyconnectAccess(intern.candidateId);

      setActionMessage(
        response?.changed === false
          ? "HR Psyconnect access is already inactive."
          : "HR Psyconnect access revoked successfully.",
      );
      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to revoke HR Psyconnect access:", error);
      setErrorMessage(
        error instanceof Error && error.message
          ? error.message
          : "Unable to revoke HR Psyconnect access.",
      );
    } finally {
      setAccessActionCandidateIds((currentIds) => {
        const nextIds = new Set(currentIds);
        nextIds.delete(intern.candidateId);
        return nextIds;
      });
    }
  }

  async function handleConfirmInitiateExit(payload) {
    setIsInitiatingExit(true);
    setActionMessage("");
    setErrorMessage("");

    try {
      await initiateExitForCandidate({
        candidateId: payload.candidateId,
        exitType: payload.exitType,
        exitDate: payload.exitDate,
        notes: payload.notes,
      });

      setActionMessage(
        `Exit process initiated successfully for ${initiateExitCandidate?.fullName || "candidate"}.`,
      );
      setInitiateExitCandidate(null);
      await refreshActiveInterns();
    } catch (error) {
      console.error("Unable to initiate exit process:", error);
      setErrorMessage(
        error instanceof Error
          ? error.message
          : "An exit process has already been initiated for this intern.",
      );
    } finally {
      setIsInitiatingExit(false);
    }
  }

  return (
    <div className="app-page">
      <Link to="/" className="back-link">
        ← Back to Dashboard
      </Link>

      <div className="page-header-modern">
        <div className="page-icon">
          <BriefcaseBusiness size={28} />
        </div>

        <div>
          <h1 className="page-title-modern">Active Interns</h1>
          <p className="page-subtitle">
            Manage active interns, initiate exits, and track signed offer submissions.
          </p>
        </div>
      </div>

      {isLoading && <p>Loading active interns...</p>}

      {errorMessage && (
        <div className="card card-danger" style={{ marginBottom: 16, padding: 12 }}>
          <p className="auth-inline-error" style={{ margin: 0 }}>
            {errorMessage}
          </p>
        </div>
      )}

      {actionMessage && (
        <div className="card card-success" style={{ marginBottom: 16, padding: 12 }}>
          <p style={{ margin: 0, color: "#15803d", fontWeight: 600 }}>
            {actionMessage}
          </p>
        </div>
      )}

      <div className="dashboard-controls">
        <div className="dashboard-controls__group">
          <label htmlFor="interns-search">Search</label>
          <input
            id="interns-search"
            type="search"
            className="form-input"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search name, email or role"
          />
        </div>
        <div className="dashboard-controls__group">
          <label htmlFor="interns-status-filter">Status</label>
          <select
            id="interns-status-filter"
            className="form-select"
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
          >
            {LIFECYCLE_STATUS_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>
        {departmentOptions.length > 0 && (
          <div className="dashboard-controls__group">
            <label htmlFor="interns-dept-filter">Department</label>
            <select
              id="interns-dept-filter"
              className="form-select"
              value={filterDepartment}
              onChange={(e) => setFilterDepartment(e.target.value)}
            >
              <option value="">All Departments</option>
              {departmentOptions.map((dept) => (
                <option key={dept} value={dept}>{dept}</option>
              ))}
            </select>
          </div>
        )}
        <div className="dashboard-controls__group">
          <label htmlFor="interns-sort">Sort By</label>
          <select
            id="interns-sort"
            className="form-select"
            value={sortKey}
            onChange={(e) => setSortKey(e.target.value)}
          >
            {SORT_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>
        {hasActiveControls && (
          <div className="dashboard-controls__reset">
            <button
              type="button"
              className="btn btn-secondary"
              onClick={handleResetControls}
            >
              Reset
            </button>
          </div>
        )}
      </div>

      {!isLoading && displayedInterns.length === 0 && activeInterns.length > 0 && (
        <div className="info-banner" role="status">
          No interns match the current search or filters.
        </div>
      )}

      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Phone</th>
              <th>MID</th>
              <th>Role</th>
              <th>Department</th>
              <th>Team</th>
              <th>Project</th>
              <th>Lifecycle Status</th>
              <th>Offer Status</th>
              <th>Sent At</th>
              <th>Signed Offer Status</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody>
            {displayedInterns.map((intern) => (
              <tr key={intern.id}>
                <td>
                  <button
                    type="button"
                    className="candidate-link"
                    onClick={() => setSelectedCandidateId(intern.candidateId)}
                  >
                    {intern.fullName}
                  </button>
                </td>
                <td>{intern.email}</td>
                <td>{intern.phone}</td>
                <td>
                  <strong>{intern.mid}</strong>
                </td>
                <td>{intern.appliedRole}</td>
                <td>{intern.department}</td>
                <td>{intern.team}</td>
                <td>{intern.project}</td>
                <td>
                  <span className={`badge ${getStatusClass(intern.lifecycleStatus)}`}>
                    {intern.lifecycleStatus ? intern.lifecycleStatus.replaceAll("_", " ") : "—"}
                  </span>
                </td>
                <td>{intern.offerStatus}</td>
                <td>{intern.sentAt}</td>
                <td>{intern.signedOfferStatus}</td>
                <td>
                  <div className="action-group">
                    {intern.lifecycleStatus === "ACTIVE" &&
                      isValidUuid(intern.candidateId) &&
                      !hasActivePortalAccount(intern) && (
                        <button
                          type="button"
                          className="btn btn-primary"
                          disabled={portalActionCandidateId === intern.candidateId}
                          onClick={() => handleCreatePortalAccount(intern)}
                        >
                          {portalActionCandidateId === intern.candidateId
                            ? "Creating Portal..."
                            : "Create Portal Account"}
                        </button>
                      )}

                    {hasActivePortalAccount(intern) && (
                      <span className="badge badge-success">Portal Active</span>
                    )}

                    {isHrPsyconnectIntern(intern) &&
                      !hasActivePortalAccount(intern) && (
                        <span className="badge badge-primary">
                          Portal Required
                        </span>
                      )}

                    {isHrPsyconnectIntern(intern) &&
                      hasActivePortalAccount(intern) &&
                      !intern.hrPsyconnectAccessActive && (
                        <>
                          <span className="badge badge-warning">
                            HR Access Inactive
                          </span>
                          {hasPodManagementAccess && (
                            <button
                              type="button"
                              className="btn btn-primary"
                              disabled={accessActionCandidateIds.has(
                                intern.candidateId,
                              )}
                              onClick={() =>
                                handleGrantHrPsyconnectAccess(intern)
                              }
                            >
                              {accessActionCandidateIds.has(intern.candidateId)
                                ? "Granting Access..."
                                : "Grant HR Psyconnect Access"}
                            </button>
                          )}
                        </>
                      )}

                    {isHrPsyconnectIntern(intern) &&
                      hasActivePortalAccount(intern) &&
                      intern.hrPsyconnectAccessActive && (
                        <>
                          <span
                            className="badge badge-success"
                            title={
                              intern.hrPsyconnectAccessGrantedAt
                                ? `Granted ${new Date(
                                    intern.hrPsyconnectAccessGrantedAt,
                                  ).toLocaleDateString("en-IN")}`
                                : undefined
                            }
                          >
                            HR Access Active
                          </span>
                          {hasPodManagementAccess && (
                            <button
                              type="button"
                              className="btn btn-warning"
                              disabled={accessActionCandidateIds.has(
                                intern.candidateId,
                              )}
                              onClick={() =>
                                handleRevokeHrPsyconnectAccess(intern)
                              }
                            >
                              {accessActionCandidateIds.has(intern.candidateId)
                                ? "Revoking Access..."
                                : "Revoke HR Psyconnect Access"}
                            </button>
                          )}
                        </>
                      )}

                    {intern.lifecycleStatus === "ACTIVE" && (
                      <button
                        type="button"
                        className="btn btn-primary"
                        disabled={actionCandidateId === intern.candidateId}
                        onClick={() => handleMarkSignedOfferSubmitted(intern)}
                      >
                        {actionCandidateId === intern.candidateId
                          ? "Marking..."
                          : "Mark Signed Offer Submitted"}
                      </button>
                    )}

                    {intern.hasActiveExit ? (
                      <button
                        type="button"
                        className="btn btn-secondary"
                        disabled
                        style={{ cursor: "not-allowed", opacity: 0.7 }}
                        title="Exit process has already been initiated for this intern"
                      >
                        Exit In Progress
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="btn btn-warning"
                        onClick={() => setInitiateExitCandidate(intern)}
                      >
                        Initiate Exit
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />

      <InitiateExitModal
        isOpen={Boolean(initiateExitCandidate)}
        intern={initiateExitCandidate}
        onClose={() => setInitiateExitCandidate(null)}
        onConfirm={handleConfirmInitiateExit}
        isSubmitting={isInitiatingExit}
      />
    </div>
  );
}

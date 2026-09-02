import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Info,
  ListChecks,
  LoaderCircle,
  Network,
  Plus,
  Search,
  ShieldCheck,
  UserRoundPlus,
  Users,
  X,
} from "lucide-react";
import { Link } from "react-router-dom";

import CandidateDetailModal from "../components/CandidateDetailModal";
import {
  executePodManagementOperation,
  fetchCandidatesWaitingForPod,
  fetchPodManagementPods,
  fetchPodMemberships,
  searchPodCandidates,
  searchPodHrPsyconnectReviewers,
} from "../services/podManagementService";
import "./PodManagement.css";

const EMPTY_FORM = {
  podCode: "",
  podName: "",
  description: "",
  isActive: true,
  candidateId: "",
  userId: "",
  podId: "",
  leadType: "POD_LEAD",
  effectiveFrom: "",
  membershipId: "",
  effectiveTo: "",
};

const DATE_FORMATTER = new Intl.DateTimeFormat("en-IN", {
  day: "numeric",
  month: "short",
  year: "numeric",
});

function formatDate(value) {
  if (!value) {
    return "Not available";
  }
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? "Not available" : DATE_FORMATTER.format(date);
}

function formatStatus(value, fallback = "Not available") {
  if (!value) {
    return fallback;
  }
  return value
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function getStatusBadgeClass(status) {
  if (status === "ACTIVE" || status === "SUCCESS") {
    return "badge-success";
  }
  if (
    status === "RETRY" ||
    status === "PENDING" ||
    status === "IN_PROBATION"
  ) {
    return "badge-warning";
  }
  return "badge-primary";
}

function getToday() {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function getMemberKind(membership) {
  if (membership.membershipType === "HR_SITE_CONNECT") {
    return "HR Psyconnect reviewer";
  }
  if (membership.membershipType === "CANDIDATE") {
    return "Candidate";
  }
  if (membership.membershipType === "TECH_LEAD") {
    return "Candidate portal user";
  }
  return membership.candidateId ? "Candidate-backed lead" : "Staff-only lead";
}

function getMembershipTypeLabel(membershipType) {
  if (membershipType === "HR_SITE_CONNECT") {
    return "HR Psyconnect reviewer";
  }
  if (membershipType === "TECH_LEAD") {
    return "Project Manager";
  }
  return formatStatus(membershipType);
}

function CandidateButton({ candidateId, name, onOpen }) {
  if (!candidateId) {
    return <strong className="pod-management-member-name">{name}</strong>;
  }
  return (
    <button
      className="candidate-link pod-management-member-name"
      type="button"
      onClick={() => onOpen(candidateId)}
    >
      {name}
    </button>
  );
}

function PodMetricCard({ icon: Icon, title, value, tone }) {
  return (
    <article className={`pod-management-metric pod-management-metric--${tone}`}>
      <div className="pod-management-metric__icon" aria-hidden="true">
        <Icon size={22} />
      </div>
      <div>
        <p className="pod-management-metric__label">{title}</p>
        <p className="pod-management-metric__value">{value}</p>
      </div>
    </article>
  );
}

function PodStatusPanel({ icon: Icon, children, tone = "info", role = "status" }) {
  return (
    <section
      className={`pod-management-status pod-management-status--${tone}`}
      role={role}
      aria-live={role === "alert" ? undefined : "polite"}
    >
      <div className="pod-management-status__icon" aria-hidden="true">
        <Icon size={20} />
      </div>
      <div className="pod-management-status__content">{children}</div>
    </section>
  );
}

export default function PodManagement() {
  const [pods, setPods] = useState([]);
  const [waitingCandidates, setWaitingCandidates] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [memberships, setMemberships] = useState([]);
  const [selectedPodId, setSelectedPodId] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [hasSearchedCandidates, setHasSearchedCandidates] = useState(false);
  const [reviewerSearchTerm, setReviewerSearchTerm] = useState("");
  const [reviewerSearchResults, setReviewerSearchResults] = useState([]);
  const [reviewerSearchLoading, setReviewerSearchLoading] = useState(false);
  const [reviewerSearchError, setReviewerSearchError] = useState("");
  const [hasSearchedReviewers, setHasSearchedReviewers] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [membershipsLoading, setMembershipsLoading] = useState(false);
  const [searchLoading, setSearchLoading] = useState(false);
  const [pageError, setPageError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const [performanceMessage, setPerformanceMessage] = useState("");
  const [modalMode, setModalMode] = useState("");
  const [modalContext, setModalContext] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [modalError, setModalError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [selectedCandidateId, setSelectedCandidateId] = useState(null);
  const inFlightRef = useRef(false);
  const candidateSearchRequestRef = useRef(0);
  const reviewerSearchRequestRef = useRef(0);
  const reviewerSearchInFlightRef = useRef(false);
  const selectedPodDetailsRef = useRef(null);

  const selectedPod = useMemo(
    () => pods.find((pod) => pod.podId === selectedPodId) || null,
    [pods, selectedPodId],
  );

  const currentMemberships = useMemo(
    () => memberships.filter((membership) => membership.isActive),
    [memberships],
  );
  const historicalMemberships = useMemo(
    () => memberships.filter((membership) => !membership.isActive),
    [memberships],
  );

  const currentCandidates = useMemo(
    () => currentMemberships.filter(
      (membership) => membership.membershipType === "CANDIDATE",
    ),
    [currentMemberships],
  );
  const currentPodLeads = useMemo(
    () => currentMemberships.filter(
      (membership) => membership.membershipType === "POD_LEAD",
    ),
    [currentMemberships],
  );
  const currentTechLeads = useMemo(
    () => currentMemberships.filter(
      (membership) => membership.membershipType === "TECH_LEAD",
    ),
    [currentMemberships],
  );
  const currentHrReviewers = useMemo(
    () => currentMemberships.filter(
      (membership) => membership.membershipType === "HR_SITE_CONNECT",
    ),
    [currentMemberships],
  );
  const currentHrReviewer = currentHrReviewers[0] || null;

  const resetReviewerSearchState = useCallback(() => {
    reviewerSearchRequestRef.current += 1;
    reviewerSearchInFlightRef.current = false;
    setReviewerSearchTerm("");
    setReviewerSearchResults([]);
    setReviewerSearchLoading(false);
    setReviewerSearchError("");
    setHasSearchedReviewers(false);
    setForm((current) => ({ ...current, userId: "" }));
  }, []);

  const metrics = useMemo(() => ({
    totalPods: pods.length,
    activePods: pods.filter((pod) => pod.isActive).length,
    waitingCandidates: waitingCandidates.length,
    currentLeads: pods.reduce(
      (total, pod) =>
        total + pod.activePodLeadCount + pod.activeTechLeadCount,
      0,
    ),
  }), [pods, waitingCandidates.length]);

  const loadMemberships = useCallback(async (podId, isActive = () => true) => {
    if (!podId) {
      if (isActive()) {
        setMemberships([]);
      }
      return;
    }
    if (isActive()) {
      setMembershipsLoading(true);
    }
    try {
      const records = await fetchPodMemberships(podId);
      if (isActive()) {
        setMemberships(records);
      }
    } catch (error) {
      if (isActive()) {
        setPageError(error.message);
      }
    } finally {
      if (isActive()) {
        setMembershipsLoading(false);
      }
    }
  }, []);

  const loadWorkspace = useCallback(async (isActive = () => true) => {
    if (isActive()) {
      setIsLoading(true);
      setPageError("");
    }
    try {
      const [nextPods, nextWaiting] = await Promise.all([
        fetchPodManagementPods(),
        fetchCandidatesWaitingForPod(),
      ]);
      if (!isActive()) {
        return;
      }
      setPods(nextPods);
      setWaitingCandidates(nextWaiting);
      setSelectedPodId((current) => {
        if (current && nextPods.some((pod) => pod.podId === current)) {
          return current;
        }
        return nextPods[0]?.podId || "";
      });
    } catch {
      if (isActive()) {
        setPageError("Unable to load Pod Management data.");
      }
    } finally {
      if (isActive()) {
        setIsLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    let mounted = true;
    void Promise.resolve().then(() => loadWorkspace(() => mounted));
    return () => {
      mounted = false;
    };
  }, [loadWorkspace]);

  useEffect(() => {
    let mounted = true;
    void Promise.resolve().then(() =>
      loadMemberships(selectedPodId, () => mounted)
    );
    return () => {
      mounted = false;
    };
  }, [loadMemberships, selectedPodId]);

  useEffect(() => {
    if (!modalMode) {
      return undefined;
    }
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const handleEscape = (event) => {
      if (event.key === "Escape" && !inFlightRef.current) {
        if (modalMode === "assignHrReviewer") {
          resetReviewerSearchState();
        }
        setModalMode("");
        setModalContext(null);
      }
    };
    document.addEventListener("keydown", handleEscape);
    return () => {
      document.removeEventListener("keydown", handleEscape);
      document.body.style.overflow = previousOverflow;
    };
  }, [modalMode, resetReviewerSearchState]);

  const refreshAfterWrite = useCallback(async () => {
    await loadWorkspace();
    if (selectedPodId) {
      await loadMemberships(selectedPodId);
    }
    if (hasSearchedCandidates && searchTerm.trim()) {
      setSearchResults(await searchPodCandidates(searchTerm));
    }
  }, [
    hasSearchedCandidates,
    loadMemberships,
    loadWorkspace,
    searchTerm,
    selectedPodId,
  ]);

  const openModal = (mode, context = null) => {
    const today = getToday();
    if (mode === "assignHrReviewer") {
      resetReviewerSearchState();
    }
    setModalMode(mode);
    setModalContext(context);
    setModalError("");
    setSuccessMessage("");
    setPerformanceMessage("");
    setForm({
      ...EMPTY_FORM,
      podCode: mode === "editPod" ? context.podCode : "",
      podName: mode === "editPod" ? context.podName : "",
      description: mode === "editPod" ? context.description || "" : "",
      isActive: mode === "editPod" ? context.isActive : true,
      candidateId: context?.candidateId || "",
      userId: context?.userId || "",
      podId: context?.podId || selectedPodId || "",
      leadType: context?.leadType || "POD_LEAD",
      effectiveFrom:
        context?.requiredEvaluationStartDate || today,
      membershipId: context?.membershipId || "",
      effectiveTo: today,
    });
  };

  const closeModal = () => {
    if (inFlightRef.current) {
      return;
    }
    if (modalMode === "assignHrReviewer") {
      resetReviewerSearchState();
    }
    setModalMode("");
    setModalContext(null);
    setModalError("");
  };

  const handleViewPod = (podId) => {
    setSelectedPodId(podId);

    window.requestAnimationFrame(() => {
      const detailsSection = selectedPodDetailsRef.current;
      if (!detailsSection) {
        return;
      }

      const prefersReducedMotion = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches;
      detailsSection.focus({ preventScroll: true });
      detailsSection.scrollIntoView({
        behavior: prefersReducedMotion ? "auto" : "smooth",
        block: "start",
      });
    });
  };

  const handleSearch = async (event) => {
    event.preventDefault();
    const normalizedSearchTerm = searchTerm.trim();
    if (!normalizedSearchTerm) {
      candidateSearchRequestRef.current += 1;
      setSearchResults([]);
      setHasSearchedCandidates(false);
      setSearchLoading(false);
      return;
    }

    const requestId = candidateSearchRequestRef.current + 1;
    candidateSearchRequestRef.current = requestId;
    setSearchLoading(true);
    setPageError("");
    try {
      const results = await searchPodCandidates(normalizedSearchTerm);
      if (candidateSearchRequestRef.current === requestId) {
        setSearchResults(results);
        setHasSearchedCandidates(true);
      }
    } catch (error) {
      if (candidateSearchRequestRef.current === requestId) {
        setPageError(error.message);
      }
    } finally {
      if (candidateSearchRequestRef.current === requestId) {
        setSearchLoading(false);
      }
    }
  };

  const handleSearchTermChange = (event) => {
    candidateSearchRequestRef.current += 1;
    setSearchTerm(event.target.value);
    setSearchResults([]);
    setHasSearchedCandidates(false);
    setSearchLoading(false);
  };

  const handleReviewerSearch = async () => {
    if (reviewerSearchInFlightRef.current) {
      return;
    }

    const normalizedSearchTerm = reviewerSearchTerm.trim();
    if (normalizedSearchTerm.length > 150) {
      setReviewerSearchError("HR Psyconnect reviewer search is too long.");
      return;
    }

    const requestId = reviewerSearchRequestRef.current + 1;
    reviewerSearchRequestRef.current = requestId;
    reviewerSearchInFlightRef.current = true;
    setReviewerSearchLoading(true);
    setReviewerSearchError("");
    setReviewerSearchResults([]);
    setHasSearchedReviewers(false);
    setForm((current) => ({ ...current, userId: "" }));

    try {
      const results = await searchPodHrPsyconnectReviewers(
        normalizedSearchTerm,
      );
      if (reviewerSearchRequestRef.current === requestId) {
        setReviewerSearchResults(results);
        setHasSearchedReviewers(true);
      }
    } catch (error) {
      if (reviewerSearchRequestRef.current === requestId) {
        setReviewerSearchError(error.message);
        setHasSearchedReviewers(true);
      }
    } finally {
      if (reviewerSearchRequestRef.current === requestId) {
        reviewerSearchInFlightRef.current = false;
        setReviewerSearchLoading(false);
      }
    }
  };

  const handleReviewerSearchTermChange = (event) => {
    reviewerSearchRequestRef.current += 1;
    reviewerSearchInFlightRef.current = false;
    setReviewerSearchTerm(event.target.value);
    setReviewerSearchResults([]);
    setReviewerSearchLoading(false);
    setReviewerSearchError("");
    setHasSearchedReviewers(false);
    setForm((current) => ({ ...current, userId: "" }));
  };

  const selectedAssignmentCandidate = useMemo(
    () => [...waitingCandidates, ...searchResults].find(
      (candidate) => candidate.candidateId === form.candidateId,
    ) || modalContext,
    [form.candidateId, modalContext, searchResults, waitingCandidates],
  );

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (inFlightRef.current) {
      return;
    }
    if (modalMode === "assignCandidate" || modalMode === "assignLead") {
      if (selectedAssignmentCandidate?.podAssignmentBlockReason === "PROBATION_REJECTED") {
        setModalError(
          "Probation-rejected candidates cannot be assigned to a pod.",
        );
        return;
      }
      if (selectedAssignmentCandidate?.podAssignmentBlockReason === "EXIT_STARTED") {
        setModalError(
          "Candidates with an initiated Exit process cannot be assigned to a pod.",
        );
        return;
      }
    }
    if (modalMode === "assignLead" && form.leadType === "TECH_LEAD") {
      if (modalContext?.appliedRole === "HR Psyconnect Intern") {
        setModalError(
          "HR Psyconnect candidates cannot be assigned as Project Manager.",
        );
        return;
      }
      if (modalContext?.appliedRole !== "Project Manager Intern") {
        setModalError(
          "Only Project Manager Intern (PMT) candidates can be assigned as Project Manager.",
        );
        return;
      }
      if (
        !modalContext?.activePodId ||
        modalContext.activePodId !== form.podId
      ) {
        setModalError(
          "The candidate must already be active in the selected pod before Project Manager assignment.",
        );
        return;
      }
    }
    inFlightRef.current = true;
    setIsSubmitting(true);
    setModalError("");

    try {
      let operation;
      let fields;

      if (modalMode === "createPod") {
        operation = "CREATE_POD";
        fields = {
          podCode: form.podCode.trim().toUpperCase(),
          podName: form.podName.trim(),
          description: form.description.trim() || null,
        };
      } else if (modalMode === "editPod") {
        operation = "UPDATE_POD";
        fields = {
          podId: modalContext.podId,
          podName: form.podName.trim(),
          description: form.description.trim() || null,
          isActive: form.isActive,
        };
      } else if (modalMode === "assignCandidate") {
        operation = "ASSIGN_CANDIDATE";
        fields = {
          candidateId: form.candidateId,
          podId: form.podId,
          effectiveFrom: form.effectiveFrom,
        };
      } else if (modalMode === "assignLead") {
        operation = "ASSIGN_LEAD";
        fields = {
          candidateId: form.candidateId,
          podId: form.podId,
          leadType: form.leadType,
          effectiveFrom: form.effectiveFrom,
        };
      } else if (modalMode === "assignHrReviewer") {
        operation = "ASSIGN_HR_REVIEWER";
        fields = {
          userId: form.userId,
          podId: modalContext.podId,
          effectiveFrom: form.effectiveFrom,
        };
      } else {
        operation = "END_MEMBERSHIP";
        fields = {
          membershipId: form.membershipId,
          effectiveTo: form.effectiveTo,
        };
      }

      const result = await executePodManagementOperation(operation, fields);
      const podOperation = result.podOperation;

      if (operation === "ASSIGN_CANDIDATE") {
        setSuccessMessage("Pod assignment completed successfully.");
        setPerformanceMessage(result.performanceRetry.message);
        setSelectedPodId(podOperation.podId);
      } else if (operation === "ASSIGN_HR_REVIEWER") {
        setSuccessMessage("HR Psyconnect reviewer assigned successfully.");
        setSelectedPodId(podOperation.podId);
      } else {
        setSuccessMessage(
          operation === "CREATE_POD"
            ? "Pod created successfully."
            : operation === "UPDATE_POD"
              ? "Pod updated successfully."
              : operation === "ASSIGN_LEAD"
                ? "Lead assignment completed successfully."
                : "Membership ended successfully.",
        );
        if (podOperation.podId) {
          setSelectedPodId(podOperation.podId);
        }
      }

      setModalMode("");
      setModalContext(null);
      setModalError("");
      if (operation === "ASSIGN_HR_REVIEWER") {
        resetReviewerSearchState();
      }
      await refreshAfterWrite();
    } catch (error) {
      setModalError(error.message);
    } finally {
      inFlightRef.current = false;
      setIsSubmitting(false);
    }
  };

  const lateEffectiveDate =
    modalMode === "assignCandidate" &&
    selectedAssignmentCandidate?.requiredEvaluationStartDate &&
    form.effectiveFrom >
      selectedAssignmentCandidate.requiredEvaluationStartDate;

  const isKnownInvalidProjectManagerAssignment =
    modalMode === "assignLead" &&
    form.leadType === "TECH_LEAD" &&
    (
      modalContext?.appliedRole !== "Project Manager Intern" ||
      !modalContext?.activePodId ||
      modalContext.activePodId !== form.podId
    );

  const isLeadFormInvalid =
    modalMode === "assignLead" &&
    (
      !form.candidateId ||
      !form.podId ||
      !form.effectiveFrom ||
      !["POD_LEAD", "TECH_LEAD"].includes(form.leadType) ||
      Boolean(modalContext?.podAssignmentBlockReason) ||
      isKnownInvalidProjectManagerAssignment
    );

  const isCandidateFormInvalid =
    modalMode === "assignCandidate" &&
    (
      !form.candidateId ||
      !form.podId ||
      !form.effectiveFrom ||
      Boolean(selectedAssignmentCandidate?.podAssignmentBlockReason)
    );

  const renderMembershipRows = (records, allowEnd) => {
    if (records.length === 0) {
      return (
        <div className="pod-management-empty" role="status">
          <Users size={18} aria-hidden="true" />
          <span>No memberships in this section.</span>
        </div>
      );
    }
    return (
      <div className="pod-management-table-wrap">
        <table className="pod-management-table pod-management-table--memberships">
          <thead>
            <tr>
              <th>Member</th>
              <th>Type</th>
              <th>Identity</th>
              <th>Effective From</th>
              <th>Effective To</th>
              <th>Status</th>
              {allowEnd && <th>Action</th>}
            </tr>
          </thead>
          <tbody>
            {records.map((membership) => (
              <tr key={membership.membershipId}>
                <td>
                  <CandidateButton
                    candidateId={membership.candidateId}
                    name={membership.memberName}
                    onOpen={setSelectedCandidateId}
                  />
                  {membership.memberEmail && (
                    <span className="pod-secondary-text">
                      {membership.memberEmail}
                    </span>
                  )}
                </td>
                <td>{getMembershipTypeLabel(membership.membershipType)}</td>
                <td>{getMemberKind(membership)}</td>
                <td>{formatDate(membership.effectiveFrom)}</td>
                <td>{formatDate(membership.effectiveTo)}</td>
                <td>
                  <span
                    className={`badge ${
                      membership.isActive ? "badge-success" : "badge-primary"
                    }`}
                  >
                    {membership.isActive ? "Current" : "Historical"}
                  </span>
                </td>
                {allowEnd && (
                  <td>
                    <button
                      className="btn btn-warning pod-management-table-action"
                      type="button"
                      onClick={() => openModal("endMembership", membership)}
                    >
                      End Membership
                    </button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  };

  return (
    <main className="app-page pod-management-page">
      <Link className="back-link" to="/">
        Back to Dashboard
      </Link>

      <header className="pod-management-hero">
        <div className="pod-management-hero__intro">
          <div className="pod-management-hero__icon" aria-hidden="true">
            <Network size={32} />
          </div>
          <div className="pod-management-hero__content">
            <p className="pod-management-hero__eyebrow">HR Psyconnect Workspace</p>
            <h1>Pod Management</h1>
            <p>
              Manage pods, candidate assignments, lead memberships, and
              performance-assignment follow-up.
            </p>
          </div>
        </div>
        <button
          className="btn btn-primary"
          type="button"
          onClick={() => openModal("createPod")}
        >
          <Plus size={18} aria-hidden="true" />
          Create Pod
        </button>
      </header>

      {pageError && (
        <PodStatusPanel icon={AlertTriangle} tone="error" role="alert">
          <p>{pageError}</p>
          <button
            className="btn btn-primary"
            type="button"
            onClick={() => void loadWorkspace()}
          >
            Retry
          </button>
        </PodStatusPanel>
      )}
      {successMessage && (
        <PodStatusPanel icon={CheckCircle2} tone="success">
          <p>{successMessage}</p>
        </PodStatusPanel>
      )}
      {performanceMessage && (
        <PodStatusPanel icon={Info}>
          <p>
            <strong>Performance assignment:</strong> {performanceMessage}
          </p>
        </PodStatusPanel>
      )}

      {isLoading ? (
        <PodStatusPanel icon={LoaderCircle}>
          <p>Loading Pod Management...</p>
        </PodStatusPanel>
      ) : (
        <>
          <section
            className="pod-management-metrics"
            aria-label="Pod metrics"
          >
            <PodMetricCard
              icon={Network}
              title="Total Pods"
              value={metrics.totalPods}
              tone="blue"
            />
            <PodMetricCard
              icon={ShieldCheck}
              title="Active Pods"
              value={metrics.activePods}
              tone="emerald"
            />
            <PodMetricCard
              icon={AlertTriangle}
              title="Awaiting Pod"
              value={metrics.waitingCandidates}
              tone="amber"
            />
            <PodMetricCard
              icon={Users}
              title="Current Pod Leads / Project Managers"
              value={metrics.currentLeads}
              tone="indigo"
            />
          </section>

          <section className="pod-management-section">
            <div className="pod-management-section__header">
              <div className="pod-management-section__heading">
                <div className="pod-management-section__icon" aria-hidden="true">
                  <Network size={20} />
                </div>
                <div>
                <h2>Pods</h2>
                <p>Select a pod to inspect its current and historical members.</p>
                </div>
              </div>
            </div>
            {pods.length === 0 ? (
              <div className="pod-management-empty" role="status">
                <Network size={18} aria-hidden="true" />
                <span>No pods found.</span>
              </div>
            ) : (
              <div className="pod-management-table-wrap">
                <table className="pod-management-table">
                  <thead>
                    <tr>
                      <th>Code</th>
                      <th>Pod Name</th>
                      <th>Status</th>
                      <th>Candidates</th>
                      <th>Pod Leads</th>
                      <th>Project Managers</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pods.map((pod) => (
                      <tr key={pod.podId}>
                        <td><strong>{pod.podCode}</strong></td>
                        <td>{pod.podName}</td>
                        <td>
                          <span className={`badge ${
                            pod.isActive ? "badge-success" : "badge-primary"
                          }`}>
                            {pod.isActive ? "Active" : "Inactive"}
                          </span>
                        </td>
                        <td>{pod.activeCandidateCount}</td>
                        <td>
                          {pod.currentPodLeads.map((lead) => lead.name).join(", ") ||
                            "None"}
                        </td>
                        <td>
                          {pod.currentTechLeads.map((lead) => lead.name).join(", ") ||
                            "None"}
                        </td>
                        <td>
                          <div className="pod-management-actions pod-management-actions--compact">
                            <button
                              className="btn btn-secondary"
                              type="button"
                              onClick={() => handleViewPod(pod.podId)}
                            >
                              View
                            </button>
                            <button
                              className="btn btn-primary"
                              type="button"
                              onClick={() => openModal("editPod", pod)}
                            >
                              Edit
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="pod-management-section pod-management-section--attention">
            <div className="pod-management-section__header">
              <div className="pod-management-section__heading">
                <div
                  className="pod-management-section__icon pod-management-section__icon--attention"
                  aria-hidden="true"
                >
                  <AlertTriangle size={20} />
                </div>
                <div>
                <h2>Candidates Awaiting Pod</h2>
                <p>Resolve pod-dependent performance assignments without creating new jobs.</p>
                </div>
              </div>
            </div>
            {waitingCandidates.length === 0 ? (
              <div className="pod-management-empty" role="status">
                <CheckCircle2 size={18} aria-hidden="true" />
                <span>No candidates are currently waiting for a pod.</span>
              </div>
            ) : (
              <div className="pod-management-table-wrap">
                <table className="pod-management-table">
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Lifecycle</th>
                      <th>Probation Start</th>
                      <th>Required Membership Date</th>
                      <th>Performance Job</th>
                      <th>Portal</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {waitingCandidates.map((candidate) => (
                      <tr key={candidate.candidateId}>
                        <td>
                          <CandidateButton
                            candidateId={candidate.candidateId}
                            name={candidate.fullName}
                            onOpen={setSelectedCandidateId}
                          />
                          <span className="pod-secondary-text">{candidate.email}</span>
                        </td>
                        <td>{formatStatus(candidate.lifecycleStatus)}</td>
                        <td>{formatDate(candidate.probationStartDate)}</td>
                        <td>{formatDate(candidate.requiredEvaluationStartDate)}</td>
                        <td>
                          <span className={`badge ${getStatusBadgeClass(
                            candidate.performanceJobStatus,
                          )}`}>
                            {formatStatus(candidate.performanceJobStatus, "No job")}
                          </span>
                          {candidate.performanceJobError && (
                            <span className="pod-secondary-text">
                              {candidate.performanceJobError}
                            </span>
                          )}
                        </td>
                        <td>
                          <span className={`badge ${
                            candidate.hasActivePortalAccount
                              ? "badge-success"
                              : "badge-primary"
                          }`}>
                            {candidate.hasActivePortalAccount
                              ? "Portal Active"
                              : "No Active Portal"}
                          </span>
                        </td>
                        <td>
                          <button
                            className="btn btn-primary"
                            type="button"
                            onClick={() => openModal("assignCandidate", candidate)}
                          >
                            Assign Pod
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="pod-management-section pod-management-search-workspace">
            <div className="pod-management-section__header">
              <div className="pod-management-section__heading">
                <div className="pod-management-section__icon" aria-hidden="true">
                  <Search size={20} />
                </div>
                <div>
                <h2>Candidate Search</h2>
                <p>Search by full name, email, or MID.</p>
                </div>
              </div>
            </div>
            <form className="pod-management-search" onSubmit={handleSearch}>
              <div className="pod-management-field">
                <label htmlFor="pod-candidate-search">Candidate search</label>
                <div className="pod-management-search__control">
                  <Search size={19} aria-hidden="true" />
                  <input
                    id="pod-candidate-search"
                    type="search"
                    value={searchTerm}
                    maxLength={150}
                    onChange={handleSearchTermChange}
                    placeholder="Name, email, or MID"
                  />
                </div>
              </div>
              <button className="btn btn-primary" type="submit" disabled={searchLoading}>
                <Search size={18} aria-hidden="true" />
                {searchLoading ? "Searching..." : "Search"}
              </button>
            </form>
            {!hasSearchedCandidates ? (
              <div className="pod-management-empty" role="status">
                <Search size={18} aria-hidden="true" />
                <span>Enter a search term to find candidates.</span>
              </div>
            ) : searchResults.length === 0 ? (
              <div className="pod-management-empty" role="status">
                <Users size={18} aria-hidden="true" />
                <span>No candidates match the search.</span>
              </div>
            ) : (
              <div className="pod-management-table-wrap">
                <table className="pod-management-table pod-management-table--search-results">
                  <thead>
                    <tr>
                      <th>Candidate</th>
                      <th>Role / MID</th>
                      <th>Current Pod</th>
                      <th>Portal</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {searchResults.map((candidate) => {
                      const hasActivePortalAccount =
                        candidate.portalAccountStatus === "ACTIVE";
                      const isHrPsyconnectCandidate =
                        candidate.appliedRole === "HR Psyconnect Intern";
                      const isProjectManagerCandidate =
                        candidate.appliedRole === "Project Manager Intern";
                      const projectManagerEligibilityMessage =
                        isHrPsyconnectCandidate
                          ? "HR Psyconnect candidates cannot be assigned as Project Manager."
                          : !isProjectManagerCandidate
                            ? "Only Project Manager Intern (PMT) candidates can be assigned as Project Manager."
                            : !candidate.activePodId
                              ? "The candidate must already be active in a pod before Project Manager assignment."
                              : "";
                      const podAssignmentEligibilityMessage =
                        candidate.podAssignmentBlockReason === "PROBATION_REJECTED"
                          ? "Probation-rejected candidates cannot be assigned to a pod."
                          : candidate.podAssignmentBlockReason === "EXIT_STARTED"
                            ? "Candidates with an initiated Exit process cannot be assigned to a pod."
                            : "";
                      const leadRequirementId =
                        `lead-portal-requirement-${candidate.candidateId}`;
                      const projectManagerRequirementId =
                        `project-manager-requirement-${candidate.candidateId}`;
                      const podAssignmentRequirementId =
                        `pod-assignment-requirement-${candidate.candidateId}`;

                      return (
                        <tr key={candidate.candidateId}>
                          <td>
                            <CandidateButton
                              candidateId={candidate.candidateId}
                              name={candidate.fullName}
                              onOpen={setSelectedCandidateId}
                            />
                            <span className="pod-secondary-text">
                              {candidate.email}
                            </span>
                          </td>
                          <td>
                            <span className="pod-management-role-name">
                              {candidate.appliedRole || "Not available"}
                            </span>
                            <span className="pod-secondary-text">
                              MID: {candidate.mid || "Not generated"}
                            </span>
                          </td>
                          <td>
                            <span
                              className={
                                candidate.activePodCode
                                  ? undefined
                                  : "pod-management-muted-value"
                              }
                            >
                              {candidate.activePodCode || "Not assigned"}
                            </span>
                          </td>
                          <td>
                            <span className={`badge pod-management-portal-badge ${
                              hasActivePortalAccount
                                ? "badge-success"
                                : "badge-primary"
                            }`}>
                              {formatStatus(
                                candidate.portalAccountStatus,
                                "No Active Portal",
                              )}
                            </span>
                          </td>
                          <td>
                            <div className="pod-management-actions pod-management-candidate-actions">
                              <button
                                className="btn btn-primary"
                                type="button"
                                disabled={Boolean(podAssignmentEligibilityMessage)}
                                aria-describedby={
                                  podAssignmentEligibilityMessage
                                    ? podAssignmentRequirementId
                                    : undefined
                                }
                                title={podAssignmentEligibilityMessage || undefined}
                                onClick={() =>
                                  openModal("assignCandidate", candidate)
                                }
                              >
                                Assign Candidate
                              </button>
                              <button
                                className="btn btn-secondary"
                                type="button"
                                disabled={
                                  !hasActivePortalAccount ||
                                  Boolean(podAssignmentEligibilityMessage)
                                }
                                aria-describedby={
                                  !hasActivePortalAccount
                                    ? leadRequirementId
                                    : podAssignmentEligibilityMessage
                                      ? podAssignmentRequirementId
                                      : undefined
                                }
                                title={
                                  !hasActivePortalAccount
                                    ? "Activate the candidate portal before assigning a lead role."
                                    : podAssignmentEligibilityMessage || undefined
                                }
                                onClick={() => openModal("assignLead", {
                                  ...candidate,
                                  leadType: "POD_LEAD",
                                })}
                              >
                                Assign Pod Lead
                              </button>
                              <button
                                className="btn btn-secondary"
                                type="button"
                                disabled={
                                  !hasActivePortalAccount ||
                                  Boolean(podAssignmentEligibilityMessage) ||
                                  Boolean(projectManagerEligibilityMessage)
                                }
                                aria-describedby={
                                  !hasActivePortalAccount
                                    ? leadRequirementId
                                    : podAssignmentEligibilityMessage
                                      ? podAssignmentRequirementId
                                      : projectManagerEligibilityMessage
                                        ? projectManagerRequirementId
                                        : undefined
                                }
                                title={
                                  !hasActivePortalAccount
                                    ? "Activate the candidate portal before assigning a lead role."
                                    : podAssignmentEligibilityMessage ||
                                      projectManagerEligibilityMessage ||
                                      undefined
                                }
                                onClick={() => openModal("assignLead", {
                                  ...candidate,
                                  podId: candidate.activePodId,
                                  leadType: "TECH_LEAD",
                                })}
                              >
                                Assign Project Manager
                              </button>
                            </div>
                            {(podAssignmentEligibilityMessage ||
                              !hasActivePortalAccount ||
                              (hasActivePortalAccount &&
                                projectManagerEligibilityMessage)) && (
                              <div className="pod-management-requirements">
                                {podAssignmentEligibilityMessage && (
                                  <span
                                    id={podAssignmentRequirementId}
                                    className="pod-management-requirement"
                                  >
                                    <AlertTriangle size={14} aria-hidden="true" />
                                    {podAssignmentEligibilityMessage}
                                  </span>
                                )}
                                {!hasActivePortalAccount && (
                                  <span
                                    id={leadRequirementId}
                                    className="pod-management-requirement"
                                  >
                                    <Info size={14} aria-hidden="true" />
                                    Activate the candidate portal before assigning a
                                    lead role.
                                  </span>
                                )}
                                {hasActivePortalAccount &&
                                  projectManagerEligibilityMessage && (
                                  <span
                                    id={projectManagerRequirementId}
                                    className="pod-management-requirement"
                                  >
                                    <Info size={14} aria-hidden="true" />
                                    {projectManagerEligibilityMessage}
                                  </span>
                                )}
                              </div>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section
            ref={selectedPodDetailsRef}
            className="pod-management-section pod-management-details"
            tabIndex={-1}
            aria-labelledby="selected-pod-details-title"
          >
            <div className="pod-management-section__header pod-management-details__header">
              <div className="pod-management-section__heading">
                <div className="pod-management-section__icon" aria-hidden="true">
                  <ListChecks size={20} />
                </div>
                <div>
                <h2 id="selected-pod-details-title">Selected Pod Details</h2>
                <p>
                  {selectedPod
                    ? `${selectedPod.podCode} — ${selectedPod.podName}`
                    : "Select a pod to inspect memberships."}
                </p>
                </div>
              </div>
              {pods.length > 0 && (
                <div className="pod-management-field pod-management-selector">
                  <label htmlFor="pod-detail-selector">Pod</label>
                  <select
                    id="pod-detail-selector"
                    value={selectedPodId}
                    onChange={(event) => setSelectedPodId(event.target.value)}
                  >
                    {pods.map((pod) => (
                      <option key={pod.podId} value={pod.podId}>
                        {pod.podCode} — {pod.podName}
                      </option>
                    ))}
                  </select>
                </div>
              )}
            </div>

            {membershipsLoading ? (
              <PodStatusPanel icon={LoaderCircle}>
                <p>Loading memberships...</p>
              </PodStatusPanel>
            ) : selectedPod ? (
              <div className="pod-management-membership-groups">
                <section className="pod-management-membership-group">
                  <div className="pod-management-membership-group__header">
                    <h3>HR Psyconnect Reviewer</h3>
                    <span className="pod-management-count-badge">
                      {currentHrReviewer ? 1 : 0}
                    </span>
                  </div>
                  {currentHrReviewer ? (
                    renderMembershipRows([currentHrReviewer], true)
                  ) : (
                    <>
                      <div className="pod-management-empty" role="status">
                        <Users size={18} aria-hidden="true" />
                        <span>
                          No HR Psyconnect reviewer is assigned to this pod.
                        </span>
                      </div>
                      {selectedPod.isActive && (
                        <button
                          className="btn btn-primary"
                          type="button"
                          onClick={() =>
                            openModal("assignHrReviewer", selectedPod)
                          }
                        >
                          Assign HR Psyconnect Reviewer
                        </button>
                      )}
                    </>
                  )}
                </section>
                <section className="pod-management-membership-group">
                  <div className="pod-management-membership-group__header">
                    <h3>Current Candidate Members</h3>
                    <span className="pod-management-count-badge">
                      {currentCandidates.length}
                    </span>
                  </div>
                  {renderMembershipRows(currentCandidates, true)}
                </section>
                <section className="pod-management-membership-group">
                  <div className="pod-management-membership-group__header">
                    <h3>Current Pod Leads</h3>
                    <span className="pod-management-count-badge">
                      {currentPodLeads.length}
                    </span>
                  </div>
                  {renderMembershipRows(currentPodLeads, true)}
                </section>
                <section className="pod-management-membership-group">
                  <div className="pod-management-membership-group__header">
                    <h3>Current Project Managers</h3>
                    <span className="pod-management-count-badge">
                      {currentTechLeads.length}
                    </span>
                  </div>
                  {renderMembershipRows(currentTechLeads, true)}
                </section>
                <section className="pod-management-membership-group pod-management-membership-group--historical">
                  <div className="pod-management-membership-group__header">
                    <h3>Historical Memberships</h3>
                    <span className="pod-management-count-badge">
                      {historicalMemberships.length}
                    </span>
                  </div>
                  {renderMembershipRows(historicalMemberships, false)}
                </section>
              </div>
            ) : (
              <div className="pod-management-empty" role="status">
                <Network size={18} aria-hidden="true" />
                <span>No pod selected.</span>
              </div>
            )}
          </section>
        </>
      )}

      {modalMode && (
        <div
          className="modal-overlay pod-modal-overlay"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) {
              closeModal();
            }
          }}
        >
          <section
            className="pod-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="pod-modal-title"
          >
            <header className="pod-modal-header">
              <div>
                <h2 id="pod-modal-title">
                  {modalMode === "createPod"
                    ? "Create Pod"
                    : modalMode === "editPod"
                      ? "Update Pod"
                      : modalMode === "assignCandidate"
                        ? "Assign Candidate to Pod"
                        : modalMode === "assignLead"
                          ? "Assign Candidate as Lead"
                          : modalMode === "assignHrReviewer"
                            ? "Assign HR Psyconnect Reviewer"
                          : "End Membership"}
                </h2>
                {modalContext?.fullName && <p>{modalContext.fullName}</p>}
                {modalContext?.memberName && <p>{modalContext.memberName}</p>}
              </div>
              <button
                className="modal-close-btn"
                type="button"
                aria-label="Close"
                disabled={isSubmitting}
                onClick={closeModal}
              >
                <X aria-hidden="true" />
              </button>
            </header>

            <form className="pod-modal-form" onSubmit={handleSubmit}>
              {modalMode === "createPod" && (
                <>
                  <div className="form-group">
                    <label htmlFor="pod-code">Pod code</label>
                    <input
                      id="pod-code"
                      value={form.podCode}
                      minLength={3}
                      maxLength={30}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        podCode: event.target.value.toUpperCase(),
                      }))}
                    />
                  </div>
                  <div className="form-group">
                    <label htmlFor="pod-name">Pod name</label>
                    <input
                      id="pod-name"
                      value={form.podName}
                      maxLength={150}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        podName: event.target.value,
                      }))}
                    />
                  </div>
                </>
              )}

              {modalMode === "editPod" && (
                <>
                  <div className="form-group">
                    <label htmlFor="edit-pod-name">Pod name</label>
                    <input
                      id="edit-pod-name"
                      value={form.podName}
                      maxLength={150}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        podName: event.target.value,
                      }))}
                    />
                  </div>
                  <label className="checkbox-row" htmlFor="pod-active">
                    <input
                      id="pod-active"
                      type="checkbox"
                      checked={form.isActive}
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        isActive: event.target.checked,
                      }))}
                    />
                    <span>Pod is active</span>
                  </label>
                  <p className="pod-form-help">
                    A pod cannot be deactivated while current or future active
                    memberships remain.
                  </p>
                </>
              )}

              {(modalMode === "createPod" || modalMode === "editPod") && (
                <div className="form-group">
                  <label htmlFor="pod-description">Description</label>
                  <textarea
                    id="pod-description"
                    value={form.description}
                    rows={4}
                    maxLength={1000}
                    onChange={(event) => setForm((current) => ({
                      ...current,
                      description: event.target.value,
                    }))}
                  />
                </div>
              )}

              {(modalMode === "assignCandidate" || modalMode === "assignLead") && (
                <>
                  <div className="form-group">
                    <label htmlFor="assignment-pod">Pod</label>
                    <select
                      id="assignment-pod"
                      value={form.podId}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        podId: event.target.value,
                      }))}
                    >
                      <option value="">Select pod</option>
                      {pods.filter((pod) => pod.isActive).map((pod) => (
                        <option key={pod.podId} value={pod.podId}>
                          {pod.podCode} — {pod.podName}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="form-group">
                    <label htmlFor="assignment-date">Effective from</label>
                    <input
                      id="assignment-date"
                      type="date"
                      value={form.effectiveFrom}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        effectiveFrom: event.target.value,
                      }))}
                    />
                  </div>
                </>
              )}

              {modalMode === "assignCandidate" && (
                <>
                  {selectedAssignmentCandidate?.requiredEvaluationStartDate && (
                    <p className="pod-form-help">
                      Required performance membership date:{" "}
                      <strong>
                        {formatDate(
                          selectedAssignmentCandidate.requiredEvaluationStartDate,
                        )}
                      </strong>
                    </p>
                  )}
                  {lateEffectiveDate && (
                    <p className="alert-card" role="alert">
                      This membership starts after the required evaluation date.
                      The pod assignment can succeed, but the existing performance
                      job may remain pending.
                    </p>
                  )}
                </>
              )}

              {modalMode === "assignLead" && (
                <>
                  <div className="form-group">
                    <label htmlFor="lead-type">Lead type</label>
                    <select
                      id="lead-type"
                      value={form.leadType}
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        leadType: event.target.value,
                      }))}
                    >
                      <option value="POD_LEAD">Pod Lead</option>
                      <option
                        value="TECH_LEAD"
                        disabled={
                          modalContext?.appliedRole !== "Project Manager Intern" ||
                          !modalContext?.activePodId ||
                          modalContext.activePodId !== form.podId
                        }
                      >
                        Project Manager
                      </option>
                    </select>
                  </div>
                  <div className="info-banner">
                    <UserRoundPlus aria-hidden="true" />
                    <p>
                      Candidate portal access and the Candidate role are
                      preserved. An active portal account is required. Project
                      Managers must already be active candidates in the selected
                      pod, and overlapping Pod Lead and Project Manager
                      assignments in the same pod are blocked.
                    </p>
                  </div>
                </>
              )}

              {modalMode === "assignHrReviewer" && (
                <>
                  <div className="info-banner">
                    <p>
                      <strong>{modalContext.podCode}</strong>
                      <br />
                      {modalContext.podName}
                    </p>
                  </div>

                  <div className="form-group">
                    <label htmlFor="hr-reviewer-search">Reviewer search</label>
                    <div className="pod-search-form">
                      <input
                        id="hr-reviewer-search"
                        type="search"
                        value={reviewerSearchTerm}
                        maxLength={150}
                        placeholder="Search by name or email"
                        onChange={handleReviewerSearchTermChange}
                        onKeyDown={(event) => {
                          if (event.key === "Enter") {
                            event.preventDefault();
                            void handleReviewerSearch();
                          }
                        }}
                      />
                      <button
                        className="btn btn-primary"
                        type="button"
                        disabled={reviewerSearchLoading}
                        onClick={() => void handleReviewerSearch()}
                      >
                        <Search size={18} aria-hidden="true" />
                        {reviewerSearchLoading ? "Searching..." : "Search"}
                      </button>
                    </div>
                  </div>

                  {reviewerSearchLoading && (
                    <p className="info-banner" role="status" aria-live="polite">
                      Searching HR Psyconnect reviewers...
                    </p>
                  )}

                  {reviewerSearchError && (
                    <p className="auth-inline-error" role="alert">
                      {reviewerSearchError}
                    </p>
                  )}

                  {!reviewerSearchLoading &&
                    !reviewerSearchError &&
                    !hasSearchedReviewers && (
                      <p className="info-banner" role="status">
                        Search by name or email, or search with an empty field
                        to view available reviewers.
                      </p>
                    )}

                  {!reviewerSearchLoading &&
                    !reviewerSearchError &&
                    hasSearchedReviewers &&
                    reviewerSearchResults.length === 0 && (
                      <p className="info-banner" role="status">
                        No HR Psyconnect reviewers match the search.
                      </p>
                    )}

                  {reviewerSearchResults.length > 0 && (
                    <fieldset className="pod-reviewer-results">
                      <legend>Select reviewer</legend>
                      {reviewerSearchResults.map((reviewer) => (
                        <label
                          className="checkbox-row"
                          htmlFor={`hr-reviewer-${reviewer.userId}`}
                          key={reviewer.userId}
                        >
                          <input
                            id={`hr-reviewer-${reviewer.userId}`}
                            type="radio"
                            name="hr-reviewer"
                            value={reviewer.userId}
                            checked={form.userId === reviewer.userId}
                            onChange={(event) => setForm((current) => ({
                              ...current,
                              userId: event.target.value,
                            }))}
                          />
                          <span>
                            <strong>{reviewer.fullName}</strong>
                            <span className="pod-secondary-text">
                              {reviewer.email}
                            </span>
                            <span className="pod-secondary-text">
                              {reviewer.activePodCount > 0
                                ? `Assigned to ${reviewer.activePodCount} ${
                                    reviewer.activePodCount === 1
                                      ? "pod"
                                      : "pods"
                                  }: ${reviewer.activePodCodes.join(", ")}`
                                : "Not currently assigned to a pod"}
                            </span>
                          </span>
                        </label>
                      ))}
                    </fieldset>
                  )}

                  <div className="form-group">
                    <label htmlFor="hr-reviewer-effective-from">
                      Effective from
                    </label>
                    <input
                      id="hr-reviewer-effective-from"
                      type="date"
                      value={form.effectiveFrom}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        effectiveFrom: event.target.value,
                      }))}
                    />
                  </div>
                </>
              )}

              {modalMode === "endMembership" && (
                <>
                  <div className="info-banner">
                    <p>
                      <strong>{getMemberKind(modalContext)}</strong>
                      <br />
                      This ends the membership without deleting its history or
                      deactivating a lead role.
                    </p>
                  </div>
                  <div className="form-group">
                    <label htmlFor="membership-end-date">Effective to</label>
                    <input
                      id="membership-end-date"
                      type="date"
                      min={modalContext.effectiveFrom}
                      value={form.effectiveTo}
                      required
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        effectiveTo: event.target.value,
                      }))}
                    />
                  </div>
                </>
              )}

              {modalError && (
                <p className="auth-inline-error" role="alert">{modalError}</p>
              )}

              <div className="action-group pod-modal-actions">
                <button
                  className="btn btn-secondary"
                  type="button"
                  disabled={isSubmitting}
                  onClick={closeModal}
                >
                  Cancel
                </button>
                <button
                  className={
                    modalMode === "endMembership"
                      ? "btn btn-warning"
                      : "btn btn-primary"
                  }
                  type="submit"
                  disabled={
                    isSubmitting ||
                    isCandidateFormInvalid ||
                    isLeadFormInvalid ||
                    (modalMode === "assignHrReviewer" &&
                      (!form.userId ||
                        !form.effectiveFrom ||
                        reviewerSearchLoading))
                  }
                >
                  {isSubmitting
                    ? "Saving..."
                    : modalMode === "assignHrReviewer"
                      ? "Assign Reviewer"
                      : "Confirm"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      <CandidateDetailModal
        candidateId={selectedCandidateId}
        onClose={() => setSelectedCandidateId(null)}
      />
    </main>
  );
}

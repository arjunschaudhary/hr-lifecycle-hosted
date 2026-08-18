/**
 * HRExitEvaluation.jsx
 * HR-facing Exit Evaluations module page & form.
 *
 * - When no exitCaseId is in the URL (/hr-exit-evaluations), renders the Pending HR Exit Evaluations table.
 * - When exitCaseId is specified (/hr-exit-evaluation/:exitCaseId), renders the HR Exit Evaluation Form for that case.
 */

import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, CheckCircle2, Plus, Trash2 } from "lucide-react";

import {
  getHRExitEvaluationData,
  getPendingHRExitCases,
  submitHRExitEvaluation,
} from "../services/hrExitEvaluationService";

import ExitProgressBar from "../components/exit/ExitProgressBar";
import ExitQuestionSection from "../components/exit/ExitQuestionSection";
import ExitQuestionField from "../components/exit/ExitQuestionField";
import ExitFormFooter from "../components/exit/ExitFormFooter";
import ExitLoading from "../components/exit/ExitLoading";
import ExitErrorState from "../components/exit/ExitErrorState";
import HRExitSuccess from "../components/exit/HRExitSuccess";
import ExitConfirmationModal from "../components/exit/ExitConfirmationModal";
import CandidateFeedbackPanel from "../components/exit/CandidateFeedbackPanel";

import {
  EXIT_REASONS,
  HR_EXIT_REASONS,
  HR_PREVENTABLE_OPTIONS,
  RETENTION_ATTEMPT_OPTIONS,
  HR_EXTENSION_OFFER_OPTIONS,
  LEAD_EXTENSION_RECOMMENDATION_OPTIONS,
  REHIRE_ELIGIBILITY_OPTIONS,
  HANDOVER_COMPLETE_OPTIONS,
  HANDOVER_METHOD_OPTIONS,
} from "../constants/exitFormOptions";

const TOTAL_SECTIONS = 5;
const SECTION_TITLES = [
  "Basic Information (Read-Only)",
  "Performance Ratings",
  "Exit Context",
  "Decision Fields",
  "Knowledge Transfer",
];

export default function HRExitEvaluation() {
  const { exitCaseId } = useParams();

  // Mode 1: List View state (when !exitCaseId)
  const [pendingList, setPendingList] = useState([]);
  const [listLoading, setListLoading] = useState(!exitCaseId);
  const [listError, setListError] = useState("");

  // Mode 2: Form View state (when exitCaseId is present)
  const [loading, setLoading] = useState(Boolean(exitCaseId));
  const [error, setError] = useState("");
  const [exitCase, setExitCase] = useState(null);
  const [profile, setProfile] = useState(null);
  const [candidateFeedback, setCandidateFeedback] = useState(null);
  const [reviewer, setReviewer] = useState(null);
  const [staffUsers, setStaffUsers] = useState([]);
  const [existingEvaluation, setExistingEvaluation] = useState(null);

  const [currentSection, setCurrentSection] = useState(1);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Form State
  const [formData, setFormData] = useState({
    // Section B: Ratings
    skillRating: "",
    communicationRating: "",
    ownershipRating: "",
    reliabilityRating: "",
    collaborationRating: "",
    adaptabilityRating: "",
    timelinessRating: "",
    independenceRating: "",

    // Section C: Exit Context
    hrPrimaryReason: "",
    hrOtherReasons: [],
    hrPreventable: "",
    retentionAttempt: "no",
    retentionNotes: "",
    extensionOffer: "",
    leadExtensionRecommendation: "",



    // Section E: Knowledge Transfer
    handoverComplete: "",
    handoverMethod: [],
    handoverGap: "",
    verifiedBy: "",
  });

  const [handoverItems, setHandoverItems] = useState([]);
  const [fieldErrors, setFieldErrors] = useState({});

  // Fetch pending list if no exitCaseId
  useEffect(() => {
    if (exitCaseId) return;

    let isMounted = true;
    async function loadPendingList() {
      try {
        setListLoading(true);
        setListError("");
        const data = await getPendingHRExitCases();
        if (isMounted) {
          setPendingList(data || []);
        }
      } catch (err) {
        if (isMounted) {
          setListError(err.message || "Failed to load pending HR exit evaluations.");
        }
      } finally {
        if (isMounted) setListLoading(false);
      }
    }

    loadPendingList();
    return () => {
      isMounted = false;
    };
  }, [exitCaseId]);

  // Fetch specific exit case data when exitCaseId is provided
  useEffect(() => {
    if (!exitCaseId) return;

    let isMounted = true;

    async function loadFormData() {
      try {
        setLoading(true);
        setError("");
        const data = await getHRExitEvaluationData(exitCaseId);

        if (!isMounted) return;

        if (!data.exitCase) {
          setError("No pending exit case was found for evaluation.");
          return;
        }

        setExitCase(data.exitCase);
        setProfile(data.profile);
        setCandidateFeedback(data.candidateFeedback);
        setExistingEvaluation(data.existingEvaluation);
        setReviewer(data.reviewer);
        setStaffUsers(data.staffUsers || []);

        if (data.reviewer?.id) {
          setFormData((prev) => ({ ...prev, verifiedBy: prev.verifiedBy || data.reviewer.id }));
        }

        if (data.exitCase.alreadySubmitted || data.existingEvaluation) {
          setIsSubmitted(true);
        }
      } catch (err) {
        if (!isMounted) return;
        setError(err.message || "Failed to load HR Exit Evaluation data.");
      } finally {
        if (isMounted) setLoading(false);
      }
    }

    loadFormData();

    return () => {
      isMounted = false;
    };
  }, [exitCaseId]);

  // =========================================================================
  // RENDER MODE 1: MODULE LIST PAGE (When !exitCaseId)
  // =========================================================================
  if (!exitCaseId) {
    if (listLoading) {
      return (
        <div className="app-page">
          <ExitLoading />
        </div>
      );
    }

    if (listError) {
      return (
        <div className="app-page">
          <ExitErrorState message={listError} onRetry={() => window.location.reload()} />
        </div>
      );
    }

    return (
      <div className="app-page" style={{ maxWidth: 1000, margin: "0 auto", paddingBottom: 60 }}>
        <Link to="/" className="back-link" style={{ display: "inline-flex", alignItems: "center", gap: 6, marginBottom: 16 }}>
          <ArrowLeft size={16} /> Back to HR Dashboard
        </Link>

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
          <div>
            <h1 style={{ margin: "0 0 4px 0", fontSize: 24, fontWeight: 700, color: "#0f172a" }}>
              Exit Evaluations Workspace
            </h1>
            <p style={{ margin: 0, color: "#64748b", fontSize: 14 }}>
              Process pending intern exit evaluations and verify candidate exit feedback.
            </p>
          </div>
          <span style={{ fontSize: 14, fontWeight: 600, color: "#475569", background: "#e2e8f0", padding: "6px 14px", borderRadius: 20 }}>
            {pendingList.length} Pending HR {pendingList.length === 1 ? "Evaluation" : "Evaluations"}
          </span>
        </div>

        {/* PENDING EXIT EVALUATIONS TABLE */}
        {pendingList.length === 0 ? (
          <div
            className="card"
            style={{
              padding: 40,
              textAlign: "center",
              color: "#64748b",
              background: "#f8fafc",
              border: "1px solid #e2e8f0",
              borderRadius: 12,
            }}
          >
            <CheckCircle2 size={40} color="#16a34a" style={{ marginBottom: 12 }} />
            <h3 style={{ margin: "0 0 6px 0", color: "#1e293b", fontSize: 18 }}>No Pending HR Exit Evaluations</h3>
            <p style={{ margin: 0, fontSize: 14 }}>
              All candidate exit questionnaires have been processed or none are currently awaiting evaluation.
            </p>
          </div>
        ) : (
          <div className="card" style={{ padding: 0, overflowX: "auto", borderRadius: 12, border: "1px solid #cbd5e1" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, textAlign: "left" }}>
              <thead>
                <tr style={{ background: "#f8fafc", borderBottom: "1px solid #e2e8f0", color: "#475569" }}>
                  <th style={{ padding: "14px 16px" }}>Candidate</th>
                  <th style={{ padding: "14px 16px" }}>MID</th>
                  <th style={{ padding: "14px 16px" }}>Pod</th>
                  <th style={{ padding: "14px 16px" }}>Exit Type</th>
                  <th style={{ padding: "14px 16px" }}>Exit Date</th>
                  <th style={{ padding: "14px 16px" }}>Candidate Form</th>
                  <th style={{ padding: "14px 16px" }}>HR Form</th>
                  <th style={{ padding: "14px 16px", textAlign: "right" }}>Action</th>
                </tr>
              </thead>
              <tbody>
                {pendingList.map((item) => (
                  <tr key={item.exitCaseId} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "14px 16px", fontWeight: 600, color: "#0f172a" }}>
                      {item.candidateName}
                    </td>
                    <td style={{ padding: "14px 16px", color: "#475569" }}>{item.mid}</td>
                    <td style={{ padding: "14px 16px", color: "#475569" }}>{item.podName}</td>
                    <td style={{ padding: "14px 16px" }}>
                      <span
                        style={{
                          padding: "4px 10px",
                          borderRadius: 6,
                          fontSize: 12,
                          fontWeight: 600,
                          background: "#fef3c7",
                          color: "#d97706",
                        }}
                      >
                        {item.exitType}
                      </span>
                    </td>
                    <td style={{ padding: "14px 16px", color: "#475569" }}>{item.exitDate}</td>
                    <td style={{ padding: "14px 16px" }}>
                      <span style={{ padding: "3px 10px", borderRadius: 12, fontSize: 12, fontWeight: 600, background: "#dcfce7", color: "#15803d" }}>
                        Completed
                      </span>
                    </td>
                    <td style={{ padding: "14px 16px" }}>
                      <span style={{ padding: "3px 10px", borderRadius: 12, fontSize: 12, fontWeight: 600, background: "#fef3c7", color: "#b45309" }}>
                        Pending
                      </span>
                    </td>
                    <td style={{ padding: "14px 16px", textAlign: "right" }}>
                      <Link to={`/hr-exit-evaluation/${item.exitCaseId}`}>
                        <button className="btn btn-primary" style={{ padding: "7px 16px", fontSize: 13, fontWeight: 600 }}>
                          Complete HR Evaluation
                        </button>
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    );
  }

  // =========================================================================
  // RENDER MODE 2: FORM PAGE (When exitCaseId is provided)
  // =========================================================================
  const updateField = (fieldName, value) => {
    setFormData((prev) => ({ ...prev, [fieldName]: value }));
    if (fieldErrors[fieldName]) {
      setFieldErrors((prev) => ({ ...prev, [fieldName]: null }));
    }
  };

  const addHandoverItem = () => {
    setHandoverItems((prev) => [
      ...prev,
      {
        taskName: "",
        taskStatus: "COMPLETED",
        nextSteps: "",
        successorName: "",
        repositoryLink: "",
        accessToRevoke: "",
      },
    ]);
  };

  const updateHandoverItem = (index, field, val) => {
    setHandoverItems((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], [field]: val };
      return next;
    });
  };

  const removeHandoverItem = (index) => {
    setHandoverItems((prev) => prev.filter((_, i) => i !== index));
  };

  const validateCurrentSection = () => {
    const errors = {};

    if (currentSection === 2) {
      if (!formData.skillRating) errors.skillRating = "Please select a Skill rating (1-5).";
      if (!formData.communicationRating) errors.communicationRating = "Please select a Communication rating (1-5).";
      if (!formData.ownershipRating) errors.ownershipRating = "Please select an Ownership rating (1-5).";
      if (!formData.reliabilityRating) errors.reliabilityRating = "Please select a Reliability rating (1-5).";
      if (!formData.collaborationRating) errors.collaborationRating = "Please select a Collaboration rating (1-5).";
      if (!formData.adaptabilityRating) errors.adaptabilityRating = "Please select an Adaptability rating (1-5).";
      if (!formData.timelinessRating) errors.timelinessRating = "Please select a Timeliness rating (1-5).";
      if (!formData.independenceRating) errors.independenceRating = "Please select an Independence rating (1-5).";
    } else if (currentSection === 3) {
      if (!formData.hrPrimaryReason) errors.hrPrimaryReason = "Please select primary exit reason.";
      if (formData.retentionAttempt === "yes" && !formData.retentionNotes.trim()) {
        errors.retentionNotes = "Please provide retention notes since retention was attempted.";
      }
    } else if (currentSection === 4) {
      if (!formData.rehireEligibility) errors.rehireEligibility = "Please select Rehire eligibility.";
    }

    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleNext = () => {
    if (validateCurrentSection()) {
      setCurrentSection((prev) => Math.min(prev + 1, TOTAL_SECTIONS));
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  };

  const handlePrev = () => {
    setCurrentSection((prev) => Math.max(prev - 1, 1));
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const handleOpenSubmitModal = () => {
    if (validateCurrentSection()) {
      setIsModalOpen(true);
    }
  };

  const handleConfirmSubmit = async () => {
    setIsModalOpen(false);
    setSubmitting(true);
    setSubmitError("");

    try {
      await submitHRExitEvaluation({
        exitCaseId: exitCase.exitCaseId,
        formData,
        handoverItems,
      });

      setIsSubmitted(true);
    } catch (err) {
      setSubmitError(err.message || "Failed to submit HR evaluation.");
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div className="app-page">
        <ExitLoading />
      </div>
    );
  }

  if (error) {
    return (
      <div className="app-page">
        <ExitErrorState message={error} onRetry={() => window.location.reload()} />
      </div>
    );
  }

  if (isSubmitted) {
    return (
      <div className="app-page">
        {existingEvaluation && (
          <div
            className="card"
            style={{
              maxWidth: 600,
              margin: "20px auto",
              padding: 16,
              background: "#eff6ff",
              border: "1px solid #bfdbfe",
              borderRadius: 8,
              textAlign: "center",
            }}
          >
            <CheckCircle2 size={24} color="#2563eb" style={{ marginBottom: 6 }} />
            <h3 style={{ margin: "0 0 4px 0", color: "#1e40af" }}>HR Evaluation Completed</h3>
            <p style={{ margin: 0, fontSize: 14, color: "#1e3a8a" }}>
              An HR evaluation has already been completed for {profile?.fullName || "this candidate"}. Duplicate submissions are prevented.
            </p>
          </div>
        )}
        <HRExitSuccess />
      </div>
    );
  }

  const durationText = profile?.internshipDurationMonths
    ? `${profile.internshipDurationMonths} Month${profile.internshipDurationMonths === 1 ? "" : "s"}`
    : "—";

  return (
    <div className="app-page" style={{ maxWidth: 900, margin: "0 auto", paddingBottom: 60 }}>
      <Link to="/hr-exit-evaluations" className="back-link" style={{ display: "inline-flex", alignItems: "center", gap: 6, marginBottom: 16 }}>
        <ArrowLeft size={16} /> Back to Exit Evaluations Workspace
      </Link>

      <div style={{ marginBottom: 20 }}>
        <h1 style={{ margin: "0 0 4px 0", fontSize: 24, fontWeight: 700, color: "#0f172a" }}>
          HR Intern Exit Evaluation
        </h1>
        <p style={{ margin: 0, color: "#64748b", fontSize: 14 }}>
          Evaluate departing intern performance, exit context, decision fields, and knowledge transfer verification.
        </p>
      </div>

      {/* Candidate Exit Feedback Reference Panel */}
      <CandidateFeedbackPanel feedback={candidateFeedback} profile={profile}  />

      <ExitProgressBar
        current={currentSection}
        total={TOTAL_SECTIONS}
        sectionLabel={SECTION_TITLES[currentSection - 1]}
      />

      {submitError && (
        <div className="card card-danger" style={{ marginBottom: 20, padding: 16 }} role="alert">
          <p className="auth-inline-error" style={{ margin: 0 }}>
            {submitError}
          </p>
        </div>
      )}

      <form onSubmit={(e) => e.preventDefault()} noValidate className="form-card">
        {/* SECTION 1: BASIC INFORMATION (Auto-Filled Read-Only) */}
        {currentSection === 1 && (
          <ExitQuestionSection id="sec-a-title" title="Section A: Basic Information (Auto-Filled)">
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 16 }}>
              <ExitQuestionField id="field-name" label="Candidate Name" type="readonly" value={profile?.fullName} />
              <ExitQuestionField id="field-mid" label="MID" type="readonly" value={profile?.mid} />
              <ExitQuestionField id="field-dept" label="Department / Pod" type="readonly" value={profile?.department} />
              <ExitQuestionField id="field-start-date" label="Internship Start Date" type="readonly" value={profile?.startDate} />
              <ExitQuestionField id="field-end-date" label="Internship End Date" type="readonly" value={profile?.endDate} />
              <ExitQuestionField id="field-duration" label="Internship Duration" type="readonly" value={durationText} />
              <ExitQuestionField id="field-reviewer-name" label="Reviewer Name" type="readonly" value={reviewer?.name} />
              <ExitQuestionField id="field-reviewer-role" label="Reviewer Role" type="readonly" value={reviewer?.role} />
            </div>
          </ExitQuestionSection>
        )}

        {/* SECTION 2: PERFORMANCE RATINGS */}
        {currentSection === 2 && (
          <ExitQuestionSection id="sec-b-title" title="Section B: Performance Ratings (1–5)">
            <p style={{ marginTop: 0, marginBottom: 20, color: "#64748b", fontSize: 14 }}>
              Rate the intern's overall performance across standard capability dimensions during their tenure.
            </p>

            <ExitQuestionField
              id="field-skill"
              label="Skill Rating"
              type="rating"
              required
              value={formData.skillRating}
              onChange={(val) => updateField("skillRating", val)}
              error={fieldErrors.skillRating}
            />

            <ExitQuestionField
              id="field-comm"
              label="Communication"
              type="rating"
              required
              value={formData.communicationRating}
              onChange={(val) => updateField("communicationRating", val)}
              error={fieldErrors.communicationRating}
            />

            <ExitQuestionField
              id="field-ownership"
              label="Ownership"
              type="rating"
              required
              value={formData.ownershipRating}
              onChange={(val) => updateField("ownershipRating", val)}
              error={fieldErrors.ownershipRating}
            />

            <ExitQuestionField
              id="field-reliability"
              label="Reliability"
              type="rating"
              required
              value={formData.reliabilityRating}
              onChange={(val) => updateField("reliabilityRating", val)}
              error={fieldErrors.reliabilityRating}
            />

            <ExitQuestionField
              id="field-collaboration"
              label="Collaboration"
              type="rating"
              required
              value={formData.collaborationRating}
              onChange={(val) => updateField("collaborationRating", val)}
              error={fieldErrors.collaborationRating}
            />

            <ExitQuestionField
              id="field-adaptability"
              label="Adaptability"
              type="rating"
              required
              value={formData.adaptabilityRating}
              onChange={(val) => updateField("adaptabilityRating", val)}
              error={fieldErrors.adaptabilityRating}
            />

            <ExitQuestionField
              id="field-timeliness"
              label="Timeliness"
              type="rating"
              required
              value={formData.timelinessRating}
              onChange={(val) => updateField("timelinessRating", val)}
              error={fieldErrors.timelinessRating}
            />

            <ExitQuestionField
              id="field-independence"
              label="Independence"
              type="rating"
              required
              value={formData.independenceRating}
              onChange={(val) => updateField("independenceRating", val)}
              error={fieldErrors.independenceRating}
            />
          </ExitQuestionSection>
        )}

        {/* SECTION 3: EXIT CONTEXT */}
        {currentSection === 3 && (
          <ExitQuestionSection id="sec-c-title" title="Section C: Exit Context">
            <ExitQuestionField
              id="field-hr-primary-reason"
              label="Primary Exit Reason"
              type="dropdown"
              required
              options={HR_EXIT_REASONS}
              value={formData.hrPrimaryReason}
              onChange={(val) => updateField("hrPrimaryReason", val)}
              error={fieldErrors.hrPrimaryReason}
            />

            <ExitQuestionField
              id="field-hr-other-reasons"
              label="Other Contributing Factors (Multi Select)"
              type="multiselect"
              options={EXIT_REASONS}
              value={formData.hrOtherReasons}
              onChange={(val) => updateField("hrOtherReasons", val)}
            />

            <ExitQuestionField
              id="field-hr-preventable"
              label="Preventable"
              type="dropdown"
              options={HR_PREVENTABLE_OPTIONS}
              value={formData.hrPreventable}
              onChange={(val) => updateField("hrPreventable", val)}
            />

            <ExitQuestionField
              id="field-retention-attempt"
              label="Retention Attempt"
              type="radio"
              options={RETENTION_ATTEMPT_OPTIONS}
              value={formData.retentionAttempt}
              onChange={(val) => updateField("retentionAttempt", val)}
            />

            {formData.retentionAttempt === "yes" && (
              <ExitQuestionField
                id="field-retention-notes"
                label="Retention Notes"
                type="textarea"
                required
                value={formData.retentionNotes}
                onChange={(val) => updateField("retentionNotes", val)}
                error={fieldErrors.retentionNotes}
              />
            )}

            <ExitQuestionField
              id="field-extension-offer"
              label="Would you offer extension?"
              type="dropdown"
              options={HR_EXTENSION_OFFER_OPTIONS}
              value={formData.extensionOffer}
              onChange={(val) => updateField("extensionOffer", val)}
            />

            <ExitQuestionField
              id="field-lead-extension-rec"
              label="Did reporting lead recommend extension?"
              type="dropdown"
              options={LEAD_EXTENSION_RECOMMENDATION_OPTIONS}
              value={formData.leadExtensionRecommendation}
              onChange={(val) => updateField("leadExtensionRecommendation", val)}
            />
          </ExitQuestionSection>
        )}

        {/* SECTION 4: DECISION FIELDS */}
        {currentSection === 4 && (
          <ExitQuestionSection id="sec-d-title" title="Section D: Decision Fields">

            <ExitQuestionField
              id="field-rehire"
              label="Rehire Eligibility"
              type="dropdown"
              required
              options={REHIRE_ELIGIBILITY_OPTIONS}
              value={formData.rehireEligibility}
              onChange={(val) => updateField("rehireEligibility", val)}
              error={fieldErrors.rehireEligibility}
            />

            <ExitQuestionField
              id="field-internal-notes"
              label="Internal Notes"
              type="textarea"
              hint="Confidential notes for HR record keeping."
              value={formData.internalNotes}
              onChange={(val) => updateField("internalNotes", val)}
            />

            <ExitQuestionField
              id="field-candidate-summary"
              label="Candidate Summary"
              type="textarea"
              hint="Summary of candidate's overall contributions and exit evaluation."
              value={formData.candidateSummary}
              onChange={(val) => updateField("candidateSummary", val)}
            />
          </ExitQuestionSection>
        )}

        {/* SECTION 5: KNOWLEDGE TRANSFER */}
        {currentSection === 5 && (
          <ExitQuestionSection id="sec-e-title" title="Section E: Knowledge Transfer">
            <ExitQuestionField
              id="field-kt-complete"
              label="Knowledge transfer complete?"
              type="dropdown"
              options={HANDOVER_COMPLETE_OPTIONS}
              value={formData.handoverComplete}
              onChange={(val) => updateField("handoverComplete", val)}
            />

            <ExitQuestionField
              id="field-handover-method"
              label="Handover Method (Multi Select)"
              type="multiselect"
              options={HANDOVER_METHOD_OPTIONS}
              value={formData.handoverMethod}
              onChange={(val) => updateField("handoverMethod", val)}
            />

            <ExitQuestionField
              id="field-handover-gap"
              label="Gaps Found"
              type="textarea"
              value={formData.handoverGap}
              onChange={(val) => updateField("handoverGap", val)}
            />

            {staffUsers.length > 0 ? (
              <ExitQuestionField
                id="field-verified-by"
                label="Verified By"
                type="dropdown"
                options={staffUsers}
                value={formData.verifiedBy}
                onChange={(val) => updateField("verifiedBy", val)}
              />
            ) : (
              <ExitQuestionField
                id="field-verified-by-read"
                label="Verified By"
                type="readonly"
                value={reviewer?.name || "HR Evaluator"}
              />
            )}

            {/* Optional Handover Items List */}
            <div style={{ marginTop: 24, paddingTop: 16, borderTop: "1px solid #e2e8f0" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                <h4 style={{ margin: 0, fontSize: 15, fontWeight: 700, color: "#1e293b" }}>
                  Handover Tasks / Items (Optional)
                </h4>
                <button
                  type="button"
                  onClick={addHandoverItem}
                  className="btn btn-secondary"
                  style={{ fontSize: 13, padding: "6px 12px", display: "flex", alignItems: "center", gap: 4 }}
                >
                  <Plus size={14} /> Add Item
                </button>
              </div>

              {handoverItems.length === 0 ? (
                <p style={{ fontSize: 13, color: "#94a3b8", fontStyle: "italic" }}>
                  No specific task handover items added yet. Click "Add Item" to track task transfers.
                </p>
              ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                  {handoverItems.map((item, idx) => (
                    <div
                      key={idx}
                      style={{
                        padding: 14,
                        border: "1px solid #cbd5e1",
                        borderRadius: 8,
                        background: "#f8fafc",
                        position: "relative",
                      }}
                    >
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                        <span style={{ fontSize: 12, fontWeight: 700, color: "#475569" }}>Handover Item #{idx + 1}</span>
                        <button
                          type="button"
                          onClick={() => removeHandoverItem(idx)}
                          style={{ background: "none", border: "none", color: "#dc2626", cursor: "pointer" }}
                        >
                          <Trash2 size={16} />
                        </button>
                      </div>
                      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 10 }}>
                        <ExitQuestionField
                          id={`item-task-${idx}`}
                          label="Task Name"
                          type="text"
                          required
                          value={item.taskName}
                          onChange={(v) => updateHandoverItem(idx, "taskName", v)}
                        />
                        <ExitQuestionField
                          id={`item-successor-${idx}`}
                          label="Successor Name"
                          type="text"
                          value={item.successorName}
                          onChange={(v) => updateHandoverItem(idx, "successorName", v)}
                        />
                        <ExitQuestionField
                          id={`item-next-${idx}`}
                          label="Next Steps"
                          type="text"
                          value={item.nextSteps}
                          onChange={(v) => updateHandoverItem(idx, "nextSteps", v)}
                        />
                        <ExitQuestionField
                          id={`item-repo-${idx}`}
                          label="Repository Link"
                          type="text"
                          value={item.repositoryLink}
                          onChange={(v) => updateHandoverItem(idx, "repositoryLink", v)}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </ExitQuestionSection>
        )}

        <ExitFormFooter
          currentSection={currentSection}
          totalSections={TOTAL_SECTIONS}
          onPrev={handlePrev}
          onNext={handleNext}
          onSubmitClick={handleOpenSubmitModal}
          submitting={submitting}
        />
      </form>

      <ExitConfirmationModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onConfirm={handleConfirmSubmit}
        submitting={submitting}
      />
    </div>
  );
}

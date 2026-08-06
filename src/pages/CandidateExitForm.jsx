/**
 * CandidateExitForm.jsx
 * Candidate-facing Exit Questionnaire Page.
 */

import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Plus, Trash2 } from "lucide-react";

import { useAuth } from "../context/authContext";
import {
  getCandidateExitData,
  submitCandidateExitFeedback,
} from "../services/exitService";

import ExitFormHeader from "../components/exit/ExitFormHeader";
import ExitProgressBar from "../components/exit/ExitProgressBar";
import ExitQuestionSection from "../components/exit/ExitQuestionSection";
import ExitQuestionField from "../components/exit/ExitQuestionField";
import ExitFormFooter from "../components/exit/ExitFormFooter";
import ExitLoading from "../components/exit/ExitLoading";
import ExitErrorState from "../components/exit/ExitErrorState";
import ExitSuccess from "../components/exit/ExitSuccess";
import ExitConfirmationModal from "../components/exit/ExitConfirmationModal";

import {
  EXIT_REASONS,
  PREVENTABLE_OPTIONS,
  EXTENSION_OPTIONS,
  EXTENSION_REASON_OPTIONS,
  EXPECTATION_OPTIONS,
  MEANINGFUL_WORK_OPTIONS,
  MISSING_EXPOSURE_OPTIONS,
  FEEDBACK_FREQUENCY_OPTIONS,
  SAFETY_OPTIONS,
  HR_COMMUNICATION_ISSUES,
  IMPROVEMENT_SUGGESTIONS,
  REJOIN_OPTIONS,
} from "../constants/exitFormOptions";

const TOTAL_SECTIONS = 5;
const SECTION_TITLES = [
  "Basic Information",
  "Learning, Growth & Overall Experience",
  "Mentorship & Team",
  "Final Open Feedback",
  "Knowledge Transfer / Handover",
];

export default function CandidateExitForm() {
  const navigate = useNavigate();
  const { candidateId } = useAuth();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [exitCase, setExitCase] = useState(null);
  const [profile, setProfile] = useState(null);

  const [currentSection, setCurrentSection] = useState(1);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Form State
  const [formData, setFormData] = useState({
    // Basic Info
    completedFullDuration: "",
    primaryExitReason: "",
    otherExitReasons: [],
    otherReasonText: "",
    preventableExit: "",
    wantedExtension: "",
    extensionReason: "",

    // Section A: Learning
    overallExperienceRating: "",
    npsScore: "",
    expectationMatch: "",
    learningRating: "",
    meaningfulWork: "",
    missingExposure: [],
    missingExposureOther: "",

    // Section B: Mentorship & Team
    guidanceRating: "",
    feedbackFrequency: "",
    psychologicalSafetyRating: "",
    valuedContributorRating: "",
    workDistributionRating: "",
    podCultureRating: "",
    safetyIssue: "",
    safetyIssueDetails: "",
    hrCommunicationIssues: [],
    hrCommunicationOther: "",

    // Section F: Final Feedback
    improvementSuggestions: [],
    improvementOther: "",
    rejoinInterest: "",

    // Section G: Knowledge Transfer / Handover
    ongoingTasks: [],
    briefedSomeone: "",
    personName: "",
    transferDocuments: "",
    accessToRevoke: "",
    timeSensitiveNotes: "",
    repositoryLink: "",
  });

  const [fieldErrors, setFieldErrors] = useState({});

  const addOngoingTask = () => {
    setFormData((prev) => ({
      ...prev,
      ongoingTasks: [
        ...prev.ongoingTasks,
        { taskName: "", taskStatus: "IN_PROGRESS", nextSteps: "" },
      ],
    }));
  };

  const updateOngoingTask = (index, field, val) => {
    setFormData((prev) => {
      const nextTasks = [...prev.ongoingTasks];
      nextTasks[index] = { ...nextTasks[index], [field]: val };
      return { ...prev, ongoingTasks: nextTasks };
    });
  };

  const removeOngoingTask = (index) => {
    setFormData((prev) => ({
      ...prev,
      ongoingTasks: prev.ongoingTasks.filter((_, i) => i !== index),
    }));
  };

  useEffect(() => {
    let isMounted = true;

    async function loadData() {
      try {
        setLoading(true);
        setError("");
        const data = await getCandidateExitData();

        if (!isMounted) return;

        if (!data.exitCase) {
          setError("No active exit case was found for your account.");
          return;
        }

        setExitCase(data.exitCase);
        setProfile(data.profile);

        if (data.exitCase.alreadySubmitted || data.exitCase.candidate_form_completed) {
          setIsSubmitted(true);
        }
      } catch (err) {
        if (!isMounted) return;
        setError(err.message || "Failed to load candidate exit questionnaire.");
      } finally {
        if (isMounted) setLoading(false);
      }
    }

    loadData();

    return () => {
      isMounted = false;
    };
  }, []);

  const updateField = (fieldName, value) => {
    setFormData((prev) => ({ ...prev, [fieldName]: value }));
    if (fieldErrors[fieldName]) {
      setFieldErrors((prev) => ({ ...prev, [fieldName]: null }));
    }
  };

  const validateCurrentSection = () => {
    const errors = {};

    if (currentSection === 1) {
      if (!formData.completedFullDuration) {
        errors.completedFullDuration = "Please indicate if you completed your full duration.";
      }
      if (!formData.primaryExitReason) {
        errors.primaryExitReason = "Please select a primary reason for leaving.";
      }
      if (
        (formData.primaryExitReason === "other" || formData.otherExitReasons.includes("other")) &&
        !formData.otherReasonText.trim()
      ) {
        errors.otherReasonText = "Please specify the other reason.";
      }
    } else if (currentSection === 2) {
      if (!formData.overallExperienceRating) {
        errors.overallExperienceRating = "Please rate your overall experience (1-5).";
      }
      if (formData.npsScore === "" || formData.npsScore === null) {
        errors.npsScore = "Please select an NPS score (0-10).";
      }
      if (!formData.learningRating) {
        errors.learningRating = "Please rate how much you learned (1-5).";
      }
      if (formData.missingExposure.includes("other") && !formData.missingExposureOther.trim()) {
        errors.missingExposureOther = "Please specify other exposure desired.";
      }
    } else if (currentSection === 3) {
      if (!formData.guidanceRating) {
        errors.guidanceRating = "Please rate the guidance received (1-5).";
      }
      if (!formData.psychologicalSafetyRating) {
        errors.psychologicalSafetyRating = "Please rate your comfort asking questions (1-5).";
      }
      if (!formData.valuedContributorRating) {
        errors.valuedContributorRating = "Please rate how valued you felt (1-5).";
      }
      if (!formData.workDistributionRating) {
        errors.workDistributionRating = "Please rate work distribution (1-5).";
      }
      if (!formData.podCultureRating) {
        errors.podCultureRating = "Please rate team environment (1-5).";
      }
      if (formData.hrCommunicationIssues.includes("other") && !formData.hrCommunicationOther.trim()) {
        errors.hrCommunicationOther = "Please specify HR communication issue.";
      }
    } else if (currentSection === 4) {
      if (formData.improvementSuggestions.includes("other") && !formData.improvementOther.trim()) {
        errors.improvementOther = "Please specify improvement suggestion.";
      }
    } else if (currentSection === 5) {
      if (formData.briefedSomeone === "yes" && !formData.personName.trim()) {
        errors.personName = "Please specify the person name you briefed.";
      }
      if (
        formData.ongoingTasks.some(
          (t) => t && (!t.taskName || !t.taskName.trim())
        )
      ) {
        errors.ongoingTasks =
          "Please fill out the task name for all added tasks, or remove empty task rows.";
      }
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
      await submitCandidateExitFeedback({
        exitCaseId: exitCase.exit_case_id,
        candidateId: candidateId || exitCase.candidate_id,
        formData,
      });

      setIsSubmitted(true);
    } catch (err) {
      setSubmitError(err.message || "Failed to submit exit feedback.");
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
        <ExitSuccess />
      </div>
    );
  }

  return (
    <div className="app-page">
      <Link to="/portal" className="back-link">
        ← Back to Candidate Portal
      </Link>

      <ExitFormHeader />

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

      <form onSubmit={(e) => e.preventDefault()} noValidate className="form-card" style={{ maxWidth: 800 }}>
        {/* SECTION 1: BASIC INFORMATION */}
        {currentSection === 1 && (
          <ExitQuestionSection id="sec-1-title" title="1. Basic Information">
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 16, marginBottom: 20 }}>
              <ExitQuestionField id="field-name" label="Name" type="readonly" value={profile?.fullName} />
              <ExitQuestionField id="field-email" label="Email" type="readonly" value={profile?.email} />
              <ExitQuestionField id="field-phone" label="Mobile Number" type="readonly" value={profile?.phone} />
              <ExitQuestionField id="field-dept" label="Department / Pod" type="readonly" value={profile?.podName || profile?.department} />
              <ExitQuestionField
                id="field-duration"
                label="Internship Duration"
                type="readonly"
                value={
                  profile?.internshipDurationMonths
                    ? `${profile.internshipDurationMonths} Month${profile.internshipDurationMonths === 1 ? "" : "s"}`
                    : ""
                }
              />
            </div>

            <ExitQuestionField
              id="field-completed"
              label="Did you complete your full originally committed duration?"
              type="radio"
              required
              options={[
                { value: "yes", label: "Yes, completed full term" },
                { value: "no", label: "No, left early" },
              ]}
              value={formData.completedFullDuration}
              onChange={(val) => updateField("completedFullDuration", val)}
              error={fieldErrors.completedFullDuration}
            />

            <ExitQuestionField
              id="field-primary-reason"
              label="Primary reason for leaving"
              type="dropdown"
              required
              options={EXIT_REASONS}
              value={formData.primaryExitReason}
              onChange={(val) => updateField("primaryExitReason", val)}
              error={fieldErrors.primaryExitReason}
            />

            <ExitQuestionField
              id="field-other-reasons"
              label="Any other contributing reasons? (Optional)"
              type="multiselect"
              options={EXIT_REASONS}
              value={formData.otherExitReasons}
              onChange={(val) => updateField("otherExitReasons", val)}
            />

            {(formData.primaryExitReason === "other" || formData.otherExitReasons.includes("other")) && (
              <ExitQuestionField
                id="field-other-reason-text"
                label="If 'Other', please specify"
                type="textarea"
                required
                value={formData.otherReasonText}
                onChange={(val) => updateField("otherReasonText", val)}
                error={fieldErrors.otherReasonText}
              />
            )}

            <ExitQuestionField
              id="field-preventable"
              label="Looking back, could this exit have been prevented by the organization?"
              type="dropdown"
              options={PREVENTABLE_OPTIONS}
              value={formData.preventableExit}
              onChange={(val) => updateField("preventableExit", val)}
            />

            <ExitQuestionField
              id="field-extension"
              label="Would you have liked to extend your internship beyond your original end date, if given the option?"
              type="dropdown"
              options={EXTENSION_OPTIONS}
              value={formData.wantedExtension}
              onChange={(val) => updateField("wantedExtension", val)}
            />

            {(formData.wantedExtension === "yes" || formData.wantedExtension === "offered_declined") && (
              <ExitQuestionField
                id="field-extension-reason"
                label="What would have made you extend? (Optional)"
                type="dropdown"
                options={EXTENSION_REASON_OPTIONS}
                value={formData.extensionReason}
                onChange={(val) => updateField("extensionReason", val)}
              />
            )}
          </ExitQuestionSection>
        )}

        {/* SECTION 2: LEARNING, GROWTH & OVERALL EXPERIENCE */}
        {currentSection === 2 && (
          <ExitQuestionSection id="sec-2-title" title="2. Learning, Growth & Overall Experience">
            <ExitQuestionField
              id="field-overall-rating"
              label="Overall, how would you rate your experience interning with us?"
              type="rating"
              required
              value={formData.overallExperienceRating}
              onChange={(val) => updateField("overallExperienceRating", val)}
              error={fieldErrors.overallExperienceRating}
            />

            <ExitQuestionField
              id="field-nps"
              label="How likely are you to recommend interning here to a friend or peer?"
              type="nps"
              required
              value={formData.npsScore}
              onChange={(val) => updateField("npsScore", val)}
              error={fieldErrors.npsScore}
            />

            <ExitQuestionField
              id="field-expectation"
              label="Did your experience meet your expectations when you joined?"
              type="dropdown"
              options={EXPECTATION_OPTIONS}
              value={formData.expectationMatch}
              onChange={(val) => updateField("expectationMatch", val)}
            />

            <ExitQuestionField
              id="field-learning"
              label="How much did you learn during your time here?"
              type="rating"
              required
              value={formData.learningRating}
              onChange={(val) => updateField("learningRating", val)}
              error={fieldErrors.learningRating}
            />

            <ExitQuestionField
              id="field-meaningful"
              label="Did you get to work on tasks meaningful and relevant to your role/interests?"
              type="dropdown"
              options={MEANINGFUL_WORK_OPTIONS}
              value={formData.meaningfulWork}
              onChange={(val) => updateField("meaningfulWork", val)}
            />

            <ExitQuestionField
              id="field-exposure"
              label="What's one thing you wish you had exposure to but didn't? (Select all that apply)"
              type="multiselect"
              options={MISSING_EXPOSURE_OPTIONS}
              value={formData.missingExposure}
              onChange={(val) => updateField("missingExposure", val)}
            />

            {formData.missingExposure.includes("other") && (
              <ExitQuestionField
                id="field-exposure-other"
                label="Please specify other exposure desired"
                type="textarea"
                required
                value={formData.missingExposureOther}
                onChange={(val) => updateField("missingExposureOther", val)}
                error={fieldErrors.missingExposureOther}
              />
            )}
          </ExitQuestionSection>
        )}

        {/* SECTION 3: MENTORSHIP & TEAM */}
        {currentSection === 3 && (
          <ExitQuestionSection id="sec-3-title" title="3. Mentorship & Team">
            <ExitQuestionField
              id="field-guidance"
              label="Rate the guidance and support you received from your reporting lead during your time here"
              type="rating"
              required
              value={formData.guidanceRating}
              onChange={(val) => updateField("guidanceRating", val)}
              error={fieldErrors.guidanceRating}
            />

            <ExitQuestionField
              id="field-feedback-freq"
              label="Did you receive regular feedback on your work?"
              type="dropdown"
              options={FEEDBACK_FREQUENCY_OPTIONS}
              value={formData.feedbackFrequency}
              onChange={(val) => updateField("feedbackFrequency", val)}
            />

            <ExitQuestionField
              id="field-safety-rating"
              label="Did you feel comfortable raising concerns or asking questions?"
              type="rating"
              required
              value={formData.psychologicalSafetyRating}
              onChange={(val) => updateField("psychologicalSafetyRating", val)}
              error={fieldErrors.psychologicalSafetyRating}
            />

            <ExitQuestionField
              id="field-valued"
              label="Did you feel like a valued contributor, not just 'extra hands'?"
              type="rating"
              required
              value={formData.valuedContributorRating}
              onChange={(val) => updateField("valuedContributorRating", val)}
              error={fieldErrors.valuedContributorRating}
            />

            <ExitQuestionField
              id="field-work-dist"
              label="Was work distributed fairly within your pod?"
              type="rating"
              required
              value={formData.workDistributionRating}
              onChange={(val) => updateField("workDistributionRating", val)}
              error={fieldErrors.workDistributionRating}
            />

            <ExitQuestionField
              id="field-culture"
              label="Rate your overall pod/team environment and culture"
              type="rating"
              required
              value={formData.podCultureRating}
              onChange={(val) => updateField("podCultureRating", val)}
              error={fieldErrors.podCultureRating}
            />

            <ExitQuestionField
              id="field-safety-issue"
              label="Did you experience or observe any behaviour that made you feel unsafe, disrespected, or unfairly treated?"
              type="dropdown"
              options={SAFETY_OPTIONS}
              value={formData.safetyIssue}
              onChange={(val) => updateField("safetyIssue", val)}
            />

            {formData.safetyIssue === "yes" && (
              <ExitQuestionField
                id="field-safety-details"
                label="Confidential details (Optional — kept strictly confidential with HR)"
                type="textarea"
                hint="This information will remain confidential and visible to HR only."
                value={formData.safetyIssueDetails}
                onChange={(val) => updateField("safetyIssueDetails", val)}
              />
            )}

            <ExitQuestionField
              id="field-hr-comm"
              label="Any issues with communication from HR during your time here? (Select all that apply)"
              type="multiselect"
              options={HR_COMMUNICATION_ISSUES}
              value={formData.hrCommunicationIssues}
              onChange={(val) => updateField("hrCommunicationIssues", val)}
            />

            {formData.hrCommunicationIssues.includes("other") && (
              <ExitQuestionField
                id="field-hr-comm-other"
                label="Please specify HR communication issue"
                type="textarea"
                required
                value={formData.hrCommunicationOther}
                onChange={(val) => updateField("hrCommunicationOther", val)}
                error={fieldErrors.hrCommunicationOther}
              />
            )}
          </ExitQuestionSection>
        )}

        {/* SECTION 4: FINAL OPEN FEEDBACK */}
        {currentSection === 4 && (
          <ExitQuestionSection id="sec-4-title" title="4. Final Open Feedback">
            <ExitQuestionField
              id="field-improvements"
              label="What could we improve for future interns/volunteers? (Select all that apply)"
              type="multiselect"
              options={IMPROVEMENT_SUGGESTIONS}
              value={formData.improvementSuggestions}
              onChange={(val) => updateField("improvementSuggestions", val)}
            />

            {formData.improvementSuggestions.includes("other") && (
              <ExitQuestionField
                id="field-improvement-other"
                label="Please specify other areas for improvement"
                type="textarea"
                required
                value={formData.improvementOther}
                onChange={(val) => updateField("improvementOther", val)}
                error={fieldErrors.improvementOther}
              />
            )}

            <ExitQuestionField
              id="field-rejoin"
              label="Would you consider rejoining this organization in the future?"
              type="dropdown"
              options={REJOIN_OPTIONS}
              value={formData.rejoinInterest}
              onChange={(val) => updateField("rejoinInterest", val)}
            />
          </ExitQuestionSection>
        )}

        {/* SECTION 5: KNOWLEDGE TRANSFER / HANDOVER */}
        {currentSection === 5 && (
          <ExitQuestionSection id="sec-5-title" title="5. Knowledge Transfer / Handover">
            {/* 1. Ongoing Tasks / Projects */}
            <div style={{ marginBottom: 24 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                <label style={{ fontWeight: 600, display: "block" }}>
                  1. Ongoing Tasks / Projects
                </label>
                <button
                  type="button"
                  onClick={addOngoingTask}
                  className="btn btn-secondary"
                  style={{ fontSize: 13, padding: "6px 12px", display: "flex", alignItems: "center", gap: 4 }}
                >
                  <Plus size={14} /> Add Task
                </button>
              </div>

              {formData.ongoingTasks.length === 0 ? (
                <p style={{ fontSize: 13, color: "#64748b", fontStyle: "italic", margin: 0 }}>
                  No ongoing tasks added. Click "+ Add Task" to add pending tasks or projects.
                </p>
              ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                  {formData.ongoingTasks.map((task, idx) => (
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
                        <span style={{ fontSize: 12, fontWeight: 700, color: "#475569" }}>Task #{idx + 1}</span>
                        <button
                          type="button"
                          onClick={() => removeOngoingTask(idx)}
                          style={{ background: "none", border: "none", color: "#dc2626", cursor: "pointer" }}
                          aria-label="Remove task"
                        >
                          <Trash2 size={16} />
                        </button>
                      </div>
                      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 10 }}>
                        <ExitQuestionField
                          id={`task-name-${idx}`}
                          label="Task / Project Name"
                          type="text"
                          required
                          value={task.taskName}
                          onChange={(v) => updateOngoingTask(idx, "taskName", v)}
                        />
                        <ExitQuestionField
                          id={`task-status-${idx}`}
                          label="Current Status"
                          type="dropdown"
                          options={[
                            { value: "IN_PROGRESS", label: "In Progress" },
                            { value: "PENDING", label: "Pending" },
                            { value: "HANDED_OVER", label: "Handed Over" },
                            { value: "COMPLETED", label: "Completed" },
                          ]}
                          value={task.taskStatus}
                          onChange={(v) => updateOngoingTask(idx, "taskStatus", v)}
                        />
                        <ExitQuestionField
                          id={`task-next-${idx}`}
                          label="Next Steps"
                          type="text"
                          value={task.nextSteps}
                          onChange={(v) => updateOngoingTask(idx, "nextSteps", v)}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              )}
              {fieldErrors.ongoingTasks && (
                <p role="alert" style={{ margin: "6px 0 0", fontSize: 13, color: "#dc2626" }}>
                  {fieldErrors.ongoingTasks}
                </p>
              )}
            </div>

            {/* 2. Briefed Someone */}
            <ExitQuestionField
              id="field-briefed-someone"
              label="2. Is there a person you've briefed on your pending work?"
              type="radio"
              options={[
                { value: "yes", label: "Yes" },
                { value: "no", label: "No" },
              ]}
              value={formData.briefedSomeone}
              onChange={(val) => updateField("briefedSomeone", val)}
            />

            {formData.briefedSomeone === "yes" && (
              <ExitQuestionField
                id="field-person-name"
                label="Person Name"
                type="text"
                required
                value={formData.personName}
                onChange={(val) => updateField("personName", val)}
                error={fieldErrors.personName}
              />
            )}

            {/* 3. Documents / Files / Credentials */}
            <ExitQuestionField
              id="field-transfer-docs"
              label="3. Any documents, files, or access/credentials that need to be transferred?"
              type="textarea"
              value={formData.transferDocuments}
              onChange={(val) => updateField("transferDocuments", val)}
            />

            {/* 4. Accounts / Access */}
            <ExitQuestionField
              id="field-access-revoke"
              label="4. Any tools/accounts that should be revoked or reassigned?"
              type="textarea"
              value={formData.accessToRevoke}
              onChange={(val) => updateField("accessToRevoke", val)}
            />

            {/* 5. Time Sensitive Items */}
            <ExitQuestionField
              id="field-time-sensitive"
              label="5. Anything time-sensitive needing immediate attention after you leave?"
              type="textarea"
              value={formData.timeSensitiveNotes}
              onChange={(val) => updateField("timeSensitiveNotes", val)}
            />

            {/* 6. Repository / Drive */}
            <ExitQuestionField
              id="field-repo-link"
              label="6. Where can your work/files be found? (GitHub / Drive / Repository Link)"
              type="textarea"
              value={formData.repositoryLink}
              onChange={(val) => updateField("repositoryLink", val)}
            />
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

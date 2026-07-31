/**
 * exitFormOptions.js
 * Centralised option lists for the Candidate Exit Questionnaire.
 * Import from here; never hardcode options inside JSX.
 */

export const EXIT_REASONS = [
  { value: "completed_planned", label: "Completed planned duration" },
  { value: "academic", label: "Academic commitments" },
  { value: "paid_opportunity", label: "Received a paid opportunity elsewhere" },
  { value: "personal_family", label: "Personal or family reasons" },
  { value: "health", label: "Health or wellbeing" },
  { value: "role_mismatch", label: "Role didn't match expectations" },
  { value: "insufficient_learning", label: "Insufficient learning opportunities" },
  { value: "workload", label: "Workload too heavy" },
  { value: "lack_guidance", label: "Lack of guidance or mentorship" },
  { value: "team_culture", label: "Team or pod culture" },
  { value: "communication", label: "Communication problems" },
  { value: "relocation", label: "Relocation" },
  { value: "other", label: "Other" },
];

export const PREVENTABLE_OPTIONS = [
  { value: "definitely_yes", label: "Definitely yes" },
  { value: "probably_yes", label: "Probably yes" },
  { value: "not_sure", label: "Not sure" },
  { value: "probably_not", label: "Probably not" },
  { value: "definitely_not", label: "Definitely not" },
  { value: "not_applicable", label: "Not applicable — I completed my internship" },
];

export const EXTENSION_OPTIONS = [
  { value: "yes", label: "Yes" },
  { value: "no", label: "No" },
  { value: "offered_declined", label: "I was offered an extension and declined" },
  { value: "not_applicable", label: "Not applicable — I was asked to leave" },
];

export const EXTENSION_REASON_OPTIONS = [
  { value: "more_learning", label: "More learning opportunities" },
  { value: "different_responsibilities", label: "Different responsibilities" },
  { value: "different_pod", label: "Different pod" },
  { value: "better_mentoring", label: "Better mentoring" },
  { value: "flexible_workload", label: "More flexible workload" },
  { value: "clearer_growth", label: "Clearer growth path" },
  { value: "other", label: "Other" },
];

export const EXPECTATION_OPTIONS = [
  { value: "much_worse", label: "Much worse" },
  { value: "worse", label: "Worse" },
  { value: "as_expected", label: "As expected" },
  { value: "better", label: "Better" },
  { value: "much_better", label: "Much better" },
];

export const MEANINGFUL_WORK_OPTIONS = [
  { value: "yes_fully", label: "Yes, fully" },
  { value: "partially", label: "Partially" },
  { value: "not_really", label: "Not really" },
];

export const MISSING_EXPOSURE_OPTIONS = [
  { value: "technical_skills", label: "Technical/role-specific skills" },
  { value: "cross_team", label: "Cross-team exposure" },
  { value: "leadership", label: "Leadership opportunities" },
  { value: "client_stakeholder", label: "Client/stakeholder interaction" },
  { value: "strategic", label: "Strategic/decision-making involvement" },
  { value: "other", label: "Other" },
];

export const FEEDBACK_FREQUENCY_OPTIONS = [
  { value: "regularly", label: "Regularly" },
  { value: "occasionally", label: "Occasionally" },
  { value: "rarely", label: "Rarely" },
  { value: "never", label: "Never" },
];

export const SAFETY_OPTIONS = [
  { value: "yes", label: "Yes" },
  { value: "no", label: "No" },
  { value: "prefer_not", label: "Prefer not to answer" },
];

export const HR_COMMUNICATION_ISSUES = [
  { value: "delayed_responses", label: "Delayed responses" },
  { value: "unclear_policies", label: "Unclear policies" },
  { value: "lack_of_updates", label: "Lack of updates on process/status" },
  { value: "no_issues", label: "No issues" },
  { value: "other", label: "Other" },
];

export const IMPROVEMENT_SUGGESTIONS = [
  { value: "mentorship", label: "Mentorship/guidance" },
  { value: "workload", label: "Workload/pacing" },
  { value: "tools", label: "Access to tools/resources" },
  { value: "communication", label: "Communication clarity" },
  { value: "task_relevance", label: "Task relevance to role" },
  { value: "team_culture", label: "Team culture" },
  { value: "recognition", label: "Recognition" },
  { value: "onboarding", label: "Onboarding" },
  { value: "other", label: "Other" },
];

export const REJOIN_OPTIONS = [
  { value: "yes", label: "Yes" },
  { value: "no", label: "No" },
  { value: "maybe", label: "Maybe" },
];

export const RATING_SCALE = [1, 2, 3, 4, 5];
export const NPS_SCALE = Array.from({ length: 11 }, (_, i) => i); // 0-10

export type WelcomeEmailTemplateInput = {
  fullName: string;
  appliedRole: string;
  joiningDate: string | null;
  probationEndDate: string | null;
  internshipDurationMonths: number | null;
  expectedEndDate: string | null;
};

export type WelcomeEmailTemplate = {
  subject: string;
  text: string;
  html: string;
};

const TO_BE_CONFIRMED = "To be confirmed by HR";

function normalizeDisplayText(value: string): string {
  return value.replace(/[\r\n]+/g, " ").trim();
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatDate(value: string | null): string {
  const normalized = value?.trim();

  if (!normalized) {
    return TO_BE_CONFIRMED;
  }

  const match = normalized.match(/^(\d{4})-(\d{2})-(\d{2})/);

  if (!match) {
    return TO_BE_CONFIRMED;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return TO_BE_CONFIRMED;
  }

  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

function formatDuration(months: number | null): string {
  if (months === null || !Number.isInteger(months) || months <= 0) {
    return TO_BE_CONFIRMED;
  }

  return `${months} ${months === 1 ? "month" : "months"}`;
}

export function buildWelcomeEmailTemplate(
  input: WelcomeEmailTemplateInput,
): WelcomeEmailTemplate {
  const fullName = normalizeDisplayText(input.fullName);
  const appliedRole = normalizeDisplayText(input.appliedRole);
  const joiningDate = formatDate(input.joiningDate);
  const probationEndDate = formatDate(input.probationEndDate);
  const internshipDuration = formatDuration(input.internshipDurationMonths);
  const expectedEndDate = formatDate(input.expectedEndDate);

  const text = [
    `Hello ${fullName},`,
    "",
    "Welcome to JCF. We are pleased to have you join our internship program.",
    "",
    `Applied role: ${appliedRole}`,
    `Joining date: ${joiningDate}`,
    `Probation end date: ${probationEndDate}`,
    `Internship duration: ${internshipDuration}`,
    `Expected internship end date: ${expectedEndDate}`,
    "",
    "If you have any questions, please reply to this HR email.",
    "",
    "Regards,",
    "HR Team",
  ].join("\n");

  const html = [
    "<!doctype html>",
    '<html lang="en">',
    "<body>",
    `<p>Hello ${escapeHtml(fullName)},</p>`,
    "<p>Welcome to JCF. We are pleased to have you join our internship program.</p>",
    "<ul>",
    `<li><strong>Applied role:</strong> ${escapeHtml(appliedRole)}</li>`,
    `<li><strong>Joining date:</strong> ${escapeHtml(joiningDate)}</li>`,
    `<li><strong>Probation end date:</strong> ${escapeHtml(probationEndDate)}</li>`,
    `<li><strong>Internship duration:</strong> ${escapeHtml(internshipDuration)}</li>`,
    `<li><strong>Expected internship end date:</strong> ${escapeHtml(expectedEndDate)}</li>`,
    "</ul>",
    "<p>If you have any questions, please reply to this HR email.</p>",
    "<p>Regards,<br>HR Team</p>",
    "</body>",
    "</html>",
  ].join("\n");

  return {
    subject: "Welcome to JCF - Internship Onboarding",
    text,
    html,
  };
}

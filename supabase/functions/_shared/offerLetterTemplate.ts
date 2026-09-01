import type {
  EmailTemplate,
} from "./gmailProvider.ts";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MID_PATTERN = /^JCF-[A-Z0-9]{3}-[A-Z0-9_]{1,2}-[0-9]{5}$/;

export const APPROVED_OFFER_REPLACEMENT_KEYS = [
  "<<TODAY_DATE>>",
  "JCF/INT/2024/ <<MID NO>>",
  "<< CANDIDATE NAME >>",
  "<< CANDIDATE ADDRESS >>",
  "<< CANDIDATE EMAIL >>",
  "<< CANDIDATE PHONE >>",
  "<<POSITION>>",
  "<<Paid/Unpaid>>",
  "<<unpaid/paid>>",
  "<< START DATE >>",
  "<< END DATE >>",
  "<<Months>>",
  "<<ACCEPTANCE_DATE>>",
] as const;

export const UNRESOLVED_OFFER_PLACEHOLDER_TOKENS = [
  "<<TODAY_DATE>>",
  "<<MID NO>>",
  "<< CANDIDATE NAME >>",
  "<< CANDIDATE ADDRESS >>",
  "<< CANDIDATE EMAIL >>",
  "<< CANDIDATE PHONE >>",
  "<<POSITION>>",
  "<<Paid/Unpaid>>",
  "<< START DATE >>",
  "<<Months>>",
  "<< END DATE >>",
  "<<unpaid/paid>>",
  "<<ACCEPTANCE_DATE>>",
] as const;

export type ApprovedOfferReplacementKey =
  typeof APPROVED_OFFER_REPLACEMENT_KEYS[number];

export type OfferPlaceholderValues = Record<
  ApprovedOfferReplacementKey,
  string
>;

export type OfferLetterTemplateInput = {
  fullName: string;
  email: string;
  phone: string | null;
  address: string | null;
  appliedRole: string;
  roleCode: string;
  mid: string;
  offerLetterNumber: string;
  joiningDate: string;
  expectedEndDate: string;
  internshipDurationMonths: number;
  offerDate: string;
};

export type OfferLetterTemplate = {
  googleDocFileName: string;
  pdfFileName: string;
  placeholders: OfferPlaceholderValues;
  email: EmailTemplate;
};

function requiredText(value: string, fieldName: string): string {
  const normalized = typeof value === "string" ? value.trim() : "";

  if (!normalized) {
    throw new Error(`${fieldName} is required.`);
  }

  return normalized;
}

function optionalText(value: string | null): string {
  return typeof value === "string" ? value.trim() : "";
}

function offerDocumentPosition(appliedRole: string): string {
  const normalizedRole = appliedRole.trim();
  const roleWithoutTerminalIntern = normalizedRole
    .replace(/\bIntern$/i, "")
    .trim();

  return roleWithoutTerminalIntern || normalizedRole;
}

function requiredDate(value: string, fieldName: string): string {
  const normalized = requiredText(value, fieldName);

  if (!DATE_PATTERN.test(normalized)) {
    throw new Error(`${fieldName} must be a date-only value.`);
  }

  const parsedDate = new Date(`${normalized}T00:00:00.000Z`);

  if (
    Number.isNaN(parsedDate.getTime()) ||
    parsedDate.toISOString().slice(0, 10) !== normalized
  ) {
    throw new Error(`${fieldName} must be a valid calendar date.`);
  }

  return normalized;
}

function addCalendarMonth(value: string): string {
  const [year, month, day] = value.split("-").map(Number);
  const targetMonthStart = new Date(Date.UTC(year, month, 1));
  const targetYear = targetMonthStart.getUTCFullYear();
  const targetMonth = targetMonthStart.getUTCMonth();
  const targetMonthLastDay = new Date(
    Date.UTC(targetYear, targetMonth + 1, 0),
  ).getUTCDate();
  const targetDate = new Date(
    Date.UTC(targetYear, targetMonth, Math.min(day, targetMonthLastDay)),
  );

  return targetDate.toISOString().slice(0, 10);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function buildOfferLetterTemplate(
  input: OfferLetterTemplateInput,
): OfferLetterTemplate {
  const fullName = requiredText(input.fullName, "Candidate full name");
  const email = requiredText(input.email, "Candidate email");
  const appliedRole = requiredText(input.appliedRole, "Applied role");
  const roleCode = requiredText(input.roleCode, "Role code").toUpperCase();
  const mid = requiredText(input.mid, "MID");
  const offerLetterNumber = requiredText(
    input.offerLetterNumber,
    "Offer letter number",
  );
  const joiningDate = requiredDate(input.joiningDate, "Joining date");
  const expectedEndDate = requiredDate(
    input.expectedEndDate,
    "Expected end date",
  );
  const offerDate = requiredDate(input.offerDate, "Offer date");
  const documentPosition = offerDocumentPosition(appliedRole);
  const signedOfferCopyDeadline = addCalendarMonth(offerDate);

  if (!MID_PATTERN.test(mid)) {
    throw new Error("MID format is invalid.");
  }

  if (offerLetterNumber !== `OL-${mid}`) {
    throw new Error("Offer letter number does not match the MID.");
  }

  if (!/^[A-Z0-9]{3}$/.test(roleCode)) {
    throw new Error("Role code format is invalid.");
  }

  if (
    !Number.isInteger(input.internshipDurationMonths) ||
    input.internshipDurationMonths <= 0
  ) {
    throw new Error("Internship duration is invalid.");
  }

  const duration = input.internshipDurationMonths === 1
    ? "1 month"
    : `${input.internshipDurationMonths} months`;
  const placeholders: OfferPlaceholderValues = {
    "<<TODAY_DATE>>": offerDate,
    "JCF/INT/2024/ <<MID NO>>": mid,
    "<< CANDIDATE NAME >>": fullName,
    "<< CANDIDATE ADDRESS >>": optionalText(input.address),
    "<< CANDIDATE EMAIL >>": email,
    "<< CANDIDATE PHONE >>": optionalText(input.phone),
    "<<POSITION>>": documentPosition,
    "<<Paid/Unpaid>>": "Unpaid",
    "<<unpaid/paid>>": "unpaid",
    "<< START DATE >>": joiningDate,
    "<< END DATE >>": expectedEndDate,
    "<<Months>>": duration,
    "<<ACCEPTANCE_DATE>>": signedOfferCopyDeadline,
  };
  const subject = `Offer Letter - ${appliedRole}`;
  const text = [
    `Dear ${fullName},`,
    "",
    `Please find attached your offer letter for ${appliedRole}.`,
    `Offer Letter Number: ${offerLetterNumber}`,
    `MID: ${mid}`,
    "",
    "Please review the attached PDF and retain it for your records.",
    "",
    "Regards,",
    "JCF HR Team",
  ].join("\n");
  const html = [
    `<p>Dear ${escapeHtml(fullName)},</p>`,
    `<p>Please find attached your offer letter for <strong>${escapeHtml(appliedRole)}</strong>.</p>`,
    `<p>Offer Letter Number: <strong>${escapeHtml(offerLetterNumber)}</strong><br>`,
    `MID: <strong>${escapeHtml(mid)}</strong></p>`,
    "<p>Please review the attached PDF and retain it for your records.</p>",
    "<p>Regards,<br>JCF HR Team</p>",
  ].join("");

  return {
    googleDocFileName: `${offerLetterNumber} - ${fullName}`,
    pdfFileName: `${offerLetterNumber}.pdf`,
    placeholders,
    email: { subject, text, html },
  };
}

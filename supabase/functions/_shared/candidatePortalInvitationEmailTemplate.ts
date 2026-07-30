import type { EmailTemplate } from "./gmailProvider.ts";

export type CandidatePortalInvitationEmailTemplateInput = {
  candidateName: string;
  invitationLink: string;
};

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

function normalizeInvitationLink(value: string): string {
  const normalized = value.trim();
  const url = new URL(normalized);

  if (!["https:", "http:"].includes(url.protocol)) {
    throw new Error("Candidate portal invitation link is invalid.");
  }

  return url.toString();
}

export function buildCandidatePortalInvitationEmailTemplate(
  input: CandidatePortalInvitationEmailTemplateInput,
): EmailTemplate {
  const candidateName = normalizeDisplayText(input.candidateName);
  const invitationLink = normalizeInvitationLink(input.invitationLink);

  if (!candidateName) {
    throw new Error("Candidate name is required for the invitation email.");
  }

  const text = [
    `Hello ${candidateName},`,
    "",
    "Your JCF candidate portal account is ready to be activated.",
    "",
    "Use the secure link below to create your password and activate portal access:",
    invitationLink,
    "",
    "For your security, do not share this link with anyone.",
    "",
    "If you were not expecting this invitation, please contact HR.",
    "",
    "Regards,",
    "HR Team",
  ].join("\n");

  const escapedName = escapeHtml(candidateName);
  const escapedInvitationLink = escapeHtml(invitationLink);
  const html = [
    "<!doctype html>",
    '<html lang="en">',
    "<body>",
    `<p>Hello ${escapedName},</p>`,
    "<p>Your JCF candidate portal account is ready to be activated.</p>",
    "<p>Use the secure button below to create your password and activate portal access.</p>",
    `<p><a href="${escapedInvitationLink}">Continue to account setup</a></p>`,
    "<p><strong>For your security, do not share this link with anyone.</strong></p>",
    "<p>If you were not expecting this invitation, please contact HR.</p>",
    "<p>Regards,<br>HR Team</p>",
    "</body>",
    "</html>",
  ].join("\n");

  return {
    subject: "Activate your JCF candidate portal account",
    text,
    html,
  };
}

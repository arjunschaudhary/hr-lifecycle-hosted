import type { EmailTemplate } from "./gmailProvider.ts";

export type PasswordResetEmailTemplateInput = {
  resetLink: string;
};

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function normalizeResetLink(value: string): string {
  const normalized = value.trim();
  const url = new URL(normalized);

  if (
    !["https:", "http:"].includes(url.protocol) ||
    url.username ||
    url.password
  ) {
    throw new Error("Password reset link is invalid.");
  }

  return url.toString();
}

export function buildPasswordResetEmailTemplate(
  input: PasswordResetEmailTemplateInput,
): EmailTemplate {
  const resetLink = normalizeResetLink(input.resetLink);
  const escapedResetLink = escapeHtml(resetLink);
  const text = [
    "Hello,",
    "",
    "A password reset was requested for your JCF HR Psyconnect account.",
    "",
    "Use the secure link below to reset your password:",
    resetLink,
    "",
    "This link expires and may become invalid after it is used.",
    "",
    "If you did not request this password reset, you can safely ignore this email.",
    "",
    "Regards,",
    "JCF HR Psyconnect Team",
  ].join("\n");
  const html = [
    "<!doctype html>",
    '<html lang="en">',
    "<body>",
    "<p>Hello,</p>",
    "<p>A password reset was requested for your JCF HR Psyconnect account.</p>",
    '<p><a href="' + escapedResetLink + '">Reset Password</a></p>',
    "<p>This link expires and may become invalid after it is used.</p>",
    "<p>If you did not request this password reset, you can safely ignore this email.</p>",
    "<p>Regards,<br>JCF HR Psyconnect Team</p>",
    "</body>",
    "</html>",
  ].join("\n");

  return {
    subject: "Reset your JCF HR Psyconnect password",
    text,
    html,
  };
}

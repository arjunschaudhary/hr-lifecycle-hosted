import type { WelcomeEmailTemplate } from "./welcomeEmailTemplate.ts";

type GmailConfiguration = {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
  senderEmail: string;
  senderName: string;
  replyToEmail?: string;
};

type DeliveryOutcome = "NOT_SENT" | "UNKNOWN";
type ProviderStage = "CONFIGURATION" | "OAUTH" | "GMAIL_SEND";

export class GmailProviderError extends Error {
  constructor(
    readonly stage: ProviderStage,
    readonly deliveryOutcome: DeliveryOutcome,
    readonly retryable: boolean,
    readonly safeFailureMessage: string,
    readonly publicMessage: string,
    readonly httpStatus: number,
  ) {
    super(publicMessage);
    this.name = "GmailProviderError";
  }
}

export function isGmailProviderError(
  error: unknown,
): error is GmailProviderError {
  return error instanceof GmailProviderError;
}

function nonBlank(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function requireEnvironmentValue(name: string): string {
  const value = nonBlank(Deno.env.get(name));

  if (!value) {
    throw new GmailProviderError(
      "CONFIGURATION",
      "NOT_SENT",
      false,
      "Welcome-email provider configuration is incomplete.",
      "Welcome-email delivery is not configured.",
      500,
    );
  }

  return value;
}

function isValidEmailAddress(value: string): boolean {
  return (
    !/[\r\n]/.test(value) &&
    /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value)
  );
}

function validateEmailAddress(
  value: string,
  failureMessage: string,
): string {
  const normalized = value.trim().toLowerCase();

  if (!isValidEmailAddress(normalized)) {
    throw new GmailProviderError(
      "CONFIGURATION",
      "NOT_SENT",
      false,
      failureMessage,
      "Welcome-email delivery is not configured.",
      500,
    );
  }

  return normalized;
}

function getGmailConfiguration(): GmailConfiguration {
  const senderName = requireEnvironmentValue("GMAIL_SENDER_NAME");

  if (/[\r\n]/.test(senderName)) {
    throw new GmailProviderError(
      "CONFIGURATION",
      "NOT_SENT",
      false,
      "Welcome-email sender name is invalid.",
      "Welcome-email delivery is not configured.",
      500,
    );
  }

  const replyToValue = nonBlank(Deno.env.get("GMAIL_REPLY_TO_EMAIL"));

  return {
    clientId: requireEnvironmentValue("GMAIL_OAUTH_CLIENT_ID"),
    clientSecret: requireEnvironmentValue("GMAIL_OAUTH_CLIENT_SECRET"),
    refreshToken: requireEnvironmentValue("GMAIL_OAUTH_REFRESH_TOKEN"),
    senderEmail: validateEmailAddress(
      requireEnvironmentValue("GMAIL_SENDER_EMAIL"),
      "Welcome-email sender address is invalid.",
    ),
    senderName,
    replyToEmail: replyToValue
      ? validateEmailAddress(
        replyToValue,
        "Welcome-email reply-to address is invalid.",
      )
      : undefined,
  };
}

function getRetryableHttpStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

async function requestAccessToken(
  configuration: GmailConfiguration,
): Promise<string> {
  const requestBody = new URLSearchParams({
    client_id: configuration.clientId,
    client_secret: configuration.clientSecret,
    refresh_token: configuration.refreshToken,
    grant_type: "refresh_token",
  });

  let response: Response;

  try {
    response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: requestBody.toString(),
    });
  } catch {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      true,
      "Gmail OAuth request failed before email delivery.",
      "The email provider is temporarily unavailable.",
      502,
    );
  }

  if (!response.ok) {
    const retryable = getRetryableHttpStatus(response.status);

    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      retryable,
      retryable
        ? "Gmail OAuth returned a transient failure before email delivery."
        : "Gmail OAuth credentials or configuration were rejected.",
      retryable
        ? "The email provider is temporarily unavailable."
        : "Welcome-email delivery is not configured.",
      retryable ? 502 : 500,
    );
  }

  let payload: unknown;

  try {
    payload = await response.json();
  } catch {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      false,
      "Gmail OAuth returned an invalid success response.",
      "The email provider returned an invalid response.",
      502,
    );
  }

  if (typeof payload !== "object" || payload === null) {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      false,
      "Gmail OAuth returned an invalid success response.",
      "The email provider returned an invalid response.",
      502,
    );
  }

  const tokenPayload = payload as Record<string, unknown>;
  const accessToken =
    typeof tokenPayload.access_token === "string"
      ? tokenPayload.access_token.trim()
      : "";

  if (!accessToken) {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      false,
      "Gmail OAuth returned no usable access token.",
      "The email provider returned an invalid response.",
      502,
    );
  }

  if (
    tokenPayload.expires_in !== undefined &&
    (
      typeof tokenPayload.expires_in !== "number" ||
      !Number.isFinite(tokenPayload.expires_in) ||
      tokenPayload.expires_in <= 0
    )
  ) {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      false,
      "Gmail OAuth returned an invalid token lifetime.",
      "The email provider returned an invalid response.",
      502,
    );
  }

  if (
    tokenPayload.token_type !== undefined &&
    (
      typeof tokenPayload.token_type !== "string" ||
      tokenPayload.token_type.toLowerCase() !== "bearer"
    )
  ) {
    throw new GmailProviderError(
      "OAUTH",
      "NOT_SENT",
      false,
      "Gmail OAuth returned an unsupported token type.",
      "The email provider returned an invalid response.",
      502,
    );
  }

  return accessToken;
}

function bytesToBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000;
  let binary = "";

  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

function encodeUtf8Base64(value: string): string {
  return bytesToBase64(new TextEncoder().encode(value));
}

function encodeBodyBase64(value: string): string {
  return encodeUtf8Base64(value).match(/.{1,76}/g)?.join("\r\n") ?? "";
}

function encodeHeaderWord(value: string): string {
  return `=?UTF-8?B?${encodeUtf8Base64(value)}?=`;
}

function createMultipartBoundary(): string {
  const randomBytes = new Uint8Array(24);
  crypto.getRandomValues(randomBytes);

  return `=_JCF_${Array.from(
    randomBytes,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("")}`;
}

function normalizeBodyLineEndings(value: string): string {
  return value.replace(/\r\n|\r|\n/g, "\r\n");
}

function createMimeMessage(
  configuration: GmailConfiguration,
  recipientEmail: string,
  template: WelcomeEmailTemplate,
): string {
  const recipient = validateEmailAddress(
    recipientEmail,
    "Welcome-email recipient address is invalid.",
  );

  if (/[\r\n]/.test(template.subject) || !template.subject.trim()) {
    throw new GmailProviderError(
      "CONFIGURATION",
      "NOT_SENT",
      false,
      "Welcome-email subject is invalid.",
      "Welcome-email delivery could not be prepared.",
      500,
    );
  }

  const boundary = createMultipartBoundary();
  const headers = [
    `From: ${encodeHeaderWord(configuration.senderName)} <${configuration.senderEmail}>`,
    `To: ${recipient}`,
    ...(configuration.replyToEmail
      ? [`Reply-To: ${configuration.replyToEmail}`]
      : []),
    `Subject: ${template.subject}`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
  ];
  const plainTextBody = encodeBodyBase64(
    normalizeBodyLineEndings(template.text),
  );
  const htmlBody = encodeBodyBase64(normalizeBodyLineEndings(template.html));

  return [
    ...headers,
    "",
    `--${boundary}`,
    'Content-Type: text/plain; charset="UTF-8"',
    "Content-Transfer-Encoding: base64",
    "",
    plainTextBody,
    `--${boundary}`,
    'Content-Type: text/html; charset="UTF-8"',
    "Content-Transfer-Encoding: base64",
    "",
    htmlBody,
    `--${boundary}--`,
    "",
  ].join("\r\n");
}

function encodeMimeForGmail(mimeMessage: string): string {
  return encodeUtf8Base64(mimeMessage)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}

export async function sendWelcomeEmailWithGmail(
  recipientEmail: string,
  template: WelcomeEmailTemplate,
): Promise<{ messageId: string }> {
  const configuration = getGmailConfiguration();
  const accessToken = await requestAccessToken(configuration);
  const mimeMessage = createMimeMessage(
    configuration,
    recipientEmail,
    template,
  );
  const rawMessage = encodeMimeForGmail(mimeMessage);
  let response: Response;

  try {
    response = await fetch(
      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ raw: rawMessage }),
      },
    );
  } catch {
    throw new GmailProviderError(
      "GMAIL_SEND",
      "UNKNOWN",
      false,
      "Gmail delivery outcome is unknown after a network failure.",
      "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.",
      502,
    );
  }

  if (!response.ok) {
    if ([500, 502, 503, 504].includes(response.status)) {
      throw new GmailProviderError(
        "GMAIL_SEND",
        "UNKNOWN",
        false,
        "Gmail returned a server error with an unknown delivery outcome.",
        "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.",
        502,
      );
    }

    const retryable = response.status === 429;

    throw new GmailProviderError(
      "GMAIL_SEND",
      "NOT_SENT",
      retryable,
      retryable
        ? "Gmail returned a transient non-success response."
        : "Gmail rejected the welcome-email request.",
      retryable
        ? "The email provider is temporarily unavailable."
        : "The email provider rejected the welcome-email request.",
      502,
    );
  }

  let payload: unknown;

  try {
    payload = await response.json();
  } catch {
    throw new GmailProviderError(
      "GMAIL_SEND",
      "UNKNOWN",
      false,
      "Gmail returned an unreadable success response.",
      "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.",
      502,
    );
  }

  const messageId =
    typeof payload === "object" &&
      payload !== null &&
      typeof (payload as Record<string, unknown>).id === "string"
      ? ((payload as Record<string, unknown>).id as string).trim()
      : "";

  if (!messageId) {
    throw new GmailProviderError(
      "GMAIL_SEND",
      "UNKNOWN",
      false,
      "Gmail returned success without a message ID.",
      "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.",
      502,
    );
  }

  return { messageId };
}

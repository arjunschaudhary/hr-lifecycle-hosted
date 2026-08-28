import {
  APPROVED_OFFER_REPLACEMENT_KEYS,
  type OfferPlaceholderValues,
  UNRESOLVED_OFFER_PLACEHOLDER_TOKENS,
} from "./offerLetterTemplate.ts";

import {
  GENERATED_DOCUMENTS_FOLDER_ID,
  type ExitDocumentTemplate,
} from "./exitDocumentTemplates.ts";

const GOOGLE_DOC_MIME_TYPE = "application/vnd.google-apps.document";
const PDF_MIME_TYPE = "application/pdf";
const MAX_PDF_BYTES = 10 * 1024 * 1024;
const FILE_ID_PATTERN = /^[A-Za-z0-9_-]{10,255}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type GoogleWorkspaceConfiguration = {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
  templateFileId: string;
  destinationFolderId: string;
};

type GoogleDriveFile = {
  id: string;
  mimeType: string;
  parents: string[];
  appProperties: Record<string, string>;
};

export type GoogleWorkspaceStage =
  | "CONFIGURATION"
  | "OAUTH"
  | "DRIVE_RESERVE_ID"
  | "DRIVE_LOOKUP"
  | "DRIVE_COPY"
  | "DOCS_REPLACE"
  | "DOCS_VERIFY"
  | "DRIVE_EXPORT"
  | "DRIVE_UPLOAD"
  | "DRIVE_DOWNLOAD";

export class GoogleWorkspaceProviderError extends Error {
  constructor(
    readonly stage: GoogleWorkspaceStage,
    readonly retryable: boolean,
    readonly safeFailureMessage: string,
    readonly publicMessage: string,
    readonly httpStatus: number,
  ) {
    super(publicMessage);
    this.name = "GoogleWorkspaceProviderError";
  }
}

export function isGoogleWorkspaceProviderError(
  error: unknown,
): error is GoogleWorkspaceProviderError {
  return error instanceof GoogleWorkspaceProviderError;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonBlank(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function requireEnvironmentValue(name: string): string {
  const value = nonBlank(Deno.env.get(name));

  if (!value) {
    throw new GoogleWorkspaceProviderError(
      "CONFIGURATION",
      false,
      "Google Workspace provider configuration is incomplete.",
      "Offer-document generation is not configured.",
      500,
    );
  }

  return value;
}

function validateConfiguredFileId(name: string): string {
  const value = requireEnvironmentValue(name);

  if (!FILE_ID_PATTERN.test(value)) {
    throw new GoogleWorkspaceProviderError(
      "CONFIGURATION",
      false,
      `${name} is invalid.`,
      "Offer-document generation is not configured.",
      500,
    );
  }

  return value;
}

function getGoogleWorkspaceConfiguration(): GoogleWorkspaceConfiguration {
  return {
    clientId: requireEnvironmentValue("GMAIL_OAUTH_CLIENT_ID"),
    clientSecret: requireEnvironmentValue("GMAIL_OAUTH_CLIENT_SECRET"),
    refreshToken: requireEnvironmentValue("GMAIL_OAUTH_REFRESH_TOKEN"),
    templateFileId: validateConfiguredFileId(
      "GOOGLE_OFFER_TEMPLATE_FILE_ID",
    ),
    destinationFolderId: validateConfiguredFileId(
      "GOOGLE_OFFER_DRIVE_FOLDER_ID",
    ),
  };
}

function isRetryableHttpStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

function providerFailure(
  stage: GoogleWorkspaceStage,
  status: number,
): GoogleWorkspaceProviderError {
  const retryable = isRetryableHttpStatus(status);
  const accessFailure = status === 401 || status === 403;

  return new GoogleWorkspaceProviderError(
    stage,
    retryable,
    accessFailure
      ? "Google Workspace credentials, scopes, or file access were rejected."
      : retryable
      ? "Google Workspace returned a transient failure."
      : "Google Workspace rejected the offer-document request.",
    accessFailure
      ? "Offer-document generation is not configured correctly."
      : retryable
      ? "Offer-document generation is temporarily unavailable."
      : "Offer-document generation failed.",
    retryable ? 502 : 500,
  );
}

async function requestAccessToken(
  configuration: GoogleWorkspaceConfiguration,
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
    throw new GoogleWorkspaceProviderError(
      "OAUTH",
      true,
      "Google OAuth request failed before document operations.",
      "Google Workspace is temporarily unavailable.",
      502,
    );
  }

  if (!response.ok) {
    throw providerFailure("OAUTH", response.status);
  }

  let payload: unknown;

  try {
    payload = await response.json();
  } catch {
    throw new GoogleWorkspaceProviderError(
      "OAUTH",
      false,
      "Google OAuth returned an unreadable success response.",
      "Google Workspace returned an invalid response.",
      502,
    );
  }

  const accessToken = isRecord(payload) &&
      typeof payload.access_token === "string"
    ? payload.access_token.trim()
    : "";

  if (!accessToken) {
    throw new GoogleWorkspaceProviderError(
      "OAUTH",
      false,
      "Google OAuth returned no usable access token.",
      "Google Workspace returned an invalid response.",
      502,
    );
  }

  return accessToken;
}

function validateFileId(value: string, message: string): string {
  const normalized = value.trim();

  if (!FILE_ID_PATTERN.test(normalized)) {
    throw new GoogleWorkspaceProviderError(
      "CONFIGURATION",
      false,
      message,
      "Offer-document generation could not be prepared.",
      500,
    );
  }

  return normalized;
}

function sanitizeDriveFileName(value: string, fallback: string): string {
  const sanitized = value
    .replace(/[\u0000-\u001f\u007f/\\]/g, "_")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 180);

  return sanitized || fallback;
}

function createBoundary(prefix: string): string {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);

  return `${prefix}_${Array.from(
    bytes,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("")}`;
}

function validatePdfBytes(bytes: Uint8Array): Uint8Array {
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_PDF_BYTES) {
    throw new GoogleWorkspaceProviderError(
      "DRIVE_EXPORT",
      false,
      "Generated offer PDF was empty or exceeded the 10 MiB limit.",
      "The generated offer PDF is invalid.",
      500,
    );
  }

  return bytes;
}

function parseDriveFile(value: unknown): GoogleDriveFile | null {
  if (!isRecord(value) || typeof value.id !== "string") {
    return null;
  }

  const id = value.id.trim();
  const mimeType = typeof value.mimeType === "string"
    ? value.mimeType.trim()
    : "";
  const parents = Array.isArray(value.parents) &&
      value.parents.every((parent) => typeof parent === "string")
    ? value.parents as string[]
    : [];
  const appProperties = isRecord(value.appProperties)
    ? Object.fromEntries(
      Object.entries(value.appProperties).filter(
        (entry): entry is [string, string] => typeof entry[1] === "string",
      ),
    )
    : {};

  return FILE_ID_PATTERN.test(id) && mimeType
    ? { id, mimeType, parents, appProperties }
    : null;
}

function collectGoogleDocumentText(
  value: unknown,
  textParts: string[],
): void {
  if (Array.isArray(value)) {
    value.forEach((entry) => collectGoogleDocumentText(entry, textParts));
    return;
  }

  if (!isRecord(value)) {
    return;
  }

  if (
    isRecord(value.textRun) &&
    typeof value.textRun.content === "string"
  ) {
    textParts.push(value.textRun.content);
  }

  Object.entries(value).forEach(([key, entry]) => {
    if (key !== "textRun") {
      collectGoogleDocumentText(entry, textParts);
    }
  });
}

export class GoogleWorkspaceProvider {
  constructor(
    private readonly configuration: GoogleWorkspaceConfiguration,
    private readonly accessToken: string,
  ) {}

  private async getFile(fileId: string): Promise<GoogleDriveFile | null> {
    const normalizedFileId = validateFileId(
      fileId,
      "Google Drive file ID is invalid.",
    );
    const query = new URLSearchParams({
      fields: "id,mimeType,parents,appProperties",
      supportsAllDrives: "true",
    });
    let response: Response;

    try {
      response = await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(normalizedFileId)}?${query}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        true,
        "Google Drive file lookup failed.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      throw providerFailure("DRIVE_LOOKUP", response.status);
    }

    let payload: unknown;

    try {
      payload = await response.json();
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Google Drive returned an unreadable file response.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    const file = parseDriveFile(payload);

    if (!file || file.id !== normalizedFileId) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Google Drive returned invalid file metadata.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    return file;
  }

  private validateOwnedArtifact(
    file: GoogleDriveFile,
    jobId: string,
    artifactType: "DOC" | "PDF",
    expectedMimeType: string,
  ): void {
    if (
      file.mimeType !== expectedMimeType ||
      !file.parents.includes(this.configuration.destinationFolderId) ||
      file.appProperties.jcfOfferJobId !== jobId ||
      file.appProperties.jcfOfferArtifact !== artifactType
    ) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Stored Google Drive file ID does not identify the expected private offer artifact.",
        "Stored offer-document state is inconsistent.",
        500,
      );
    }
  }

  private async findOwnedOfferDocument(
    jobId: string,
  ): Promise<GoogleDriveFile | null> {
    if (!UUID_PATTERN.test(jobId)) {
      throw new GoogleWorkspaceProviderError(
        "CONFIGURATION",
        false,
        "Offer-letter job ID is invalid for Google Drive recovery.",
        "Offer-document generation could not be prepared.",
        500,
      );
    }

    const query = new URLSearchParams({
      q: `'${this.configuration.destinationFolderId}' in parents and appProperties has { key='jcfOfferJobId' and value='${jobId}' } and appProperties has { key='jcfOfferArtifact' and value='DOC' } and trashed=false`,
      fields: "nextPageToken,files(id,mimeType,parents,appProperties)",
      pageSize: "10",
      spaces: "drive",
      supportsAllDrives: "true",
      includeItemsFromAllDrives: "true",
    });
    let response: Response;

    try {
      response = await fetch(
        `https://www.googleapis.com/drive/v3/files?${query}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        true,
        "Google Drive offer-document recovery lookup failed.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (!response.ok) {
      throw providerFailure("DRIVE_LOOKUP", response.status);
    }

    let payload: unknown;

    try {
      payload = await response.json();
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Google Drive returned an unreadable offer-document search response.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    const rawFiles = isRecord(payload) && Array.isArray(payload.files)
      ? payload.files
      : null;
    const hasAnotherPage = isRecord(payload) &&
      typeof payload.nextPageToken === "string" &&
      payload.nextPageToken.trim() !== "";
    const files = rawFiles?.map(parseDriveFile).filter(
      (file): file is GoogleDriveFile => file !== null,
    );

    if (!files || files.length !== rawFiles?.length) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Google Drive returned invalid offer-document search metadata.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    if (files.length > 1 || hasAnotherPage) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Multiple Google Docs have the same offer-letter job marker.",
        "Stored offer-document state is inconsistent.",
        500,
      );
    }

    const file = files[0] ?? null;

    if (file) {
      this.validateOwnedArtifact(file, jobId, "DOC", GOOGLE_DOC_MIME_TYPE);
    }

    return file;
  }

  private async recoverOfferDocumentAfterUncertainCopy(
    jobId: string,
  ): Promise<GoogleDriveFile | null> {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const file = await this.findOwnedOfferDocument(jobId);

        if (file) {
          return file;
        }
      } catch (error) {
        if (
          !isGoogleWorkspaceProviderError(error) ||
          !error.retryable ||
          attempt === 3
        ) {
          throw error;
        }
      }

      if (attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, attempt * 250));
      }
    }

    return null;
  }

  private async verifyOfferPlaceholdersResolved(
    googleDocFileId: string,
  ): Promise<void> {
    const query = new URLSearchParams({
      includeTabsContent: "true",
    });
    let response: Response;

    try {
      response = await fetch(
        `https://docs.googleapis.com/v1/documents/${encodeURIComponent(googleDocFileId)}?${query}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DOCS_VERIFY",
        true,
        "Google Docs unresolved-placeholder verification failed.",
        "Google Docs is temporarily unavailable.",
        502,
      );
    }

    if (!response.ok) {
      throw providerFailure("DOCS_VERIFY", response.status);
    }

    let payload: unknown;

    try {
      payload = await response.json();
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DOCS_VERIFY",
        false,
        "Google Docs returned an unreadable document verification response.",
        "Google Docs returned an invalid response.",
        502,
      );
    }

    if (!isRecord(payload)) {
      throw new GoogleWorkspaceProviderError(
        "DOCS_VERIFY",
        false,
        "Google Docs returned invalid document verification data.",
        "Google Docs returned an invalid response.",
        502,
      );
    }

    const textParts: string[] = [];
    collectGoogleDocumentText(payload, textParts);

    if (textParts.length === 0) {
      throw new GoogleWorkspaceProviderError(
        "DOCS_VERIFY",
        false,
        "Google Docs returned no readable offer-template text.",
        "The generated offer document could not be verified.",
        500,
      );
    }

    const documentText = textParts.join("");
    const hasUnresolvedPlaceholder =
      UNRESOLVED_OFFER_PLACEHOLDER_TOKENS.some((placeholder) =>
        documentText.includes(placeholder)
      );

    if (hasUnresolvedPlaceholder) {
      throw new GoogleWorkspaceProviderError(
        "DOCS_VERIFY",
        false,
        "Generated offer document still contains an approved unresolved placeholder.",
        "The offer template contains unresolved placeholders.",
        500,
      );
    }
  }

  async reserveBinaryFileId(): Promise<string> {
    const query = new URLSearchParams({
      count: "1",
      space: "drive",
      type: "files",
    });
    let response: Response;

    try {
      response = await fetch(
        `https://www.googleapis.com/drive/v3/files/generateIds?${query}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_RESERVE_ID",
        true,
        "Google Drive file-ID reservation failed.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (!response.ok) {
      throw providerFailure("DRIVE_RESERVE_ID", response.status);
    }

    let payload: unknown;

    try {
      payload = await response.json();
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_RESERVE_ID",
        false,
        "Google Drive returned an unreadable file-ID response.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    const fileId = isRecord(payload) &&
        Array.isArray(payload.ids) &&
        typeof payload.ids[0] === "string"
      ? payload.ids[0].trim()
      : "";

    return validateFileId(
      fileId,
      "Google Drive returned an invalid reserved file ID.",
    );
  }

  async ensureOfferDocument(input: {
    fileId: string | null;
    jobId: string;
    fileName: string;
    placeholders: OfferPlaceholderValues;
  }): Promise<string> {
    let file = input.fileId
      ? await this.getFile(
        validateFileId(
          input.fileId,
          "Stored Google Doc file ID is invalid.",
        ),
      )
      : await this.findOwnedOfferDocument(input.jobId);

    if (input.fileId && !file) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_LOOKUP",
        false,
        "Stored Google Doc file ID was not found.",
        "Stored offer-document state is inconsistent.",
        500,
      );
    }

    if (file) {
      this.validateOwnedArtifact(
        file,
        input.jobId,
        "DOC",
        GOOGLE_DOC_MIME_TYPE,
      );
    }

    if (!file) {
      const query = new URLSearchParams({
        fields: "id,mimeType,parents,appProperties",
        supportsAllDrives: "true",
      });
      let response: Response | null = null;

      try {
        response = await fetch(
          `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(this.configuration.templateFileId)}/copy?${query}`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${this.accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              name: sanitizeDriveFileName(
                input.fileName,
                "JCF Offer Letter",
              ),
              parents: [this.configuration.destinationFolderId],
              appProperties: {
                jcfOfferJobId: input.jobId,
                jcfOfferArtifact: "DOC",
              },
            }),
          },
        );
      } catch {
        file = await this.recoverOfferDocumentAfterUncertainCopy(input.jobId);

        if (!file) {
          throw new GoogleWorkspaceProviderError(
            "DRIVE_COPY",
            true,
            "Google Drive template copy did not return a confirmed result.",
            "Google Drive is temporarily unavailable.",
            502,
          );
        }
      }

      if (response && !response.ok) {
        file = await this.recoverOfferDocumentAfterUncertainCopy(input.jobId);

        if (!file) {
          throw providerFailure("DRIVE_COPY", response.status);
        }
      } else if (response?.ok) {
        let payload: unknown = null;

        try {
          payload = await response.json();
        } catch {
          file = await this.recoverOfferDocumentAfterUncertainCopy(input.jobId);

          if (!file) {
            throw new GoogleWorkspaceProviderError(
              "DRIVE_COPY",
              true,
              "Google Drive template copy returned an unreadable result.",
              "Google Drive returned an invalid response.",
              502,
            );
          }
        }

        if (payload) {
          file = parseDriveFile(payload);
        }
      }
    }

    if (!file) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_COPY",
        true,
        "Google Drive did not confirm the offer-document copy.",
        "Offer-document generation could not be confirmed.",
        502,
      );
    }

    this.validateOwnedArtifact(file, input.jobId, "DOC", GOOGLE_DOC_MIME_TYPE);

    const entries = Object.entries(input.placeholders);
    const approvedReplacementKeys = new Set<string>(
      APPROVED_OFFER_REPLACEMENT_KEYS,
    );

    if (
      entries.length !== APPROVED_OFFER_REPLACEMENT_KEYS.length ||
      entries.some(([placeholder, value]) =>
        !approvedReplacementKeys.has(placeholder) ||
        typeof value !== "string"
      )
    ) {
      throw new GoogleWorkspaceProviderError(
        "DOCS_REPLACE",
        false,
        "Offer placeholder mapping is invalid.",
        "Offer-document generation could not be prepared.",
        500,
      );
    }

    let updateResponse: Response;

    try {
      updateResponse = await fetch(
        `https://docs.googleapis.com/v1/documents/${encodeURIComponent(file.id)}:batchUpdate`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            requests: entries.map(([placeholder, value]) => ({
              replaceAllText: {
                containsText: {
                  text: placeholder,
                  matchCase: true,
                },
                replaceText: value,
              },
            })),
          }),
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DOCS_REPLACE",
        true,
        "Google Docs placeholder replacement failed.",
        "Google Docs is temporarily unavailable.",
        502,
      );
    }

    if (!updateResponse.ok) {
      throw providerFailure("DOCS_REPLACE", updateResponse.status);
    }

    await this.verifyOfferPlaceholdersResolved(file.id);

    return file.id;
  }

  async ensureOfferPdf(input: {
    fileId: string;
    googleDocFileId: string;
    jobId: string;
    fileName: string;
  }): Promise<{ fileId: string; bytes: Uint8Array }> {
    const fileId = validateFileId(
      input.fileId,
      "Reserved Google PDF file ID is invalid.",
    );
    const googleDocFileId = validateFileId(
      input.googleDocFileId,
      "Google Doc file ID is invalid for PDF export.",
    );
    const existingFile = await this.getFile(fileId);

    if (existingFile) {
      this.validateOwnedArtifact(
        existingFile,
        input.jobId,
        "PDF",
        PDF_MIME_TYPE,
      );

      return {
        fileId,
        bytes: await this.downloadPdf(fileId),
      };
    }

    let exportResponse: Response;
    const exportQuery = new URLSearchParams({ mimeType: PDF_MIME_TYPE });

    try {
      exportResponse = await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(googleDocFileId)}/export?${exportQuery}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_EXPORT",
        true,
        "Google Drive PDF export failed.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (!exportResponse.ok) {
      throw providerFailure("DRIVE_EXPORT", exportResponse.status);
    }

    const pdfBytes = validatePdfBytes(
      new Uint8Array(await exportResponse.arrayBuffer()),
    );
    const boundary = createBoundary("JCF_OFFER_PDF");
    const metadata = JSON.stringify({
      id: fileId,
      name: sanitizeDriveFileName(input.fileName, "JCF-Offer-Letter.pdf"),
      mimeType: PDF_MIME_TYPE,
      parents: [this.configuration.destinationFolderId],
      appProperties: {
        jcfOfferJobId: input.jobId,
        jcfOfferArtifact: "PDF",
      },
    });
    const prefix = new TextEncoder().encode(
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n--${boundary}\r\nContent-Type: ${PDF_MIME_TYPE}\r\n\r\n`,
    );
    const suffix = new TextEncoder().encode(`\r\n--${boundary}--\r\n`);
    let uploadResponse: Response;

    try {
      uploadResponse = await fetch(
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,mimeType,parents,appProperties&supportsAllDrives=true",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": `multipart/related; boundary=${boundary}`,
          },
          body: new Blob([prefix, pdfBytes, suffix]),
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_UPLOAD",
        true,
        "Google Drive PDF upload did not return a confirmed result for a reserved file ID.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (!uploadResponse.ok) {
      if (uploadResponse.status === 409) {
        const concurrentFile = await this.getFile(fileId);

        if (concurrentFile) {
          this.validateOwnedArtifact(
            concurrentFile,
            input.jobId,
            "PDF",
            PDF_MIME_TYPE,
          );

          return {
            fileId,
            bytes: await this.downloadPdf(fileId),
          };
        }
      }

      throw providerFailure("DRIVE_UPLOAD", uploadResponse.status);
    }

    let uploadPayload: unknown;

    try {
      uploadPayload = await uploadResponse.json();
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_UPLOAD",
        true,
        "Google Drive PDF upload returned an unreadable result for a reserved file ID.",
        "Google Drive returned an invalid response.",
        502,
      );
    }

    const uploadedFile = parseDriveFile(uploadPayload);

    if (!uploadedFile || uploadedFile.id !== fileId) {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_UPLOAD",
        true,
        "Google Drive did not confirm the reserved PDF file ID.",
        "Offer PDF storage could not be confirmed.",
        502,
      );
    }

    this.validateOwnedArtifact(
      uploadedFile,
      input.jobId,
      "PDF",
      PDF_MIME_TYPE,
    );

    return { fileId, bytes: pdfBytes };
  }

  async downloadPdf(fileId: string): Promise<Uint8Array> {
    const normalizedFileId = validateFileId(
      fileId,
      "Google PDF file ID is invalid.",
    );
    let response: Response;

    try {
      response = await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(normalizedFileId)}?alt=media&supportsAllDrives=true`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        },
      );
    } catch {
      throw new GoogleWorkspaceProviderError(
        "DRIVE_DOWNLOAD",
        true,
        "Stored offer PDF download failed.",
        "Google Drive is temporarily unavailable.",
        502,
      );
    }

    if (!response.ok) {
      throw providerFailure("DRIVE_DOWNLOAD", response.status);
    }

    return validatePdfBytes(new Uint8Array(await response.arrayBuffer()));
  }
}

export async function createGoogleWorkspaceProvider(): Promise<GoogleWorkspaceProvider> {
  const configuration = getGoogleWorkspaceConfiguration();
  const accessToken = await requestAccessToken(configuration);

  return new GoogleWorkspaceProvider(configuration, accessToken);
}
type ExitWorkspaceTokenConfig = {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
};

function requiredExitWorkspaceSecret(name: string): string {
  const value = Deno.env.get(name)?.trim();

  if (!value) {
    throw new Error(`Missing required Google Workspace secret: ${name}.`);
  }

  return value;
}

async function requestExitWorkspaceAccessToken(): Promise<string> {
  const configuration: ExitWorkspaceTokenConfig = {
    clientId: requiredExitWorkspaceSecret(
      "GOOGLE_WORKSPACE_OAUTH_CLIENT_ID",
    ),
    clientSecret: requiredExitWorkspaceSecret(
      "GOOGLE_WORKSPACE_OAUTH_CLIENT_SECRET",
    ),
    refreshToken: requiredExitWorkspaceSecret(
      "GOOGLE_WORKSPACE_OAUTH_REFRESH_TOKEN",
    ),
  };
  const body = new URLSearchParams({
    client_id: configuration.clientId,
    client_secret: configuration.clientSecret,
    refresh_token: configuration.refreshToken,
    grant_type: "refresh_token",
  });
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  if (!response.ok) {
    throw new Error("Google Workspace OAuth refresh failed.");
  }

  const payload = await response.json();

  if (typeof payload?.access_token !== "string") {
    throw new Error("Google Workspace OAuth returned no access token.");
  }

  return payload.access_token;
}

async function exitWorkspaceFetch(
  url: string,
  init: RequestInit = {},
): Promise<Response> {
  const token = await requestExitWorkspaceAccessToken();
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.headers || {}),
    },
  });

  if (!response.ok) {
    throw new Error(
      `Google Workspace request failed (${response.status}).`,
    );
  }

  return response;
}

export type TemplateValues = Record<string, string>;

async function replaceExitQrCodeShapeInSlides(
  presentationId: string,
  qrImageUrl: string | null,
): Promise<boolean> {
  try {
    const getResponse = await exitWorkspaceFetch(
      `https://slides.googleapis.com/v1/presentations/${presentationId}`,
    );
    const presentation = await getResponse.json();

    let targetElement: {
      objectId: string;
      pageObjectId: string;
      size: unknown;
      transform: unknown;
    } | null = null;

    for (const slide of presentation.slides || []) {
      const pageObjectId = slide.objectId;

      for (const element of slide.pageElements || []) {
        const textContent = element.shape?.text?.textElements
          ?.map((textElement: any) => textElement.textRun?.content || "")
          .join("");

        if (textContent && textContent.includes("{{QR_CODE}}")) {
          targetElement = {
            objectId: element.objectId,
            pageObjectId,
            size: element.size,
            transform: element.transform,
          };
          break;
        }
      }

      if (targetElement) {
        break;
      }
    }

    if (!targetElement) {
      return false;
    }

    const requests: unknown[] = [
      {
        deleteObject: {
          objectId: targetElement.objectId,
        },
      },
    ];

    if (qrImageUrl) {
      requests.push({
        createImage: {
          objectId: `qr_${crypto.randomUUID().replace(/-/g, "")}`,
          url: qrImageUrl,
          elementProperties: {
            pageObjectId: targetElement.pageObjectId,
            size: targetElement.size,
            transform: targetElement.transform,
          },
        },
      });
    }

    await exitWorkspaceFetch(
      `https://slides.googleapis.com/v1/presentations/${presentationId}:batchUpdate`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ requests }),
      },
    );

    return true;
  } catch (error) {
    console.warn(
      "Unable to replace QR code shape in Google Slides.",
      error,
    );
    return false;
  }
}

export async function copyPopulateAndExportTemplate(
  template: ExitDocumentTemplate,
  values: TemplateValues,
  qrImageUrl?: string | null,
): Promise<Uint8Array> {
  if (template.requiresQrCode) {
    if (template.source !== "GOOGLE_SLIDES") {
      throw new Error(
        "The required certificate QR code cannot be inserted into this template type.",
      );
    }

    if (!qrImageUrl?.trim()) {
      throw new Error("A QR image URL is required for this certificate template.");
    }
  }

  const copyResponse = await exitWorkspaceFetch(
    `https://www.googleapis.com/drive/v3/files/${template.templateId}/copy?fields=id`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        parents: [GENERATED_DOCUMENTS_FOLDER_ID],
        name: `${template.templateKey}-${crypto.randomUUID()}`,
      }),
    },
  );
  const copiedId = (await copyResponse.json()).id;

  if (typeof copiedId !== "string") {
    throw new Error(
      "Google Drive did not return a copied template ID.",
    );
  }

  try {
    if (template.source === "GOOGLE_SLIDES") {
      const qrCodeInserted = await replaceExitQrCodeShapeInSlides(
        copiedId,
        qrImageUrl || null,
      );

      if (template.requiresQrCode && !qrCodeInserted) {
        throw new Error(
          "The required certificate QR code could not be inserted.",
        );
      }
    }

    const textValues = { ...values };
    delete textValues["{{QR_CODE}}"];

    const requests = Object.entries(textValues).map(
      ([find, replaceText]) => ({
        replaceAllText: {
          containsText: {
            text: find,
            matchCase: true,
          },
          replaceText,
        },
      }),
    );
    const endpoint = template.source === "GOOGLE_SLIDES"
      ? `https://slides.googleapis.com/v1/presentations/${copiedId}:batchUpdate`
      : `https://docs.googleapis.com/v1/documents/${copiedId}:batchUpdate`;

    await exitWorkspaceFetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ requests }),
    });

    const exportResponse = await exitWorkspaceFetch(
      `https://www.googleapis.com/drive/v3/files/${copiedId}/export?mimeType=application/pdf`,
    );

    return new Uint8Array(await exportResponse.arrayBuffer());
  } finally {
    await exitWorkspaceFetch(
      `https://www.googleapis.com/drive/v3/files/${copiedId}`,
      {
        method: "DELETE",
      },
    ).catch(() => undefined);
  }
}

export async function uploadPdfToDriveFolder(
  folderId: string,
  fileName: string,
  pdfBytes: Uint8Array,
): Promise<{ fileId: string; webViewLink?: string }> {
  const token = await requestExitWorkspaceAccessToken();
  const metadata = JSON.stringify({
    name: fileName,
    parents: [folderId],
  });

  const boundary = "-------314159265358979323846";
  const delimiter = `\r\n--${boundary}\r\n`;
  const closeDelimiter = `\r\n--${boundary}--`;

  const bodyHead =
    `${delimiter}Content-Type: application/json; charset=UTF-8\r\n\r\n` +
    metadata +
    `${delimiter}Content-Type: application/pdf\r\n\r\n`;

  const encoder = new TextEncoder();
  const headBytes = encoder.encode(bodyHead);
  const tailBytes = encoder.encode(closeDelimiter);

  const totalLength =
    headBytes.length + pdfBytes.length + tailBytes.length;
  const multipartBody = new Uint8Array(totalLength);
  multipartBody.set(headBytes, 0);
  multipartBody.set(pdfBytes, headBytes.length);
  multipartBody.set(
    tailBytes,
    headBytes.length + pdfBytes.length,
  );

  const response = await fetch(
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": `multipart/related; boundary=${boundary}`,
      },
      body: multipartBody,
    },
  );

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");

    throw new Error(
      `Google Drive PDF upload failed (${response.status}): ${errorText}`,
    );
  }

  const payload = await response.json();

  return {
    fileId: payload.id,
    webViewLink: payload.webViewLink,
  };
}

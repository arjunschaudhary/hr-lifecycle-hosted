import { GENERATED_DOCUMENTS_FOLDER_ID, type ExitDocumentTemplate } from "./exitDocumentTemplates.ts";

type GoogleTokenConfig = { clientId: string; clientSecret: string; refreshToken: string };

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required Google Workspace secret: ${name}.`);
  return value;
}

async function accessToken(): Promise<string> {
  const config: GoogleTokenConfig = {
    clientId: required("GOOGLE_WORKSPACE_OAUTH_CLIENT_ID"),
    clientSecret: required("GOOGLE_WORKSPACE_OAUTH_CLIENT_SECRET"),
    refreshToken: required("GOOGLE_WORKSPACE_OAUTH_REFRESH_TOKEN"),
  };
  const body = new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, refresh_token: config.refreshToken, grant_type: "refresh_token" });
  const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
  if (!response.ok) throw new Error("Google Workspace OAuth refresh failed.");
  const payload = await response.json();
  if (typeof payload?.access_token !== "string") throw new Error("Google Workspace OAuth returned no access token.");
  return payload.access_token;
}

async function googleFetch(url: string, init: RequestInit = {}): Promise<Response> {
  const token = await accessToken();
  const response = await fetch(url, { ...init, headers: { Authorization: `Bearer ${token}`, ...(init.headers || {}) } });
  if (!response.ok) throw new Error(`Google Workspace request failed (${response.status}).`);
  return response;
}

export type TemplateValues = Record<string, string>;

async function replaceQrCodeShapeInSlides(
  presentationId: string,
  qrImageUrl: string | null,
): Promise<boolean> {
  try {
    const getRes = await googleFetch(`https://slides.googleapis.com/v1/presentations/${presentationId}`);
    const presentation = await getRes.json();

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
          ?.map((te: any) => te.textRun?.content || "")
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
      if (targetElement) break;
    }

    if (!targetElement) return false;

    const requests: unknown[] = [
      { deleteObject: { objectId: targetElement.objectId } },
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

    await googleFetch(
      `https://slides.googleapis.com/v1/presentations/${presentationId}:batchUpdate`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ requests }),
      },
    );

    return true;
  } catch (err) {
    console.warn("Unable to replace QR code shape in Google Slides.", err);
    return false;
  }
}

export async function copyPopulateAndExportTemplate(
  template: ExitDocumentTemplate,
  values: TemplateValues,
  qrImageUrl?: string | null,
): Promise<Uint8Array> {
  const copyResponse = await googleFetch(`https://www.googleapis.com/drive/v3/files/${template.templateId}/copy?fields=id`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ parents: [GENERATED_DOCUMENTS_FOLDER_ID], name: `${template.templateKey}-${crypto.randomUUID()}` }),
  });
  const copiedId = (await copyResponse.json()).id;
  if (typeof copiedId !== "string") throw new Error("Google Drive did not return a copied template ID.");
  try {
    if (template.source === "GOOGLE_SLIDES") {
      await replaceQrCodeShapeInSlides(copiedId, qrImageUrl || null);
    }
    const textValues = { ...values };
    delete textValues["{{QR_CODE}}"];

    const requests = Object.entries(textValues).map(([find, replaceText]) => ({ replaceAllText: { containsText: { text: find, matchCase: true }, replaceText } }));
    const endpoint = template.source === "GOOGLE_SLIDES"
      ? `https://slides.googleapis.com/v1/presentations/${copiedId}:batchUpdate`
      : `https://docs.googleapis.com/v1/documents/${copiedId}:batchUpdate`;
    await googleFetch(endpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ requests }) });
    const exportResponse = await googleFetch(`https://www.googleapis.com/drive/v3/files/${copiedId}/export?mimeType=application/pdf`);
    return new Uint8Array(await exportResponse.arrayBuffer());
  } finally {
    await googleFetch(`https://www.googleapis.com/drive/v3/files/${copiedId}`, { method: "DELETE" }).catch(() => undefined);
  }
}

export async function uploadPdfToDriveFolder(
  folderId: string,
  fileName: string,
  pdfBytes: Uint8Array,
): Promise<{ fileId: string; webViewLink?: string }> {
  const token = await accessToken();
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

  const totalLength = headBytes.length + pdfBytes.length + tailBytes.length;
  const multipartBody = new Uint8Array(totalLength);
  multipartBody.set(headBytes, 0);
  multipartBody.set(pdfBytes, headBytes.length);
  multipartBody.set(tailBytes, headBytes.length + pdfBytes.length);

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
    const errText = await response.text().catch(() => "");
    throw new Error(`Google Drive PDF upload failed (${response.status}): ${errText}`);
  }

  const payload = await response.json();
  return { fileId: payload.id, webViewLink: payload.webViewLink };
}

const CERTIFICATE_ID_BYTES = 16;
const CERTIFICATE_ID_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export type CertificateVerificationIdentity = {
  certificateId: string;
  verificationUrl: string | null;
  qrPayload: string | null;
};

function getConfiguredVerificationUrlTemplate(): string | null {
  const value =
    Deno.env.get("CERTIFICATE_VERIFICATION_URL_TEMPLATE")?.trim() ||
    "https://verifycertificateportal.netlify.app/?id={certificateId}";

  if (!value.includes("{certificateId}")) {
    throw new Error(
      "CERTIFICATE_VERIFICATION_URL_TEMPLATE must contain {certificateId}.",
    );
  }

  const sample = value.replace("{certificateId}", "CERT-TEST");
  const parsed = new URL(sample);
  if (parsed.protocol !== "https:") {
    throw new Error("Certificate verification URLs must use HTTPS.");
  }

  return value;
}

/**
 * Generates the certificate-side identity without assuming a Netlify route or
 * API. When the organization confirms its Apps Script/deep-link contract, set
 * CERTIFICATE_VERIFICATION_URL_TEMPLATE to that HTTPS URL with
 * {certificateId}; QR generation then consumes `qrPayload` only.
 */
export function createCertificateVerificationIdentity(): CertificateVerificationIdentity {
  const bytes = crypto.getRandomValues(new Uint8Array(CERTIFICATE_ID_BYTES));
  const certificateId = `CERT-${Array.from(
    bytes,
    (byte) => CERTIFICATE_ID_ALPHABET[byte % CERTIFICATE_ID_ALPHABET.length],
  ).join("")}`;
  const template = getConfiguredVerificationUrlTemplate();
  const verificationUrl = template
    ? template.replaceAll("{certificateId}", certificateId)
    : null;

  return {
    certificateId,
    verificationUrl,
    qrPayload: verificationUrl,
  };
}

/** Returns null until a confirmed verification URL contract exists. */
export function getCertificateQrPayload(
  identity: CertificateVerificationIdentity,
): string | null {
  return identity.qrPayload;
}

/** Returns QuickChart HTTPS QR image URL if qrPayload is available. */
export function getCertificateQrImageUrl(
  identity: CertificateVerificationIdentity | null,
): string | null {
  if (!identity || !identity.qrPayload) return null;
  return `https://quickchart.io/qr?text=${encodeURIComponent(identity.qrPayload)}&margin=1&size=300`;
}

const CERTIFICATE_ID_BYTES = 16;
const CERTIFICATE_ID_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export type CertificateVerificationIdentity = {
  certificateId: string;
  verificationUrl: string;
  qrPayload: string;
};

function validateHttpsUrl(value: string, errorMessage: string): void {
  let parsed: URL;

  try {
    parsed = new URL(value);
  } catch {
    throw new Error(errorMessage);
  }

  if (parsed.protocol !== "https:") {
    throw new Error("Certificate verification URLs must use HTTPS.");
  }
}

function getConfiguredVerificationUrlTemplate(): string {
  const value = Deno.env
    .get("CERTIFICATE_VERIFICATION_URL_TEMPLATE")
    ?.trim();

  if (!value) {
    throw new Error(
      "Certificate verification URL configuration is missing.",
    );
  }

  if (!value.includes("{certificateId}")) {
    throw new Error(
      "CERTIFICATE_VERIFICATION_URL_TEMPLATE must contain {certificateId}.",
    );
  }

  const sample = value.replaceAll("{certificateId}", "CERT-TEST");
  validateHttpsUrl(sample, "Certificate verification URL template is invalid.");

  return value;
}

export function createCertificateVerificationIdentity(): CertificateVerificationIdentity {
  const bytes = crypto.getRandomValues(new Uint8Array(CERTIFICATE_ID_BYTES));
  const certificateId = `CERT-${Array.from(
    bytes,
    (byte) => CERTIFICATE_ID_ALPHABET[byte % CERTIFICATE_ID_ALPHABET.length],
  ).join("")}`;
  const template = getConfiguredVerificationUrlTemplate();
  const verificationUrl = template.replaceAll("{certificateId}", certificateId);

  validateHttpsUrl(
    verificationUrl,
    "Generated certificate verification URL is invalid.",
  );

  return {
    certificateId,
    verificationUrl,
    qrPayload: verificationUrl,
  };
}

export function getCertificateQrPayload(
  identity: CertificateVerificationIdentity,
): string {
  return identity.qrPayload;
}

export function getCertificateQrImageUrl(
  identity: CertificateVerificationIdentity,
): string {
  if (!identity.qrPayload.trim()) {
    throw new Error("Certificate QR payload is required.");
  }

  return `https://quickchart.io/qr?text=${encodeURIComponent(identity.qrPayload)}&margin=1&size=300`;
}

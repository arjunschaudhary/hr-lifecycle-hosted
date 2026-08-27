export const ISSUED_DOCUMENTS_BUCKET = "candidate-issued-documents";
export const GENERATED_DOCUMENTS_FOLDER_ID = "12w4YtCeWqTCha2a4Pk_H56vfZM-EkWD1";

export type ExitDocumentVariant =
  | "INTERN_CERTIFICATE"
  | "VOLUNTEER_CERTIFICATE"
  | "POD_LEAD_CERTIFICATE"
  | "INTERN_LOR"
  | "POD_LEAD_LOR"
  | "OPERATIONS_ASSOCIATE_LOR";

export type ExitDocumentTemplate = {
  variant: ExitDocumentVariant;
  templateKey: string;
  templateVersion: string;
  source: "GOOGLE_SLIDES" | "GOOGLE_DOCS";
  templateId: string;
  requiresCertificateId: boolean;
  requiresQrCode: boolean;
  placeholders: readonly string[];
};

const CERTIFICATE_PLACEHOLDERS = [
  "{{NAME}}",
  "{{COMPLETED_HOURS}}",
  "{{COMMITTED_HOURS}}",
  "{{NH2}}",
  "{{DOMAIN}}",
  "{{START_DATE}}",
  "{{END_DATE}}",
  "{{CERTIFICATE_ID}}",
  "{{QR_CODE}}",
] as const;

const LOR_PLACEHOLDERS = [
  "{{NAME}}",
  "{{DOMAIN}}",
  "{{START_DATE}}",
  "{{END_DATE}}",
] as const;

export const EXIT_DOCUMENT_TEMPLATES: Record<
  ExitDocumentVariant,
  ExitDocumentTemplate
> = {
  INTERN_CERTIFICATE: {
    variant: "INTERN_CERTIFICATE",
    templateKey: "intern-certificate",
    templateVersion: "1",
    source: "GOOGLE_SLIDES",
    templateId: "1gP_mtOIherxnM5xqWKipmcT-VyRyoaEpslQlHEKnzT0",
    requiresCertificateId: true,
    requiresQrCode: true,
    placeholders: CERTIFICATE_PLACEHOLDERS,
  },
  VOLUNTEER_CERTIFICATE: {
    variant: "VOLUNTEER_CERTIFICATE",
    templateKey: "volunteer-certificate",
    templateVersion: "1",
    source: "GOOGLE_SLIDES",
    templateId: "1XCU-IJFkXk--hmB-Eszde2iT4zXpenlW24OSMCcpi4I",
    requiresCertificateId: true,
    requiresQrCode: true,
    placeholders: CERTIFICATE_PLACEHOLDERS,
  },
  POD_LEAD_CERTIFICATE: {
    variant: "POD_LEAD_CERTIFICATE",
    templateKey: "pod-lead-certificate",
    templateVersion: "1",
    source: "GOOGLE_SLIDES",
    templateId: "16AqgQJ-2qBsvbyqhv9OA6dDJosKhJq18C7DeK0wthp4",
    requiresCertificateId: true,
    requiresQrCode: true,
    placeholders: CERTIFICATE_PLACEHOLDERS,
  },
  INTERN_LOR: {
    variant: "INTERN_LOR",
    templateKey: "intern-lor",
    templateVersion: "1",
    source: "GOOGLE_DOCS",
    templateId: "10WFU_DjDmVffgXwQRw_1XAnTBA1NApQaW-Zbw9-4lu8",
    requiresCertificateId: false,
    requiresQrCode: false,
    placeholders: LOR_PLACEHOLDERS,
  },
  POD_LEAD_LOR: {
    variant: "POD_LEAD_LOR",
    templateKey: "pod-lead-lor",
    templateVersion: "1",
    source: "GOOGLE_DOCS",
    templateId: "1crECUj6RMAAft-uQY-s0eA1qV5WlheK7AqG-w6mJE7Y",
    requiresCertificateId: false,
    requiresQrCode: false,
    placeholders: LOR_PLACEHOLDERS,
  },
  OPERATIONS_ASSOCIATE_LOR: {
    variant: "OPERATIONS_ASSOCIATE_LOR",
    templateKey: "operations-associate-lor",
    templateVersion: "1",
    source: "GOOGLE_DOCS",
    templateId: "10VrH3ahGLyWefFCC2ZRbjRcSVhli3vdDd04BULG4U34",
    requiresCertificateId: false,
    requiresQrCode: false,
    placeholders: LOR_PLACEHOLDERS,
  },
};

export function getExitDocumentTemplate(variant: string): ExitDocumentTemplate {
  const template = EXIT_DOCUMENT_TEMPLATES[variant as ExitDocumentVariant];

  if (!template) {
    throw new Error("Unsupported exit-document variant.");
  }

  return template;
}

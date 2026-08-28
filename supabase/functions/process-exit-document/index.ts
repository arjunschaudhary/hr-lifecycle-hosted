import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";
import { createCertificateVerificationIdentity, getCertificateQrImageUrl, type CertificateVerificationIdentity } from "../_shared/certificateVerificationProvider.ts";
import { GENERATED_DOCUMENTS_FOLDER_ID, getExitDocumentTemplate, ISSUED_DOCUMENTS_BUCKET } from "../_shared/exitDocumentTemplates.ts";
import { copyPopulateAndExportTemplate, uploadPdfToDriveFolder } from "../_shared/googleWorkspaceProvider.ts";
import { isGmailProviderError, sendEmailWithGmailAttachment } from "../_shared/gmailProvider.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const certificateId = /^CERT-[A-Z0-9]+$/;
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function recordFailureSafely(
  admin: ReturnType<typeof createClient>,
  jobId: string,
  errorMessage: string,
  retryable: boolean,
  providerOutcome: "UNKNOWN" | "NOT_STARTED",
): Promise<void> {
  try {
    const { error } = await admin.rpc("record_exit_document_job_failure", {
      p_job_id: jobId,
      p_error_message: errorMessage,
      p_retryable: retryable,
      p_provider_outcome: providerOutcome,
    });
    if (error) console.error("Unable to record exit-document job failure.", error);
  } catch (recordingError) {
    console.error("Unable to record exit-document job failure.", recordingError);
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const authorization = request.headers.get("authorization");
  const { jobId } = await request.json().catch(() => ({}));
  if (typeof jobId !== "string" || !uuid.test(jobId)) return json({ error: "A valid jobId is required." }, 400);
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!url || !serviceKey) return json({ error: "Worker configuration is incomplete." }, 500);
  if (authorization !== `Bearer ${serviceKey}`) return json({ error: "Service-role worker access is required." }, 403);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  try {
    const { data: claim, error: claimError } = await admin.rpc("claim_exit_document_job", { p_job_id: jobId });
    if (claimError) throw claimError;
    const payload = claim as { exitCaseId: string; documentVariant: string };
    const template = getExitDocumentTemplate(payload.documentVariant);
    const { data: exitCase, error: caseError } = await admin.from("exit_cases").select("exit_case_id,candidate_id,lifecycle_id").eq("exit_case_id", payload.exitCaseId).single();
    if (caseError || !exitCase) throw new Error("Exit case could not be resolved.");
    const [{ data: candidate }, { data: lifecycle }] = await Promise.all([
      admin.from("master_candidates").select("full_name,email,applied_role").eq("candidate_id", exitCase.candidate_id).single(),
      admin.from("hr_lifecycle").select("probation_start_date,current_end_date,internship_duration_months,total_extension_months,current_internship_duration_days").eq("lifecycle_id", exitCase.lifecycle_id).single(),
    ]);
    if (!candidate || !lifecycle) throw new Error("Candidate or lifecycle could not be resolved.");
    const { data: existingDocument, error: existingDocumentError } = await admin
      .from("exit_documents")
      .select("storage_path,certificate_id,certificate_verification_url")
      .eq("exit_case_id", payload.exitCaseId)
      .eq("document_variant", payload.documentVariant)
      .maybeSingle();
    if (existingDocumentError) throw existingDocumentError;

    let identity: CertificateVerificationIdentity | null = null;
    if (template.requiresCertificateId) {
      if (existingDocument?.certificate_id) {
        const normalizedCertificateId = existingDocument.certificate_id.trim().toUpperCase();
        if (
          normalizedCertificateId !== existingDocument.certificate_id ||
          !certificateId.test(normalizedCertificateId)
        ) {
          throw new Error("Existing certificate identity is invalid.");
        }
        identity = {
          certificateId: normalizedCertificateId,
          verificationUrl: existingDocument.certificate_verification_url,
          qrPayload: existingDocument.certificate_verification_url,
        };
      } else {
        if (existingDocument?.storage_path) {
          throw new Error("Stored certificate requires identity reconciliation before retry.");
        }
        identity = createCertificateVerificationIdentity();
      }
    } else if (existingDocument?.certificate_id) {
      throw new Error("Non-certificate document has an unexpected certificate identity.");
    }
    const qrImageUrl = getCertificateQrImageUrl(identity);
    const totalInternshipMonths =
      (lifecycle.internship_duration_months || 0) +
      (lifecycle.total_extension_months || 0);
    const committedHours = totalInternshipMonths * 100;
    const completedHours = committedHours;
    const values: Record<string, string> = {
      "{{NAME}}": candidate.full_name,
      "{{DOMAIN}}": candidate.applied_role,
      "{{START_DATE}}": lifecycle.probation_start_date || "",
      "{{END_DATE}}": lifecycle.current_end_date || "",
      "{{NH2}}": String(lifecycle.internship_duration_months || ""),
      "{{COMMITTED_HOURS}}": String(committedHours),
      "{{COMPLETED_HOURS}}": String(completedHours),
      "{{CERTIFICATE_ID}}": identity?.certificateId || "",
      "{{QR_CODE}}": "",
    };
    let pdf: Uint8Array;
    let completion: unknown = null;
    if (existingDocument?.storage_path) {
      const { data, error } = await admin.storage.from(ISSUED_DOCUMENTS_BUCKET).download(existingDocument.storage_path);
      if (error || !data) throw new Error("Previously generated PDF could not be loaded for email retry.");
      pdf = new Uint8Array(await data.arrayBuffer());
    } else {
      pdf = await copyPopulateAndExportTemplate(template, values, qrImageUrl);
      const documentId = crypto.randomUUID();
      const objectPath = `candidate/${exitCase.candidate_id}/exit/${exitCase.exit_case_id}/${template.variant}/${documentId}.pdf`;
      const { error: uploadError } = await admin.storage.from(ISSUED_DOCUMENTS_BUCKET).upload(objectPath, pdf, { contentType: "application/pdf", upsert: false });
      if (uploadError) throw uploadError;
      const archiveFileName = `${candidate.full_name.replace(/[^a-zA-Z0-9_-]/g, "_")}_${template.templateKey}_${documentId.slice(0, 8)}.pdf`;
      await uploadPdfToDriveFolder(GENERATED_DOCUMENTS_FOLDER_ID, archiveFileName, pdf);
      const result = await admin.rpc("complete_exit_document_generation", { p_job_id: jobId, p_document_id: documentId, p_storage_path: objectPath, p_bucket_id: ISSUED_DOCUMENTS_BUCKET, p_template_key: template.templateKey, p_template_version: template.templateVersion, p_certificate_id: identity?.certificateId ?? null, p_certificate_verification_url: identity?.verificationUrl ?? null });
      if (result.error) throw result.error;
      completion = result.data;
    }
    const name = template.variant.includes("LOR") ? "Letter of Recommendation" : "Internship Certificate";
    try {
      const gmail = await sendEmailWithGmailAttachment(candidate.email, { subject: `${name} – Jarurat Care Foundation`, text: `Dear ${candidate.full_name},\n\nYour ${name} is attached.`, html: `<p>Dear ${candidate.full_name},</p><p>Your ${name} is attached.</p>` }, { filename: `${template.templateKey}.pdf`, contentType: "application/pdf", content: pdf });
      const { error: emailError } = await admin.rpc("complete_exit_document_email", { p_job_id: jobId, p_gmail_message_id: gmail.messageId });
      if (emailError) throw emailError;
      return json({ status: "EMAILED", document: completion?.[0] ?? null });
    } catch (error) {
      const retryable = isGmailProviderError(error) ? error.retryable : false;
      const providerOutcome = isGmailProviderError(error) && error.deliveryOutcome === "UNKNOWN" ? "UNKNOWN" : "NOT_STARTED";
      await recordFailureSafely(
        admin,
        jobId,
        error instanceof Error ? error.message : "Email delivery failed.",
        retryable,
        providerOutcome,
      );
      return json({ status: "GENERATED", emailPending: true }, 202);
    }
  } catch (error) {
    console.error("Exit-document worker generation failed:", error);
    if (error && typeof error === "object") {
      try {
        console.error("Detailed Error Object:", JSON.stringify(error, Object.getOwnPropertyNames(error)));
      } catch {
        console.error("Detailed Error Object (non-serializable):", error);
      }
    }

    let errorMessage = "Document generation failed.";
    if (error instanceof Error) {
      errorMessage = `${error.name || "Error"}: ${error.message}`;
      if (error.stack) {
        console.error("Error stack trace:", error.stack);
      }
    } else if (error && typeof error === "object") {
      const err = error as any;
      const parts: string[] = [];
      if (err.message) parts.push(String(err.message));
      if (err.code) parts.push(`Code: ${err.code}`);
      if (err.details) parts.push(`Details: ${err.details}`);
      if (err.hint) parts.push(`Hint: ${err.hint}`);
      if (err.status) parts.push(`Status: ${err.status}`);
      if (err.statusCode) parts.push(`StatusCode: ${err.statusCode}`);
      if (parts.length > 0) {
        errorMessage = parts.join(" | ");
      } else {
        errorMessage = JSON.stringify(error);
      }
    } else if (typeof error === "string") {
      errorMessage = error;
    } else {
      errorMessage = String(error);
    }

    await recordFailureSafely(
      admin,
      jobId,
      errorMessage,
      true,
      "NOT_STARTED",
    );
    return json({ error: "Exit-document processing failed." }, 500);
  }
});

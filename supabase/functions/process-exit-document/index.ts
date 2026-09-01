import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";

import {
  createCertificateVerificationIdentity,
  getCertificateQrImageUrl,
  type CertificateVerificationIdentity,
} from "../_shared/certificateVerificationProvider.ts";

import {
  GENERATED_DOCUMENTS_FOLDER_ID,
  getExitDocumentTemplate,
  ISSUED_DOCUMENTS_BUCKET,
} from "../_shared/exitDocumentTemplates.ts";

import {
  copyPopulateAndExportTemplate,
  uploadPdfToDriveFolder,
} from "../_shared/googleWorkspaceProvider.ts";

import {
  isGmailProviderError,
  sendEmailWithGmailAttachment,
} from "../_shared/gmailProvider.ts";

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const certificateId =
  /^CERT-[A-Z0-9]+$/;

const json = (
  body: Record<string, unknown>,
  status = 200,
) =>
  new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "Content-Type": "application/json",
      },
    },
  );

type ProviderOutcome =
  | "NOT_STARTED"
  | "UNKNOWN"
  | "ACCEPTED";

type ExitDocumentClaim = {
  terminalized?: false;
  exitCaseId: string;
  exitDocumentRequestId: string;
  documentVariant: string;
  attemptCount: number;
  leaseExpiresAt?: string | null;
  staleProcessingReclaim?: boolean;
};

type TerminalizedExitDocumentClaim = {
  terminalized: true;
  jobId: string;
  jobStatus: "FAILED";
  requestStatus: "FAILED";
  attemptCount: number;
};

function getDocumentDomain(appliedRole: string, isLor: boolean): string {
  const normalizedRole = appliedRole.trim();

  if (!isLor) {
    return normalizedRole;
  }

  const domain = normalizedRole.replace(/\s+Intern$/i, "").trim();
  return domain || normalizedRole;
}

type ExitDocumentReservation = {
  requestId: string;
  documentId: string;
  storagePath: string;
  certificateId: string | null;
  certificateVerificationUrl: string | null;
  driveFileId: string | null;
  adoptedExistingDocument?: boolean;
};

function errorMessageOf(
  error: unknown,
  fallback: string,
): string {
  if (error instanceof Error) {
    return `${error.name || "Error"}: ${error.message}`;
  }

  if (error && typeof error === "object") {
    const value = error as Record<string, unknown>;
    const parts: string[] = [];

    if (value.message) {
      parts.push(String(value.message));
    }

    if (value.code) {
      parts.push(`Code: ${String(value.code)}`);
    }

    if (value.details) {
      parts.push(`Details: ${String(value.details)}`);
    }

    if (value.hint) {
      parts.push(`Hint: ${String(value.hint)}`);
    }

    if (value.status) {
      parts.push(`Status: ${String(value.status)}`);
    }

    if (value.statusCode) {
      parts.push(
        `StatusCode: ${String(value.statusCode)}`,
      );
    }

    if (parts.length > 0) {
      return parts.join(" | ");
    }

    try {
      return JSON.stringify(error);
    } catch {
      return fallback;
    }
  }

  if (typeof error === "string" && error.trim()) {
    return error;
  }

  return fallback;
}

function requireStoredCertificateVerificationUrl(
  value: unknown,
  expectedCertificateId: string,
): string {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value !== value.trim()
  ) {
    throw new Error(
      "Stored certificate requires controlled verification/QR reconciliation.",
    );
  }

  let parsed: URL;

  try {
    parsed = new URL(value);
  } catch {
    throw new Error(
      "Stored certificate requires controlled verification/QR reconciliation.",
    );
  }

  const linkedCertificateId =
    parsed.searchParams
      .get("id")
      ?.trim()
      .toUpperCase();

  if (
    parsed.protocol !== "https:" ||
    linkedCertificateId !==
      expectedCertificateId
  ) {
    throw new Error(
      "Stored certificate requires controlled verification/QR reconciliation.",
    );
  }

  return value;
}

function isStorageObjectNotFound(
  error: unknown,
): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }

  const value =
    error as Record<string, unknown>;

  const statusCode =
    value.statusCode ??
    value.status ??
    value.status_code;

  if (
    String(statusCode ?? "") === "404"
  ) {
    return true;
  }

  const message =
    typeof value.message === "string"
      ? value.message.toLowerCase()
      : "";

  return (
    message.includes("object not found") ||
    message.includes("not found")
  );
}

async function downloadIssuedPdfIfPresent(
  admin: ReturnType<typeof createClient>,
  storagePath: string,
): Promise<Uint8Array | null> {
  const { data, error } =
    await admin.storage
      .from(ISSUED_DOCUMENTS_BUCKET)
      .download(storagePath);

  if (error) {
    if (isStorageObjectNotFound(error)) {
      return null;
    }

    throw error;
  }

  if (!data) {
    throw new Error(
      "Issued-document Storage returned no PDF data.",
    );
  }

  const bytes =
    new Uint8Array(
      await data.arrayBuffer(),
    );

  if (bytes.byteLength === 0) {
    throw new Error(
      "Issued-document Storage returned an empty PDF.",
    );
  }

  return bytes;
}

async function recordFailureSafely(
  admin: ReturnType<typeof createClient>,
  jobId: string,
  claimAttemptCount: number,
  errorMessage: string,
  retryable: boolean,
  providerOutcome: ProviderOutcome,
): Promise<void> {
  try {
    const { error } =
      await admin.rpc(
        "record_exit_document_job_failure_fenced",
        {
          p_job_id: jobId,
          p_claim_attempt_count:
            claimAttemptCount,
          p_error_message:
            errorMessage,
          p_retryable:
            retryable,
          p_provider_outcome:
            providerOutcome,
        },
      );

    if (error) {
      console.error(
        "Unable to record exit-document job failure.",
        error,
      );
    }
  } catch (recordingError) {
    console.error(
      "Unable to record exit-document job failure.",
      recordingError,
    );
  }
}

async function reconcileDurableProviderState(
  admin: ReturnType<typeof createClient>,
  jobId: string,
): Promise<Response | null> {
  const { data: job, error: jobError } =
    await admin
      .from("automation_jobs")
      .select(
        "job_type,job_status,attempt_count,provider_message_id,provider_accepted_at",
      )
      .eq("job_id", jobId)
      .maybeSingle();

  if (jobError) {
    throw jobError;
  }

  if (!job) {
    return null;
  }

  if (job.job_type !== "EXIT_DOCUMENT") {
    return json(
      {
        error:
          "Automation job is not an Exit-document job.",
      },
      400,
    );
  }

  if (job.job_status === "SUCCESS") {
    return json({
      status: "EMAILED",
      alreadyCompleted: true,
    });
  }

  const hasProviderMessage =
    typeof job.provider_message_id ===
      "string" &&
    job.provider_message_id.trim() !== "";

  const hasProviderAcceptedAt =
    typeof job.provider_accepted_at ===
      "string" &&
    job.provider_accepted_at.trim() !== "";

  if (
    job.job_status === "PROCESSING" &&
    hasProviderMessage &&
    hasProviderAcceptedAt
  ) {
    if (
      !Number.isInteger(
        job.attempt_count,
      ) ||
      job.attempt_count < 1
    ) {
      throw new Error(
        "Exit-document provider reconciliation has no valid claim attempt.",
      );
    }

    const {
      error: completionError,
    } = await admin.rpc(
      "complete_exit_document_email_fenced",
      {
        p_job_id: jobId,
        p_claim_attempt_count:
          job.attempt_count,
        p_gmail_message_id:
          job.provider_message_id,
      },
    );

    if (!completionError) {
      return json({
        status: "EMAILED",
        reconciledProviderAcceptance:
          true,
      });
    }

    console.error(
      "Unable to finalize already-accepted Exit-document email.",
      completionError,
    );

    return json(
      {
        status:
          "EMAIL_ACCEPTED_RECONCILIATION_REQUIRED",
        emailPending:
          true,
      },
      202,
    );
  }

  if (
    hasProviderMessage ||
    hasProviderAcceptedAt
  ) {
    return json(
      {
        status:
          "PROVIDER_RECONCILIATION_REQUIRED",
        emailPending:
          true,
      },
      202,
    );
  }

  if (job.job_status === "PROCESSING") {
    const {
      data: requestState,
      error: requestStateError,
    } = await admin
      .from("exit_document_requests")
      .select(
        "email_attempted_at",
      )
      .eq("job_id", jobId)
      .maybeSingle();

    if (requestStateError) {
      throw requestStateError;
    }

    if (
      requestState?.email_attempted_at
    ) {
      return json(
        {
          status:
            "EMAIL_OUTCOME_RECONCILIATION_REQUIRED",
          emailPending:
            true,
        },
        202,
      );
    }
  }

  return null;
}

function parseReservation(
  value: unknown,
): ExitDocumentReservation {
  if (
    !value ||
    typeof value !== "object"
  ) {
    throw new Error(
      "Exit-document reservation returned invalid data.",
    );
  }

  const data =
    value as Record<string, unknown>;

  const requestId =
    typeof data.requestId === "string"
      ? data.requestId
      : "";

  const documentId =
    typeof data.documentId === "string"
      ? data.documentId
      : "";

  const storagePath =
    typeof data.storagePath === "string"
      ? data.storagePath
      : "";

  const reservedCertificateId =
    typeof data.certificateId ===
      "string"
      ? data.certificateId
      : null;

  const verificationUrl =
    typeof data
      .certificateVerificationUrl ===
      "string"
      ? data.certificateVerificationUrl
      : null;

  const driveFileId =
    typeof data.driveFileId === "string"
      ? data.driveFileId
      : null;

  if (
    !uuid.test(requestId) ||
    !uuid.test(documentId) ||
    !storagePath.trim()
  ) {
    throw new Error(
      "Exit-document reservation is incomplete.",
    );
  }

  return {
    requestId,
    documentId,
    storagePath,
    certificateId:
      reservedCertificateId,
    certificateVerificationUrl:
      verificationUrl,
    driveFileId,
    adoptedExistingDocument:
      data.adoptedExistingDocument ===
        true,
  };
}

Deno.serve(
  async (request) => {
    if (request.method !== "POST") {
      return json(
        {
          error:
            "Method not allowed.",
        },
        405,
      );
    }

    const authorization =
      request.headers.get(
        "authorization",
      );

    const { jobId } =
      await request
        .json()
        .catch(() => ({}));

    if (
      typeof jobId !== "string" ||
      !uuid.test(jobId)
    ) {
      return json(
        {
          error:
            "A valid jobId is required.",
        },
        400,
      );
    }

    const url =
      Deno.env.get("SUPABASE_URL")!;

    const serviceKey =
      Deno.env.get(
        "SUPABASE_SERVICE_ROLE_KEY",
      )!;

    if (!url || !serviceKey) {
      return json(
        {
          error:
            "Worker configuration is incomplete.",
        },
        500,
      );
    }

    if (
      authorization !==
        `Bearer ${serviceKey}`
    ) {
      return json(
        {
          error:
            "Service-role worker access is required.",
        },
        403,
      );
    }

    const admin =
      createClient(
        url,
        serviceKey,
        {
          auth: {
            persistSession: false,
          },
        },
      );

    let claimAttemptCount:
      number | null = null;

    let gmailInvocationStarted =
      false;

    let providerAcceptanceRecorded =
      false;

    try {
      const reconciliation =
        await reconcileDurableProviderState(
          admin,
          jobId,
        );

      if (reconciliation) {
        return reconciliation;
      }

      const {
        data: claim,
        error: claimError,
      } = await admin.rpc(
        "claim_exit_document_job",
        {
          p_job_id: jobId,
        },
      );

      if (claimError) {
        throw claimError;
      }

      const payload =
        claim as
          | ExitDocumentClaim
          | TerminalizedExitDocumentClaim;

      if (
        payload?.terminalized === true
      ) {
        if (
          !uuid.test(payload.jobId) ||
          payload.jobId !== jobId ||
          payload.jobStatus !==
            "FAILED" ||
          payload.requestStatus !==
            "FAILED" ||
          !Number.isInteger(
            payload.attemptCount,
          ) ||
          payload.attemptCount < 5
        ) {
          throw new Error(
            "Exit-document terminal claim returned invalid data.",
          );
        }

        return json({
          status: "FAILED",
          terminalized: true,
          attemptCount:
            payload.attemptCount,
        });
      }

      if (
        !payload ||
        !uuid.test(
          payload.exitCaseId,
        ) ||
        !uuid.test(
          payload
            .exitDocumentRequestId,
        ) ||
        typeof payload
          .documentVariant !== "string" ||
        !Number.isInteger(
          payload.attemptCount,
        ) ||
        payload.attemptCount < 1
      ) {
        throw new Error(
          "Exit-document claim returned invalid data.",
        );
      }

      claimAttemptCount =
        payload.attemptCount;

      const template =
        getExitDocumentTemplate(
          payload.documentVariant,
        );

      const {
        data: exitCase,
        error: caseError,
      } = await admin
        .from("exit_cases")
        .select(
          "exit_case_id,candidate_id,lifecycle_id",
        )
        .eq(
          "exit_case_id",
          payload.exitCaseId,
        )
        .single();

      if (
        caseError ||
        !exitCase
      ) {
        throw new Error(
          "Exit case could not be resolved.",
        );
      }

      const [
        {
          data: candidate,
          error: candidateError,
        },
        {
          data: lifecycle,
          error: lifecycleError,
        },
      ] = await Promise.all([
        admin
          .from(
            "master_candidates",
          )
          .select(
            "full_name,email,applied_role",
          )
          .eq(
            "candidate_id",
            exitCase.candidate_id,
          )
          .single(),

        admin
          .from("hr_lifecycle")
          .select(
            "probation_start_date,current_end_date,internship_duration_months,total_extension_months,current_internship_duration_days",
          )
          .eq(
            "lifecycle_id",
            exitCase.lifecycle_id,
          )
          .single(),
      ]);

      if (
        candidateError ||
        lifecycleError ||
        !candidate ||
        !lifecycle
      ) {
        throw new Error(
          "Candidate or lifecycle could not be resolved.",
        );
      }

      if (
        typeof candidate.email !==
          "string" ||
        !candidate.email.trim()
      ) {
        throw new Error(
          "Candidate email is unavailable.",
        );
      }

      const {
        data: existingDocument,
        error:
          existingDocumentError,
      } = await admin
        .from("exit_documents")
        .select(
          "document_id,bucket_id,storage_path,certificate_id,certificate_verification_url",
        )
        .eq(
          "exit_case_id",
          payload.exitCaseId,
        )
        .eq(
          "document_variant",
          payload.documentVariant,
        )
        .maybeSingle();

      if (existingDocumentError) {
        throw existingDocumentError;
      }

      const {
        data: requestRecoveryState,
        error: requestRecoveryStateError,
      } = await admin
        .from("exit_document_requests")
        .select(
          "reserved_document_id,reserved_storage_path,reserved_certificate_id,reserved_certificate_verification_url,drive_file_id",
        )
        .eq(
          "request_id",
          payload.exitDocumentRequestId,
        )
        .single();

      if (
        requestRecoveryStateError ||
        !requestRecoveryState
      ) {
        throw new Error(
          "Exit-document recovery reservation state could not be resolved.",
        );
      }

      let identity:
        CertificateVerificationIdentity |
        null = null;

      if (
        template
          .requiresCertificateId
      ) {
        if (
          existingDocument
            ?.certificate_id
        ) {
          const normalizedCertificateId =
            existingDocument
              .certificate_id
              .trim()
              .toUpperCase();

          if (
            normalizedCertificateId !==
              existingDocument
                .certificate_id ||
            !certificateId.test(
              normalizedCertificateId,
            )
          ) {
            throw new Error(
              "Existing certificate identity is invalid.",
            );
          }

          const storedVerificationUrl =
            requireStoredCertificateVerificationUrl(
              existingDocument
                .certificate_verification_url,
              normalizedCertificateId,
            );

          identity = {
            certificateId:
              normalizedCertificateId,
            verificationUrl:
              storedVerificationUrl,
            qrPayload:
              storedVerificationUrl,
          };
        } else if (
          requestRecoveryState
            .reserved_certificate_id
        ) {
          const reservedCertificateId =
            String(
              requestRecoveryState
                .reserved_certificate_id,
            )
              .trim()
              .toUpperCase();

          if (
            reservedCertificateId !==
              requestRecoveryState
                .reserved_certificate_id ||
            !certificateId.test(
              reservedCertificateId,
            )
          ) {
            throw new Error(
              "Reserved certificate identity is invalid.",
            );
          }

          const reservedVerificationUrl =
            requireStoredCertificateVerificationUrl(
              requestRecoveryState
                .reserved_certificate_verification_url,
              reservedCertificateId,
            );

          identity = {
            certificateId:
              reservedCertificateId,
            verificationUrl:
              reservedVerificationUrl,
            qrPayload:
              reservedVerificationUrl,
          };
        } else {
          if (
            requestRecoveryState
              .reserved_certificate_verification_url
          ) {
            throw new Error(
              "Certificate reservation identity is incomplete.",
            );
          }

          if (
            existingDocument
              ?.storage_path
          ) {
            throw new Error(
              "Stored certificate requires identity reconciliation before retry.",
            );
          }

          identity =
            createCertificateVerificationIdentity();
        }
      } else {
        if (
          existingDocument
            ?.certificate_id ||
          existingDocument
            ?.certificate_verification_url ||
          requestRecoveryState
            .reserved_certificate_id ||
          requestRecoveryState
            .reserved_certificate_verification_url
        ) {
          throw new Error(
            "Non-certificate document has an unexpected certificate identity.",
          );
        }
      }

      const {
        data: reservationData,
        error: reservationError,
      } = await admin.rpc(
        "reserve_exit_document_generation_fenced",
        {
          p_job_id:
            jobId,
          p_claim_attempt_count:
            claimAttemptCount,
          p_certificate_id:
            identity
              ?.certificateId ??
            null,
          p_certificate_verification_url:
            identity
              ?.verificationUrl ??
            null,
        },
      );

      if (reservationError) {
        throw reservationError;
      }

      const reservation =
        parseReservation(
          reservationData,
        );

      if (
        reservation.requestId !==
        payload
          .exitDocumentRequestId
      ) {
        throw new Error(
          "Exit-document reservation does not match the claimed request.",
        );
      }

      const expectedStoragePath =
        `candidate/${exitCase.candidate_id}/exit/${exitCase.exit_case_id}/${template.variant}/${reservation.documentId}.pdf`;

      if (
        reservation.storagePath !==
        expectedStoragePath
      ) {
        throw new Error(
          "Exit-document reservation returned an unexpected Storage path.",
        );
      }

      if (existingDocument) {
        if (
          existingDocument
            .document_id !==
            reservation.documentId ||
          existingDocument
            .storage_path !==
            reservation.storagePath ||
          existingDocument
            .bucket_id !==
            ISSUED_DOCUMENTS_BUCKET
        ) {
          throw new Error(
            "Existing Exit document does not match the durable reservation.",
          );
        }
      }

      if (
        template
          .requiresCertificateId
      ) {
        if (
          !reservation
            .certificateId ||
          !certificateId.test(
            reservation
              .certificateId,
          ) ||
          reservation
            .certificateId !==
            reservation
              .certificateId
              .trim()
              .toUpperCase()
        ) {
          throw new Error(
            "Reserved certificate identity is invalid.",
          );
        }

        const reservedVerificationUrl =
          requireStoredCertificateVerificationUrl(
            reservation
              .certificateVerificationUrl,
            reservation
              .certificateId,
          );

        identity = {
          certificateId:
            reservation
              .certificateId,
          verificationUrl:
            reservedVerificationUrl,
          qrPayload:
            reservedVerificationUrl,
        };
      } else {
        if (
          reservation
            .certificateId !==
            null ||
          reservation
            .certificateVerificationUrl !==
            null
        ) {
          throw new Error(
            "Reserved LOR contains an unexpected certificate identity.",
          );
        }

        identity = null;
      }

      let qrImageUrl:
        string | null = null;

      if (
        template.requiresQrCode
      ) {
        if (!identity) {
          throw new Error(
            "Certificate identity is required for QR generation.",
          );
        }

        if (
          !identity
            .verificationUrl
            .trim() ||
          !identity
            .qrPayload
            .trim()
        ) {
          throw new Error(
            "Certificate verification URL and QR payload are required.",
          );
        }

        qrImageUrl =
          getCertificateQrImageUrl(
            identity,
          );

        if (
          !qrImageUrl.trim()
        ) {
          throw new Error(
            "Certificate QR image URL could not be generated.",
          );
        }
      }

      const totalInternshipMonths =
        (
          lifecycle
            .internship_duration_months ||
          0
        ) +
        (
          lifecycle
            .total_extension_months ||
          0
        );

      const committedHours =
        totalInternshipMonths * 100;

      const completedHours =
        committedHours;

      const values:
        Record<string, string> = {
          "{{NAME}}":
            candidate.full_name,

          "{{DOMAIN}}":
            getDocumentDomain(
              candidate.applied_role,
              template.variant.includes("LOR"),
            ),

          "{{START_DATE}}":
            lifecycle
              .probation_start_date ||
            "",

          "{{END_DATE}}":
            lifecycle
              .current_end_date ||
            "",

          "{{NH2}}":
            String(
              lifecycle
                .internship_duration_months ||
                "",
            ),

          "{{COMMITTED_HOURS}}":
            String(
              committedHours,
            ),

          "{{COMPLETED_HOURS}}":
            String(
              completedHours,
            ),

          "{{CERTIFICATE_ID}}":
            identity
              ?.certificateId ||
            "",

          "{{QR_CODE}}":
            "",
        };

      let pdf =
        await downloadIssuedPdfIfPresent(
          admin,
          reservation.storagePath,
        );

      if (!pdf) {
        pdf =
          await copyPopulateAndExportTemplate(
            template,
            values,
            qrImageUrl,
          );

        const {
          error: uploadError,
        } = await admin.storage
          .from(
            ISSUED_DOCUMENTS_BUCKET,
          )
          .upload(
            reservation.storagePath,
            pdf,
            {
              contentType:
                "application/pdf",
              upsert: false,
            },
          );

        if (uploadError) {
          const recoveredPdf =
            await downloadIssuedPdfIfPresent(
              admin,
              reservation
                .storagePath,
            );

          if (recoveredPdf) {
            pdf =
              recoveredPdf;
          } else {
            throw uploadError;
          }
        }
      }

      const archiveFileName =
        `${
          String(
            candidate.full_name ||
              "candidate",
          ).replace(
            /[^a-zA-Z0-9_-]/g,
            "_",
          )
        }_${template.templateKey}_${
          reservation
            .documentId
            .slice(0, 8)
        }.pdf`;

      const drive =
        await uploadPdfToDriveFolder(
          GENERATED_DOCUMENTS_FOLDER_ID,
          archiveFileName,
          pdf,
          {
            requestId:
              reservation
                .requestId,

            existingFileId:
              reservation
                .driveFileId,
          },
        );

      const {
        error: driveRecordError,
      } = await admin.rpc(
        "record_exit_document_drive_archive_fenced",
        {
          p_job_id:
            jobId,
          p_claim_attempt_count:
            claimAttemptCount,
          p_drive_file_id:
            drive.fileId,
        },
      );

      if (driveRecordError) {
        throw driveRecordError;
      }

      const {
        data: completion,
        error: generationError,
      } = await admin.rpc(
        "complete_exit_document_generation_fenced",
        {
          p_job_id:
            jobId,

          p_claim_attempt_count:
            claimAttemptCount,

          p_document_id:
            reservation
              .documentId,

          p_storage_path:
            reservation
              .storagePath,

          p_bucket_id:
            ISSUED_DOCUMENTS_BUCKET,

          p_template_key:
            template
              .templateKey,

          p_template_version:
            template
              .templateVersion,

          p_certificate_id:
            identity
              ?.certificateId ??
            null,

          p_certificate_verification_url:
            identity
              ?.verificationUrl ??
            null,
        },
      );

      if (generationError) {
        throw generationError;
      }

      const {
        error: emailBoundaryError,
      } = await admin.rpc(
        "mark_exit_document_email_attempt_fenced",
        {
          p_job_id:
            jobId,
          p_claim_attempt_count:
            claimAttemptCount,
        },
      );

      if (emailBoundaryError) {
        throw emailBoundaryError;
      }

      const name =
        template
            .variant
            .includes("LOR")
          ? "Letter of Recommendation"
          : "Internship Certificate";

      let gmail:
        { messageId: string };

      try {
        gmailInvocationStarted =
          true;

        gmail =
          await sendEmailWithGmailAttachment(
            candidate.email,
            {
              subject:
                `${name} – Jarurat Care Foundation`,

              text:
                `Dear ${candidate.full_name},\n\nYour ${name} is attached.`,

              html:
                `<p>Dear ${candidate.full_name},</p><p>Your ${name} is attached.</p>`,
            },
            {
              filename:
                `${template.templateKey}.pdf`,

              contentType:
                "application/pdf",

              content:
                pdf,
            },
          );
      } catch (error) {
        const gmailError =
          isGmailProviderError(
            error,
          );

        const providerOutcome:
          ProviderOutcome =
            gmailError &&
              error
                .deliveryOutcome ===
                "NOT_SENT"
              ? "NOT_STARTED"
              : "UNKNOWN";

        const retryable =
          providerOutcome ===
              "NOT_STARTED" &&
            gmailError
            ? error.retryable
            : false;

        await recordFailureSafely(
          admin,
          jobId,
          claimAttemptCount,
          errorMessageOf(
            error,
            "Email delivery failed.",
          ),
          retryable,
          providerOutcome,
        );

        return json(
          {
            status:
              providerOutcome ===
                  "UNKNOWN"
                ? "EMAIL_OUTCOME_RECONCILIATION_REQUIRED"
                : "GENERATED",

            emailPending:
              true,
          },
          202,
        );
      }

      const {
        error:
          providerAcceptanceError,
      } = await admin.rpc(
        "record_exit_document_provider_acceptance_fenced",
        {
          p_job_id:
            jobId,
          p_claim_attempt_count:
            claimAttemptCount,
          p_gmail_message_id:
            gmail.messageId,
        },
      );

      if (
        providerAcceptanceError
      ) {
        console.error(
          "Gmail accepted the Exit-document email but provider evidence could not be persisted.",
          providerAcceptanceError,
        );

        await recordFailureSafely(
          admin,
          jobId,
          claimAttemptCount,
          errorMessageOf(
            providerAcceptanceError,
            "Gmail accepted the email but provider evidence could not be recorded.",
          ),
          false,
          "UNKNOWN",
        );

        return json(
          {
            status:
              "EMAIL_ACCEPTED_RECONCILIATION_REQUIRED",
            emailPending:
              true,
          },
          202,
        );
      }

      providerAcceptanceRecorded =
        true;

      const {
        error: emailError,
      } = await admin.rpc(
        "complete_exit_document_email_fenced",
        {
          p_job_id:
            jobId,
          p_claim_attempt_count:
            claimAttemptCount,
          p_gmail_message_id:
            gmail.messageId,
        },
      );

      if (emailError) {
        console.error(
          "Gmail provider acceptance was recorded but final Exit-document email completion failed.",
          emailError,
        );

        await recordFailureSafely(
          admin,
          jobId,
          claimAttemptCount,
          errorMessageOf(
            emailError,
            "Email was accepted by Gmail but final database completion failed.",
          ),
          false,
          "ACCEPTED",
        );

        return json(
          {
            status:
              "EMAIL_ACCEPTED_RECONCILIATION_REQUIRED",
            emailPending:
              true,
          },
          202,
        );
      }

      return json({
        status: "EMAILED",
        document:
          Array.isArray(
            completion,
          )
            ? completion[0] ??
              null
            : null,
      });
    } catch (error) {
      console.error(
        "Exit-document worker generation failed:",
        error,
      );

      if (
        error &&
        typeof error === "object"
      ) {
        try {
          console.error(
            "Detailed Error Object:",
            JSON.stringify(
              error,
              Object.getOwnPropertyNames(
                error,
              ),
            ),
          );
        } catch {
          console.error(
            "Detailed Error Object (non-serializable):",
            error,
          );
        }
      }

      if (
        error instanceof Error &&
        error.stack
      ) {
        console.error(
          "Error stack trace:",
          error.stack,
        );
      }

      if (claimAttemptCount !== null) {
        const providerOutcome:
          ProviderOutcome =
            providerAcceptanceRecorded
              ? "ACCEPTED"
              : gmailInvocationStarted
              ? "UNKNOWN"
              : "NOT_STARTED";

        await recordFailureSafely(
          admin,
          jobId,
          claimAttemptCount,
          errorMessageOf(
            error,
            "Document generation failed.",
          ),
          providerOutcome ===
            "NOT_STARTED",
          providerOutcome,
        );
      }

      return json(
        {
          error:
            "Exit-document processing failed.",
        },
        500,
      );
    }
  },
);

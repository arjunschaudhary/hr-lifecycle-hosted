# HR Lifecycle V1 Status Values

## Purpose

This document defines the initial status values used in the HR Lifecycle Module V1. These statuses will be used across dummy data, React screens, Supabase tables, and workflow testing.

---

## Candidate Status

Candidate status represents the overall lifecycle stage of a candidate/intern.

| Status | Meaning |
|---|---|
| FORM_SUBMITTED | Candidate has submitted the public form |
| HR_REVIEW_PENDING | Candidate form is waiting for HR review |
| HR_APPROVED_FOR_PROBATION | HR approved the candidate to start probation |
| PROBATION_INITIATED | Probation process has been initiated |
| WELCOME_MAIL_SENT | Welcome/probation mail has been sent |
| IN_PROBATION | Candidate is currently in probation |
| PROBATION_REVIEW | Candidate probation is ready for HR review |
| PROBATION_PASSED | Candidate passed probation |
| PROBATION_REJECTED | Candidate was rejected during probation review |
| PROBATION_EXTENDED | Candidate probation was extended |
| RECONSIDERATION | Candidate is being reconsidered through a new probation attempt |
| MID_GENERATED | MID has been generated |
| OFFER_LETTER_GENERATED | Offer letter has been generated |
| OFFER_LETTER_SENT | Offer letter has been sent to the candidate |
| ACTIVE | Candidate has become an active intern |
| COMPLETED | Internship has been completed |
| TERMINATED | Internship was ended before completion |
---

## Probation Status

Probation status tracks each probation attempt separately.

| Status | Meaning |
|---|---|
| FORM_SUBMITTED | Candidate submitted the probation form |
| HR_REVIEW_PENDING | Candidate form is waiting for HR review |
| HR_APPROVED_FOR_PROBATION | HR approved candidate for probation |
| PROBATION_INITIATED | Probation has been initiated |
| WELCOME_MAIL_SENT | Welcome/probation mail has been sent |
| IN_PROBATION | Candidate is currently in probation |
| PROBATION_REVIEW | Probation is ready for HR review |
| PROBATION_PASSED | Candidate passed probation |
| PROBATION_REJECTED | Candidate did not pass probation |
| PROBATION_EXTENDED | Probation period has been extended |
| RECONSIDERATION | New attempt created after rejection |
---

## Offer Letter Status

Offer letter status tracks MID generation, offer letter generation, and email sending. There is no separate offer approval stage in V1.

| Status | Meaning |
|---|---|
| NOT_STARTED | Offer letter process has not started |
| MID_GENERATED | MID has been generated |
| OFFER_LETTER_GENERATED | Offer letter has been generated |
| OFFER_LETTER_SENT | Offer letter has been sent |
| CANCELLED | Offer letter process was cancelled |
---

## Active Intern Status

Active intern status starts after offer letter is sent.

| Status | Meaning |
|---|---|
| ACTIVE | Intern is currently active |
| COMPLETED | Internship has been completed |
| TERMINATED | Internship ended before completion |

---

## Signed Offer Status

Signed offer is handled separately from active intern status.

| Status | Meaning |
|---|---|
| NOT_SUBMITTED | Signed offer has not been submitted yet |
| SUBMITTED | Candidate submitted signed offer |
| VERIFIED | HR verified the signed offer |
| REJECTED | HR rejected the signed offer |
| RESUBMISSION_REQUIRED | Candidate needs to resubmit signed offer |

---

## Email Match Status

This is used when the signed offer is submitted.

| Status | Meaning |
|---|---|
| NOT_CHECKED | Email/phone match has not been checked |
| MATCHED | Submitted details match existing candidate record |
| MISMATCH | Submitted details do not fully match existing candidate record |

Important rule:

- Email or phone mismatch should not block active intern status.
- Mismatch should be shown as a warning in HR view and activity logs.
- HR can still verify or reject the signed offer manually.

---

## Activity Log Event Types

These event types will be used in the activity/audit log.

| Event Type | Meaning |
|---|---|
| CANDIDATE_FORM_SUBMITTED | Candidate submitted probation form |
| HR_REVIEW_PENDING | Candidate form moved to HR review |
| HR_APPROVED_FOR_PROBATION | HR approved candidate for probation |
| PROBATION_INITIATED | Probation was initiated |
| WELCOME_MAIL_SENT | Welcome/probation mail was sent |
| PROBATION_REVIEW | Probation moved to HR review |
| PROBATION_PASSED | Candidate passed probation |
| PROBATION_REJECTED | HR rejected probation |
| PROBATION_EXTENDED | Probation was extended |
| RECONSIDERATION_CREATED | New probation attempt created |
| MID_GENERATED | MID generated |
| OFFER_LETTER_GENERATED | Offer letter generated |
| OFFER_LETTER_SENT | Offer letter sent |
| INTERN_ACTIVATED | Candidate became active intern |
| SIGNED_OFFER_SUBMITTED | Signed offer submitted |
| SIGNED_OFFER_MISMATCH_REVIEW | Signed offer submitted with email/phone mismatch |
| SIGNED_OFFER_VERIFIED | HR verified signed offer |
| SIGNED_OFFER_REJECTED | HR rejected signed offer |
---

## Notes for V1

- Candidate form will be public in V1.
- HR login will be required for review and approval actions.
- Candidate login and Team Lead login can be added in later phases.
- Supabase Row Level Security can be designed later after roles and permissions are finalized.

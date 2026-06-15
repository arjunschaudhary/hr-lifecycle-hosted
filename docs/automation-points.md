HR Lifecycle V1 Automation Points

Purpose

This document defines the automation points for the HR Lifecycle Module V1.

The goal is to clearly identify where automation should happen in the lifecycle, what should trigger it, what the system should update, and what should be logged.

This version follows the corrected V1 workflow where there is no separate “Offer Approval” stage after probation.

---

Corrected V1 Workflow

Form Submitted
↓
HR Review Pending
↓
HR Approved for Probation
↓
Probation Initiated
↓
Welcome Mail Sent
↓
In Probation
↓
Probation Review
↓
HR Decision:
   - Probation Passed
   - Probation Rejected
   - Probation Extended
↓
If Probation Passed:
   MID Generated
   ↓
   Offer Letter Generated
   ↓
   Offer Letter Sent
   ↓
   Active Intern
↓
Signed Offer Submitted
↓
HR Verification:
   - Verified
   - Rejected
   - Email/Phone Mismatch Review

---

Important V1 Rule

There is no separate “Offer Letter Generated” stage in Version 1.

Once HR marks probation as passed, the system should automatically start the offer letter process:

Probation Passed
↓
MID Generated
↓
Offer Letter Generated
↓
Offer Letter Sent
↓
Active Intern

HR should not approve the same candidate again after probation has already been passed.

---

Automation 1: Candidate Form Submission

Trigger

Candidate submits the public probation form.

System Actions

- Create a candidate record.
- Set candidate status to "HR_REVIEW_PENDING".
- Store candidate source as "candidate_form".
- Create an activity log entry.
- Do not start probation automatically.
- Do not generate MID.
- Do not generate offer letter.

Status Update

FORM_SUBMITTED
↓
HR_REVIEW_PENDING

Activity Log

CANDIDATE_FORM_SUBMITTED

Notes

The candidate form submission should only create the candidate record and place it in HR review.

Probation should begin only after HR approves the candidate for probation.

---

Automation 2: HR Review of Submitted Form

Trigger

HR reviews the candidate form submission.

Possible HR Decisions

Approve for Probation
Reject / Hold

System Actions if HR Approves

- Update candidate status to "HR_APPROVED_FOR_PROBATION".
- Create activity log entry.
- Prepare candidate for probation initiation.

Status Update

HR_REVIEW_PENDING
↓
HR_APPROVED_FOR_PROBATION

Activity Log

HR_APPROVED_FOR_PROBATION

Notes

This stage is only for approving the candidate to enter probation.

It is not the same as probation passed.

---

Automation 3: Probation Initiation

Trigger

Candidate is approved by HR for probation.

System Actions

- Create probation attempt record.
- Set probation attempt status to "PROBATION_INITIATED".
- Set candidate status to "PROBATION_INITIATED".
- Set probation start date.
- Set probation end date.
- Create activity log entry.

Status Update

HR_APPROVED_FOR_PROBATION
↓
PROBATION_INITIATED

Activity Log

PROBATION_INITIATED

Notes

This stage starts the probation process.

---

Automation 4: Welcome Mail Sent

Trigger

Probation is initiated.

System Actions

- Send welcome/probation email to candidate.
- Update candidate status to "WELCOME_MAIL_SENT".
- Update probation attempt status to "WELCOME_MAIL_SENT".
- Create notification record.
- Create activity log entry.

Status Update

PROBATION_INITIATED
↓
WELCOME_MAIL_SENT
↓
IN_PROBATION

Activity Log

WELCOME_MAIL_SENT

Notification Type

PROBATION_START_EMAIL

Notes

After welcome mail is sent, the candidate is considered to be in probation.

---

Automation 5: In Probation

Trigger

Welcome mail is sent successfully.

System Actions

- Update candidate status to "IN_PROBATION".
- Update probation attempt status to "IN_PROBATION".
- Track probation duration.
- Prepare candidate for later HR review.

Status Update

WELCOME_MAIL_SENT
↓
IN_PROBATION

Notes

This is the active probation stage.

---

Automation 6: Probation Review Reminder

Trigger

Probation end date is reached or probation is due for review.

System Actions

- Move probation attempt to "PROBATION_REVIEW".
- Notify HR that candidate is ready for review.
- Create activity log entry.

Status Update

IN_PROBATION
↓
PROBATION_REVIEW

Activity Log

PROBATION_REVIEW

Notes

This automation helps HR know which candidates need review after probation.

---

Automation 7: HR Probation Decision

Trigger

HR reviews candidate probation.

HR Decision Options

Probation Passed
Probation Rejected
Probation Extended

---

Case 1: Probation Passed

System Actions

- Update probation attempt status to "PROBATION_PASSED".
- Update candidate status to "PROBATION_PASSED".
- Store reviewed_by and reviewed_at.
- Store HR remarks.
- Create activity log entry.
- Automatically trigger MID generation.
- Automatically trigger offer letter generation.
- Automatically trigger offer letter sending.

Status Update

PROBATION_REVIEW
↓
PROBATION_PASSED

Activity Log

PROBATION_PASSED

Important Rule

Probation passed directly starts the offer letter process.

There is no separate Post-Probation offer approval stage in V1.

---

Case 2: Probation Rejected

System Actions

- Update probation attempt status to "PROBATION_REJECTED".
- Update candidate status to "PROBATION_REJECTED".
- Store reviewed_by and reviewed_at.
- Store HR remarks.
- Create activity log entry.

Status Update

PROBATION_REVIEW
↓
PROBATION_REJECTED

Activity Log

PROBATION_REJECTED

---

Case 3: Probation Extended

System Actions

- Update probation attempt status to "PROBATION_EXTENDED".
- Update candidate status to "PROBATION_EXTENDED".
- Store extension reason.
- Store new probation end date.
- Create activity log entry.

Status Update

PROBATION_REVIEW
↓
PROBATION_EXTENDED

Activity Log

PROBATION_EXTENDED

---

Automation 8: Reconsideration Flow

Trigger

HR decides to reconsider a rejected candidate.

System Actions

- Create a new probation attempt.
- Increase attempt number.
- Set candidate status to "RECONSIDERATION".
- Set new probation attempt status to "RECONSIDERATION".
- Create activity log entry.

Status Update

PROBATION_REJECTED
↓
RECONSIDERATION
↓
IN_PROBATION

Activity Log

RECONSIDERATION_CREATED

Notes

This allows HR to give a candidate another probation attempt after rejection.

---

Automation 9: Automatic MID Generation

Trigger

Probation is marked as passed.

System Actions

- Generate MID using the approved MID format.
- Create or update MID registry record.
- Update candidate status to "MID_GENERATED".
- Update offer status to "MID_GENERATED".
- Create activity log entry.

MID Format

ROLE_CODE / NAME_CODE / SERIAL

Example

AU/AS/001
AU/AS/002
HR/KA/001

Status Update

PROBATION_PASSED
↓
MID_GENERATED

Activity Log

MID_GENERATED

Important Rule

MID should be generated automatically after probation is passed.

MID should not require a separate offer approval step.

---

Automation 10: Automatic Offer Letter Generation

Trigger

MID has been generated.

System Actions

- Generate offer letter from template.
- Fill candidate details.
- Fill MID.
- Fill role details.
- Fill start date and end date.
- Fill duration.
- Generate PDF or document link.
- Update offer status to "OFFER_LETTER_GENERATED".
- Update candidate status to "OFFER_LETTER_GENERATED".
- Create activity log entry.

Status Update

MID_GENERATED
↓
OFFER_LETTER_GENERATED

Activity Log

OFFER_LETTER_GENERATED

Notes

This is where the offer letter document is prepared.

---

Automation 11: Automatic Offer Letter Sending

Trigger

Offer letter is generated successfully.

System Actions

- Send offer letter to candidate by email.
- Update offer status to "OFFER_LETTER_SENT".
- Update candidate status to "OFFER_LETTER_SENT".
- Store offerLetterSentAt.
- Create notification record.
- Create activity log entry.
- Trigger active intern creation.

Status Update

OFFER_LETTER_GENERATED
↓
OFFER_LETTER_SENT

Activity Log

OFFER_LETTER_SENT

Notification Type

OFFER_LETTER_EMAIL

Notes

Candidate becomes eligible to be moved to Active Intern after the offer letter is sent.

---

Automation 12: Active Intern Creation

Trigger

Offer letter is sent successfully.

System Actions

- Create active intern record.
- Update candidate status to "ACTIVE".
- Store active start date.
- Store department/team/project details.
- Create activity log entry.

Status Update

OFFER_LETTER_SENT
↓
ACTIVE

Activity Log

INTERN_ACTIVATED

Important Rule

Candidate becomes active after offer letter is sent.

Signed offer submission should not block active intern status in V1.

---

Automation 13: Signed Offer Submission

Trigger

Candidate submits signed offer letter.

System Actions

- Create signed offer submission record.
- Store submitted email.
- Store submitted phone.
- Store uploaded file link.
- Store submittedAt.
- Set signed offer status to "SUBMITTED".
- Create activity log entry.
- Trigger email/phone match check.

Status Update

ACTIVE
↓
SIGNED_OFFER_SUBMITTED

Activity Log

SIGNED_OFFER_SUBMITTED

Notes

Signed offer is collected after the candidate is already active.

---

Automation 14: Email and Phone Match Check

Trigger

Signed offer is submitted.

System Actions

- Compare submitted email with registered email.
- Compare submitted phone with registered phone.
- Mark emailMatchStatus as "MATCHED" or "MISMATCH".
- Mark phoneMatchStatus as "MATCHED" or "MISMATCH".
- If mismatch is found, move signed offer to mismatch review.
- Create activity log entry.

Match Status Values

MATCHED
MISMATCH
MISMATCH_REVIEW

Activity Log if Mismatch Found

SIGNED_OFFER_MISMATCH_REVIEW

Notes

Mismatch should show warning to HR.

Mismatch should not remove the candidate from active intern status.

---

Automation 15: HR Signed Offer Verification

Trigger

HR reviews submitted signed offer.

HR Decision Options

Verified
Rejected
Mismatch Review

---

Case 1: Signed Offer Verified

System Actions

- Update signed offer status to "VERIFIED".
- Store verified_by and verified_at.
- Create activity log entry.

Activity Log

SIGNED_OFFER_VERIFIED

---

Case 2: Signed Offer Rejected

System Actions

- Update signed offer status to "REJECTED".
- Store rejection reason.
- Mark resubmissionRequired as true.
- Notify candidate for resubmission.
- Create activity log entry.

Activity Log

SIGNED_OFFER_REJECTED

Notification Type

SIGNED_OFFER_REJECTED

---

Case 3: Mismatch Review

System Actions

- Keep signed offer status under review.
- Show mismatch warning to HR.
- Allow HR to verify manually or reject.
- Create activity log entry.

Activity Log

SIGNED_OFFER_MISMATCH_REVIEW

---

Automation 16: Notification Logging

Trigger

Any email or notification is sent or scheduled.

System Actions

- Create notification record.
- Store candidateId.
- Store notification type.
- Store recipient email.
- Store subject.
- Store message.
- Store status.
- Store sentAt if sent.

Notification Types

PROBATION_START_EMAIL
OFFER_LETTER_EMAIL
SIGNED_OFFER_RECEIVED
SIGNED_OFFER_REJECTED

Notification Status Values

PENDING
SENT
FAILED

---

Automation 17: Activity Logging

Trigger

Any important lifecycle event happens.

System Actions

- Create activity log entry.
- Store candidateId.
- Store actionType.
- Store performedBy.
- Store oldStatus.
- Store newStatus.
- Store remarks.
- Store createdAt.

Important Activity Events

CANDIDATE_FORM_SUBMITTED
HR_REVIEW_PENDING
HR_APPROVED_FOR_PROBATION
PROBATION_INITIATED
WELCOME_MAIL_SENT
PROBATION_REVIEW
PROBATION_PASSED
PROBATION_REJECTED
PROBATION_EXTENDED
RECONSIDERATION_CREATED
MID_GENERATED
OFFER_LETTER_GENERATED
OFFER_LETTER_SENT
INTERN_ACTIVATED
SIGNED_OFFER_SUBMITTED
SIGNED_OFFER_MISMATCH_REVIEW
SIGNED_OFFER_VERIFIED
SIGNED_OFFER_REJECTED

---

Automation Summary Table

Stage| Trigger| Main Output
Candidate form submission| Candidate submits form| Candidate moves to HR review
HR review| HR approves candidate| Candidate approved for probation
Probation initiation| HR approval for probation| Probation attempt starts
Welcome mail| Probation initiated| Candidate enters probation
Probation review| Probation period ends| Candidate ready for HR decision
Probation passed| HR passes candidate| MID and offer letter process starts
MID generation| Probation passed| MID created
Offer letter generation| MID generated| Offer letter created
Offer letter sending| Offer letter generated| Offer sent to candidate
Active intern creation| Offer letter sent| Candidate becomes active
Signed offer submission| Candidate submits signed offer| HR verification starts
Match check| Signed offer submitted| Email/phone match warning if needed
Signed offer verification| HR reviews signed offer| Verified / rejected / mismatch review
Activity logging| Any lifecycle event| Audit trail created
Notification logging| Any email/notification| Communication history created

---

Key Business Rules

Rule 1: No Separate Offer Approval

There is no separate offer approval stage in V1.

Do not use this flow:

Probation Passed
↓
Offer Approved

Use this flow:

Probation Passed
↓
MID Generated
↓
Offer Letter Generated
↓
Offer Letter Sent

---

Rule 2: HR Decision After Probation

After probation review, HR should only choose:

Probation Passed
Probation Rejected
Probation Extended

---

Rule 3: MID Generation

MID should be generated only after probation is passed.

MID should not be generated at form submission stage.

---

Rule 4: Active Intern Status

Candidate becomes active after offer letter is sent.

Signed offer submission should not block active intern status in V1.

---

Rule 5: Signed Offer Verification

Signed offer verification is important for record completion and future certificate/LOR eligibility.

But signed offer verification should not remove or block active intern status.

---

Rule 6: Mismatch Handling

Email or phone mismatch should create a warning for HR.

Mismatch should go to HR review.

Mismatch should not automatically reject the signed offer.

---

Future Automation Scope

The following can be added after V1 is stable:

- Real email integration
- Offer letter PDF generation
- Supabase database triggers
- Supabase Storage or Google Drive integration
- Candidate login
- Candidate dashboard
- Certificate/LOR eligibility checks
- Leave and performance automation
- Team lead dashboard
- Role-based notifications

---

V1 Focus

Version 1 should first prove this flow:

Candidate form
↓
HR review
↓
Probation
↓
Probation passed
↓
MID generated
↓
Offer letter generated
↓
Offer letter sent
↓
Active intern
↓
Signed offer submitted
↓
Signed offer verified/rejected

Once this flow works correctly with dummy data, the same structure can later connect to Supabase.
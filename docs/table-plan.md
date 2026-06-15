HR Lifecycle V1 Table Plan

Purpose

This document defines the initial table structure required for the HR Lifecycle Module V1.

The HR Lifecycle module will first work with dummy data inside the React project. Later, once the company-wide master Supabase database is finalized, these HR module tables can be connected with the master tables.

The purpose of this document is to clearly separate:

1. Common/master tables that will come from the main company database.
2. HR Lifecycle module-specific tables that are required for our workflow.

---

Master Tables Required From Common Database

The HR Lifecycle module will depend on these common/master tables once the final master Supabase database is ready.

Master Table| Purpose in HR Module
users / profiles| HR users, Team Leads, Project Managers, POD Leads, Admin users
roles| Defines user roles or designations
permissions| Defines what actions each role can perform
departments| Used for candidate/intern department mapping
teams| Used for intern team assignment
projects| Used for project assignment after activation
resources / media| Used for file references, documents, uploaded resources

Until the master database is finalized, dummy master data will be used for testing.

---

HR Module Tables

1. hr_candidates

Purpose

Stores candidate/intern personal and application-level information.

This table is the main HR module record for a candidate. A candidate can start from a public probation form, HR manual entry, or later from the Stage 0 / Assignment module.

Fields

Field| Purpose
id| Unique candidate ID
full_name| Candidate full name
email| Candidate registered email
phone| Candidate phone number
address| Candidate address
role_applied_for| Internship role applied for
role_code| Short role code used for MID generation
department_id| Linked department from master table
team_id| Linked team from master table
project_id| Linked project from master table
created_source| Source of candidate creation
current_status| Current lifecycle status
created_at| Record creation date
updated_at| Last update date

created_source values

Value| Meaning
candidate_form| Candidate submitted the public probation form
hr_manual| HR created the candidate manually
stage0_import| Candidate came from Assignment / Stage 0 module

Important Rules

- Candidate form will be public in V1.
- HR can also manually create a candidate if needed.
- Later, Stage 0 / Assignment module can send candidate data into this table.
- Candidate email and phone should be used for matching signed offer submissions.

---

2. hr_probation_attempts

Purpose

Stores probation cycles.

One candidate can have multiple probation attempts. This is important because a rejected candidate can be reconsidered later without deleting or overwriting the old probation record.

Fields

Field| Purpose
id| Unique probation attempt ID
candidate_id| Linked candidate
attempt_no| Probation attempt number
probation_start_date| Probation start date
probation_end_date| Probation end date
status| Probation status
reviewed_by| HR user who reviewed the probation
reviewed_at| Review date/time
hr_remarks| HR review remarks
extension_reason| Reason if probation is extended
created_at| Record creation date
updated_at| Last update date

Important Rules

- Default probation duration is 7 days.
- HR can approve, reject, or extend probation.
- If a rejected candidate is reconsidered, create a new probation attempt.
- Previous probation attempts should remain stored for history.
- Probation approval does not directly generate the offer letter. HR offer approval happens after probation approval.

---

3. hr_offer_letters

Purpose

Stores offer approval, MID, offer PDF, and offer email status.

This table starts after probation is approved and HR approves the offer process.

Fields

Field| Purpose
id| Unique offer letter ID
candidate_id| Linked candidate
probation_attempt_id| Linked probation attempt
mid| Generated MID
role| Role mentioned in offer letter
role_code| Role code used for MID
start_date| Internship start date
end_date| Internship end date
duration_months| Internship duration
weekly_hours| Weekly time commitment
offer_status| Current offer status
approved_by| HR user who approved offer
approved_at| Offer approval date/time
pdf_url| Google Drive PDF link
offerlettersentat| Offer email sent date/time
created_at| Record creation date
updated_at| Last update date

Important Rules

- MID is generated only after HR approves the offer process.
- Offer letter PDF will be generated automatically later.
- For V1, offer letter PDFs can be stored in Google Drive.
- Supabase will store the PDF link and status.
- Candidate becomes an active intern after the offer email is sent.

---

4. hr_mid_registry

Purpose

Maintains MID generation history and prevents duplicate MID serials.

This table is required because MID generation has a specific business rule.

Fields

Field| Purpose
id| Unique MID registry ID
candidate_id| Linked candidate
role_code| Role code
name_code| Candidate name code
serial_no| Serial number
mid| Final generated MID
generated_for_offer_id| Linked offer letter
generated_at| MID generation date/time

MID Format

ROLE_CODE / NAME_CODE / SERIAL

Examples

Candidate| Role Code| Name Code| MID
Aarav Sharma| AU| AS| AU/AS/001
Aditya Sharad| AU| AS| AU/AS/002
Riya Patel| AU| RP| AU/RP/001
Karan| HR| KA| HR/KA/001

Important Rules

- Serial should increase only for the same role_code + name_code combination.
- Name code can be created from initials if the candidate has first and last name.
- If the candidate has a single name, use the first two letters.
- MID should not be generated before HR offer approval.

---

5. hr_active_interns

Purpose

Stores active intern stage after the offer letter is sent.

This table starts after the candidate becomes an active intern.

Fields

Field| Purpose
id| Unique active intern ID
candidate_id| Linked candidate
offer_id| Linked offer letter
mid| Intern MID
active_start_date| Date intern became active
department_id| Linked department
team_id| Linked team
project_id| Linked project
assigned_team_lead_id| Linked team lead user
status| Active intern status
created_at| Record creation date
updated_at| Last update date

Important Rules

- Candidate becomes active after offer letter email is sent.
- Signed offer verification does not block active intern status.
- Team/project assignment can be added after activation.
- Later, this table can connect with leave, performance, certificate, and LOR modules.

---

6. hr_signed_offers

Purpose

Tracks signed offer submission and HR verification.

Signed offer is a separate process from offer letter generation and active intern status.

Fields

Field| Purpose
id| Unique signed offer ID
candidate_id| Linked candidate
offer_id| Linked offer letter
mid| Candidate MID
submitted_email| Email used during signed offer submission
registered_email| Candidate registered email
submitted_phone| Phone used during signed offer submission
registered_phone| Candidate registered phone
file_url| Signed offer file link
email_match_status| Email match result
phone_match_status| Phone match result
status| Signed offer status
submitted_at| Submission date/time
verified_by| HR user who verified/rejected
verified_at| Verification date/time
rejection_reason| Reason if rejected
resubmission_required| Whether resubmission is required
created_at| Record creation date
updated_at| Last update date

Important Rules

- Signed offer should be stored separately from offer letter.
- Signed offer can be submitted after the offer email is sent.
- Candidate may submit signed offer using a different email or phone.
- Email/phone mismatch should not block active status.
- Mismatch should appear as a warning in HR view and activity log.
- HR can verify or reject signed offer manually.
- If rejected, candidate can be asked to resubmit.
- Signed offer status will matter later for certificate/LOR eligibility.

---

7. hr_activity_logs

Purpose

Maintains audit/activity history for important lifecycle actions.

This table helps track what happened, when it happened, and who performed the action.

Fields

Field| Purpose
id| Unique activity log ID
candidate_id| Linked candidate
action_type| Type of action performed
performed_by| User/system who performed the action
old_status| Previous status
new_status| New status
remarks| Notes or reason
created_at| Action date/time

Example Activity Events

Event Type| Meaning
CANDIDATE_FORM_SUBMITTED| Candidate submitted probation form
PROBATION_STARTED| Probation started
PROBATION_PASSED| HR approved probation
PROBATION_REJECTED| HR rejected probation
PROBATION_EXTENDED| HR extended probation
OFFER_LETTER_GENERATED| HR approved offer
MID_GENERATED| MID generated
OFFER_LETTER_GENERATED| Offer PDF generated
OFFER_EMAIL_SENT| Offer email sent
INTERN_ACTIVATED| Candidate became active intern
SIGNED_OFFER_SUBMITTED| Signed offer submitted
SIGNED_OFFER_EMAIL_MISMATCH| Signed offer submitted with mismatch
SIGNED_OFFER_VERIFIED| HR verified signed offer
SIGNED_OFFER_REJECTED| HR rejected signed offer

Important Rules

- Major status changes should create an activity log.
- Email/phone mismatch should be visible in the activity log.
- HR remarks should be stored where needed.
- Activity logs should help with audit and review.

---

8. hr_notifications

Purpose

Tracks email/system notification events.

This table is useful because emails and notifications may be automated later through Apps Script, n8n, Supabase Edge Functions, or another automation tool.

Fields

Field| Purpose
id| Unique notification ID
candidate_id| Linked candidate
notification_type| Type of notification
recipient_email| Recipient email
subject| Notification subject
message| Notification content
status| Pending/sent/failed
sent_at| Sent date/time
created_at| Record creation date

Notification Examples

Notification Type| Trigger
PROBATION_START_EMAIL| Candidate submits probation form
PROBATION_REVIEW_REMINDER| Probation end date is reached
OFFER_LETTER_EMAIL| Offer letter PDF is generated
SIGNED_OFFER_RECEIVED| Candidate submits signed offer
SIGNED_OFFER_REJECTED| HR rejects signed offer
SIGNED_OFFER_VERIFIED| HR verifies signed offer

Important Rules

- Notification table should track what needs to be sent and what has already been sent.
- For V1, actual email automation may be handled later.
- Supabase can store notification status, while Apps Script/n8n can perform email sending.

---

V1 Implementation Approach

Phase 1: Dummy Data and React Screens

The HR module will first work with dummy data and React screens.

This allows the team to build and test the workflow without waiting for the final master Supabase database.

Phase 2: Supabase Table Connection

Once table structure is reviewed and approved, HR module tables can be created in Supabase.

Recommended HR table naming:

- hr_candidates
- hr_probation_attempts
- hr_offer_letters
- hr_mid_registry
- hr_active_interns
- hr_signed_offers
- hr_activity_logs
- hr_notifications

Phase 3: Master Database Integration

Once the company-wide master database is finalized:

- HR module user references will connect to master users/profiles.
- HR module roles will connect to master roles.
- Department, team, and project references will connect to master tables.
- File/resource references can connect to the master resources/media table.

Phase 4: Automation Integration

Automation can be added after the core workflow is stable.

Possible automation tools:

- Supabase Edge Functions
- Google Apps Script
- n8n
- Make.com

For V1, the preferred practical option is:

1. Supabase stores HR data and status.
2. Google Apps Script or n8n generates offer letter PDF.
3. Google Drive stores offer letter PDF.
4. Gmail sends email.
5. Supabase stores PDF link and email status.

---

Notes for V1

- Candidate probation form will be public in V1.
- HR login will be required for review and approval.
- Candidate login can be added later.
- Team Lead login can be added later.
- Supabase Row Level Security can be designed after roles and permissions are finalized.
- Leave, performance, certificate, LOR, extension, and awards are not part of the immediate V1 core flow.
- Signed offer verification will not block active intern status.
- Signed offer status will be important later for certificate and LOR eligibility.

---

Summary

The HR Lifecycle Module V1 will start with a dummy-data-based React workflow.

The main flow is:

Candidate Probation Form → Probation Review → Offer Approval → MID Generation → Offer Letter Sent → Active Intern → Signed Offer Submission → HR Verification/Rejection.

This table plan is designed to work independently during development and later connect with the company-wide Supabase master database.

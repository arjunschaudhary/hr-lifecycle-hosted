HR Lifecycle V1 Dummy Data Plan

Purpose

This document defines the dummy data required for testing the HR Lifecycle Module V1.

Before connecting the module with the final Supabase master database, we will use dummy data inside the React project to test screens, workflow movement, status changes, and edge cases.

Dummy data will help us test:

- Candidate probation form submission
- Probation approval, rejection, and extension
- Reconsideration after rejection
- Offer approval
- MID generation
- Offer letter status
- Active intern creation
- Signed offer submission
- Signed offer mismatch warning
- Signed offer verification or rejection
- Activity log events

---

Dummy Master Data

These records represent temporary master data until the final company-wide Supabase master database is ready.

Dummy Users

User ID| Name| Role| Email| Purpose
USER-001| Priya HR| HR Executive| priya.hr@example.com| Reviews probation and offer approvals
USER-002| Rohan HR Lead| HR Lead| rohan.lead@example.com| Final HR review and override authority
USER-003| Neha Team Lead| Team Lead| neha.tl@example.com| Assigned team lead for active interns
USER-004| Aman PM| Project Manager| aman.pm@example.com| Project-level visibility
USER-005| System Admin| System Admin| admin@example.com| System/admin testing

---

Dummy Roles

Role ID| Role Name| Purpose
ROLE-001| Candidate| Public candidate submitting probation form
ROLE-002| HR Executive| Handles probation review and offer processing
ROLE-003| HR Lead| Handles final approvals and escalation
ROLE-004| Team Lead| Views assigned interns later
ROLE-005| Project Manager| Views project-level intern data later
ROLE-006| POD Lead| Views POD-level data later
ROLE-007| System Admin| Full access for testing/admin

---

Dummy Departments

Department ID| Department Name
DEPT-001| Human Resources
DEPT-002| Technology
DEPT-003| Operations
DEPT-004| Marketing
DEPT-005| Data / Analytics

---

Dummy Teams

Team ID| Team Name| Department
TEAM-001| HR Operations Team| Human Resources
TEAM-002| Automation Team| Technology
TEAM-003| Operations Support Team| Operations
TEAM-004| Marketing Support Team| Marketing
TEAM-005| Data Review Team| Data / Analytics

---

Dummy Projects

Project ID| Project Name| Purpose
PROJ-001| HR Lifecycle Module| HR probation to active intern workflow
PROJ-002| Assignment Module| Stage 0 / assignment workflow
PROJ-003| Project Tracking Module| Notion-like project/task tracking
PROJ-004| Automation Workflow Support| Future automation-related work

---

Dummy Candidate Cases

Case 1: Normal Probation Ongoing

Field| Value
Candidate ID| CAND-001
Full Name| Aarav Sharma
Email| aarav.sharma@example.com
Phone| 9876543210
Role Applied For| Automation Intern
Role Code| AU
Department| Technology
Created Source| candidate_form
Candidate Status| PROBATION
Probation Status| PROBATION_STARTED

Expected Flow:

Candidate has submitted the probation form and probation has started. HR has not reviewed yet.

---

Case 2: Probation Rejected

Field| Value
Candidate ID| CAND-002
Full Name| Riya Patel
Email| riya.patel@example.com
Phone| 9876543211
Role Applied For| HR Intern
Role Code| HR
Department| Human Resources
Created Source| candidate_form
Candidate Status| REJECTED
Probation Status| REJECTED

Expected Flow:

Candidate completed probation but HR rejected the candidate with remarks.

---

Case 3: Reconsidered Candidate

Field| Value
Candidate ID| CAND-002
Full Name| Riya Patel
Email| riya.patel@example.com
Phone| 9876543211
Role Applied For| HR Intern
Role Code| HR
Candidate Status| RECONSIDERATION
Probation Attempt| Attempt 2

Expected Flow:

The same candidate was rejected earlier but is being reconsidered through a new probation attempt.

Important Rule:

Do not overwrite the previous rejected probation attempt. Create a new probation attempt.

---

Case 4: Offer Letter Generated, MID Pending

Field| Value
Candidate ID| CAND-003
Full Name| Aditya Sharad
Email| aditya.sharad@example.com
Phone| 9876543212
Role Applied For| Automation Intern
Role Code| AU
Department| Technology
Candidate Status| OFFER_LETTER_GENERATED
Probation Status| APPROVED
Offer Status| APPROVED

Expected Flow:

Probation is approved and HR has approved the offer process. MID should be generated next.

Expected MID:

AU/AS/001 or AU/AS/002 depending on previous MID records.

---

Case 5: Active Intern

Field| Value
Candidate ID| CAND-004
Full Name| Karan
Email| karan@example.com
Phone| 9876543213
Role Applied For| HR Intern
Role Code| HR
Department| Human Resources
Candidate Status| ACTIVE
Offer Status| OFFER_LETTER_SENT
Active Intern Status| ACTIVE
MID| HR/KA/001

Expected Flow:

Offer email has been sent and candidate is now an active intern.

Important Rule:

Signed offer verification is not required for active intern status.

---

Case 6: Signed Offer Submitted With Matching Details

Field| Value
Candidate ID| CAND-005
Full Name| Meera Singh
Email| meera.singh@example.com
Phone| 9876543214
Role Applied For| Operations Intern
Role Code| OP
Candidate Status| ACTIVE
Signed Offer Status| SUBMITTED
Email Match Status| MATCHED
Phone Match Status| MATCHED

Expected Flow:

Candidate submitted signed offer using the same registered email and phone. HR can verify it.

---

Case 7: Signed Offer Submitted With Email Mismatch

Field| Value
Candidate ID| CAND-006
Full Name| Neha Verma
Registered Email| neha.verma@example.com
Submitted Email| neha.alt@example.com
Registered Phone| 9876543215
Submitted Phone| 9876543215
Role Applied For| Operations Intern
Role Code| OP
Candidate Status| ACTIVE
Signed Offer Status| SUBMITTED
Email Match Status| MISMATCH
Phone Match Status| MATCHED

Expected Flow:

Candidate submitted signed offer using a different email.

Important Rule:

Email mismatch should not block active intern status. It should show a warning in HR view and create an activity log event.

---

Case 8: Signed Offer Rejected and Resubmission Required

Field| Value
Candidate ID| CAND-007
Full Name| Sameer Khan
Email| sameer.khan@example.com
Phone| 9876543216
Role Applied For| Marketing Intern
Role Code| MK
Candidate Status| ACTIVE
Signed Offer Status| REJECTED
Resubmission Required| Yes

Expected Flow:

HR rejected the submitted signed offer and candidate needs to resubmit.

---

Dummy Probation Attempts

Attempt ID| Candidate ID| Attempt No| Status| Reviewer| Remarks
PROB-001| CAND-001| 1| PROBATION_STARTED| -| Probation ongoing
PROB-002| CAND-002| 1| REJECTED| USER-001| Performance not satisfactory
PROB-003| CAND-002| 2| RECONSIDERATION| -| New attempt created
PROB-004| CAND-003| 1| APPROVED| USER-001| Candidate approved
PROB-005| CAND-004| 1| APPROVED| USER-002| Approved by HR Lead
PROB-006| CAND-008| 1| EXTENDED| USER-001| Probation extended by 3 days

---

Dummy MID Records

MID ID| Candidate| Role Code| Name Code| Serial| MID
MID-001| Aarav Sharma| AU| AS| 1| AU/AS/001
MID-002| Aditya Sharad| AU| AS| 2| AU/AS/002
MID-003| Riya Patel| AU| RP| 1| AU/RP/001
MID-004| Karan| HR| KA| 1| HR/KA/001

Important Rule:

Serial increases only for the same role_code + name_code combination.

---

Dummy Offer Records

Offer ID| Candidate ID| MID| Offer Status| PDF URL| Email Sent
OFF-001| CAND-003| AU/AS/002| APPROVED| -| No
OFF-002| CAND-004| HR/KA/001| OFFER_LETTER_SENT| Google Drive Link Placeholder| Yes
OFF-003| CAND-005| OP/MS/001| OFFER_LETTER_SENT| Google Drive Link Placeholder| Yes
OFF-004| CAND-006| OP/NV/001| OFFER_LETTER_SENT| Google Drive Link Placeholder| Yes

---

Dummy Signed Offer Records

Signed Offer ID| Candidate ID| MID| Status| Email Match| Phone Match
SO-001| CAND-005| OP/MS/001| SUBMITTED| MATCHED| MATCHED
SO-002| CAND-006| OP/NV/001| SUBMITTED| MISMATCH| MATCHED
SO-003| CAND-007| MK/SK/001| REJECTED| MATCHED| MATCHED

---

Dummy Activity Logs

Log ID| Candidate ID| Event Type| Performed By| Remarks
LOG-001| CAND-001| CANDIDATE_FORM_SUBMITTED| System| Candidate submitted probation form
LOG-002| CAND-001| PROBATION_STARTED| System| Probation started for 7 days
LOG-003| CAND-002| PROBATION_REJECTED| USER-001| Candidate rejected after review
LOG-004| CAND-002| RECONSIDERATION_CREATED| USER-002| New probation attempt created
LOG-005| CAND-003| PROBATION_PASSED| USER-001| Probation passed
LOG-006| CAND-003| OFFER_LETTER_GENERATED| USER-001| Offer approved
LOG-007| CAND-003| MID_GENERATED| System| MID generated as AU/AS/002
LOG-008| CAND-004| OFFER_LETTER_SENT| System| Offer email sent
LOG-009| CAND-004| INTERN_ACTIVATED| System| Candidate became active intern
LOG-010| CAND-006| SIGNED_OFFER_EMAIL_MISMATCH| System| Submitted email does not match registered email
LOG-011| CAND-007| SIGNED_OFFER_REJECTED| USER-001| Signed offer rejected, resubmission required

---

Dummy Data Files for React

Recommended files inside "src/data/":

- dummyUsers.js
- dummyRoles.js
- dummyDepartments.js
- dummyTeams.js
- dummyProjects.js
- dummyCandidates.js
- dummyProbationAttempts.js
- dummyOffers.js
- dummyMidRegistry.js
- dummyActiveInterns.js
- dummySignedOffers.js
- dummyActivityLogs.js
- dummyNotifications.js

---

Testing Goals

This dummy data should allow us to test:

1. HR Dashboard counts
2. Probation review list
3. Candidate detail view
4. Offer approval flow
5. MID generation display
6. Active intern list
7. Signed offer mismatch warning
8. Signed offer verification/rejection
9. Activity log timeline

---

V1 Notes

- Dummy data is temporary.
- Supabase will replace dummy data later.
- Master user/role/team/project data will come from the company-wide master database.
- HR module data will stay inside HR-specific tables.
- Dummy data should cover both normal and exception cases.

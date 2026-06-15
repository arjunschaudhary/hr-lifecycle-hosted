HR Lifecycle V1 Page Data Mapping

Purpose

This document defines which dummy data files should be used on each page of the HR Lifecycle Module V1.

The goal is to make frontend connection easier by clearly mapping:

- Which page uses which data
- What each page should display
- What actions may later be added
- Which utility files can support the page logic

---

Data Files Available

The following dummy data files are available inside "src/data/":

dummyUsers.js
dummyCandidates.js
dummyProbationAttempts.js
dummyOffers.js
dummyMidRegistry.js
dummyActiveInterns.js
dummySignedOffers.js
dummyActivityLogs.js
dummyNotifications.js

The following utility files are available inside "src/utils/":

dashboardCounts.js
midGenerator.js
statusGroups.js
lifecycleRules.js

---

1. HR Dashboard

Page File

src/pages/HRDashboard.jsx

Data Required

dummyCandidates.js
dummyProbationAttempts.js
dummyOffers.js
dummyActiveInterns.js
dummySignedOffers.js
dummyActivityLogs.js

Utility Required

dashboardCounts.js
statusGroups.js

What This Page Should Show

The HR Dashboard should show high-level summary cards.

Suggested dashboard cards:

Card| Source
Total Candidates| dummyCandidates
In Probation| dummyCandidates / dummyProbationAttempts
Probation Passed| dummyProbationAttempts
Probation Rejected| dummyProbationAttempts
Offer Letter Generated| dummyOffers
Offer Letter Sent| dummyOffers
Active Interns| dummyActiveInterns
Signed Offer Submitted| dummySignedOffers
Signed Offer Mismatch| dummySignedOffers
Signed Offer Rejected| dummySignedOffers

Page Purpose

This page acts as the main navigation and testing hub during V1 development.

For now, all modules can remain linked from the HR Dashboard.

---

2. Candidate Probation Form

Page File

src/pages/CandidateProbationForm.jsx

Data Required

This page does not need existing data initially.

It should prepare the structure for creating a new candidate record.

Fields Required

Field| Purpose
fullName| Candidate full name
email| Candidate email
phone| Candidate phone number
address| Candidate address
roleAppliedFor| Internship role
roleCode| Short code used for MID
department| Candidate department
createdSource| Source of candidate creation
consent| Candidate consent confirmation

Default Values

Field| Default
createdSource| candidate_form
currentStatus| HR_REVIEW_PENDING
probationStatus| Not created until HR approves for probation

Later Action

On form submission, the system should eventually:

1. Create candidate record.
2. Set candidate status to HR_REVIEW_PENDING.
3. Create activity log entry.
4. Wait for HR approval before probation is initiated.

For now, this can be shown as a mock success message.

---

3. Probation Review

Page File

src/pages/ProbationReview.jsx

Data Required

dummyCandidates.js
dummyProbationAttempts.js
dummyUsers.js

Utility Required

statusGroups.js
lifecycleRules.js

What This Page Should Show

This page should show candidates who are currently in probation or ready for HR review.

Suggested records to display:

- Candidates with probation status "PROBATION_STARTED"
- Candidates with probation status "UNDER_REVIEW"
- Candidates with probation status "EXTENDED"
- Candidates with probation status "RECONSIDERATION"

Main Columns

Column| Source
Candidate Name| dummyCandidates
Role Applied For| dummyCandidates
Department| dummyCandidates
Attempt No| dummyProbationAttempts
Probation Start Date| dummyProbationAttempts
Probation End Date| dummyProbationAttempts
Probation Status| dummyProbationAttempts
HR Remarks| dummyProbationAttempts

Future Actions

Action| Meaning
Pass Probation| Candidate passes probation and offer letter process starts automatically
Reject| Candidate fails probation
Extend| Probation duration is extended
Reconsider| New probation attempt is created after rejection

For V1 dummy flow, these buttons can be placeholders first.

---

4. Offer Letter Process

Page File

src/pages/OfferApproval.jsx

Data Required

dummyCandidates.js
dummyProbationAttempts.js
dummyOffers.js
dummyMidRegistry.js
dummyUsers.js

Utility Required

midGenerator.js
statusGroups.js
lifecycleRules.js

What This Page Should Show

This page should show candidates whose probation has passed and whose MID/offer letter process is ready or in progress.

Suggested records to display:

- Probation status "PROBATION_PASSED"
- Offer status "MID_GENERATED"
- Offer status "OFFER_LETTER_GENERATED"
- Offer status "OFFER_LETTER_SENT"

Main Columns

Column| Source
Candidate Name| dummyCandidates
Role| dummyCandidates / dummyOffers
Role Code| dummyCandidates / dummyOffers
Probation Status| dummyProbationAttempts
Offer Letter Status| dummyOffers
MID| dummyOffers / dummyMidRegistry
Start Date| dummyOffers
End Date| dummyOffers
PDF Link| dummyOffers
Sent Date| dummyOffers

Future Actions

Action| Meaning
Generate MID| Generate MID after probation is passed
Generate Offer Letter| Generate offer letter after MID generation
Send Offer Letter| Send offer letter to candidate

Important rule:

Candidate becomes active only after offer letter is sent.
---

5. Active Interns

Page File

src/pages/ActiveInterns.jsx

Data Required

dummyCandidates.js
dummyActiveInterns.js
dummyOffers.js
dummySignedOffers.js
dummyUsers.js

Utility Required

statusGroups.js
lifecycleRules.js

What This Page Should Show

This page should show candidates who have become active interns after offer email is sent.

Main Columns

Column| Source
Intern Name| dummyActiveInterns
MID| dummyActiveInterns
Role| dummyActiveInterns
Department| dummyActiveInterns
Team| dummyActiveInterns
Project| dummyActiveInterns
Team Lead| dummyUsers
Active Start Date| dummyActiveInterns
Active Status| dummyActiveInterns
Signed Offer Status| dummySignedOffers

Important Rule

Signed offer status should be visible but should not block active intern status.

---

6. Signed Offer Upload

Page File

src/pages/SignedOfferUpload.jsx

Data Required

dummyCandidates.js
dummyOffers.js
dummySignedOffers.js

What This Page Should Show

This page simulates candidate signed offer submission.

Fields Required

Field| Purpose
MID| Candidate MID
registeredEmail| Candidate registered email
submittedEmail| Email entered during signed offer submission
registeredPhone| Candidate registered phone
submittedPhone| Phone entered during signed offer submission
fileUrl| Signed offer file link
submittedAt| Submission date/time

Later Action

On submission, system should:

1. Create signed offer record.
2. Compare submitted email with registered email.
3. Compare submitted phone with registered phone.
4. Mark match status as "MATCHED" or "MISMATCH".
5. Create activity log entry.

For now, this can be a placeholder form.

---

7. Signed Offer Verification

Page File

src/pages/SignedOfferVerification.jsx

Data Required

dummyCandidates.js
dummySignedOffers.js
dummyOffers.js
dummyUsers.js
dummyActivityLogs.js

Utility Required

statusGroups.js
lifecycleRules.js

What This Page Should Show

This page should show signed offer submissions waiting for HR verification.

Suggested records to display:

- Signed offer status "SUBMITTED"
- Signed offer status "REJECTED"
- Signed offer status "RESUBMISSION_REQUIRED"
- Email or phone mismatch cases

Main Columns

Column| Source
Candidate Name| dummyCandidates
MID| dummySignedOffers
Registered Email| dummySignedOffers
Submitted Email| dummySignedOffers
Email Match Status| dummySignedOffers
Registered Phone| dummySignedOffers
Submitted Phone| dummySignedOffers
Phone Match Status| dummySignedOffers
File Link| dummySignedOffers
Signed Offer Status| dummySignedOffers
Rejection Reason| dummySignedOffers

Future Actions

Action| Meaning
Verify| HR verifies signed offer
Reject| HR rejects signed offer
Request Resubmission| Candidate must submit again

Important rule:

Email/phone mismatch should show a warning but should not block active intern status.

---

8. Activity Log

Page File

src/pages/ActivityLog.jsx

Data Required

dummyActivityLogs.js
dummyCandidates.js
dummyUsers.js

What This Page Should Show

This page should show the timeline/history of important HR lifecycle actions.

Main Columns

Column| Source
Date/Time| dummyActivityLogs
Candidate Name| dummyCandidates
Action Type| dummyActivityLogs
Performed By| dummyActivityLogs / dummyUsers
Old Status| dummyActivityLogs
New Status| dummyActivityLogs
Remarks| dummyActivityLogs

Important Events To Show

- Candidate form submitted
- Probation started
- Probation rejected
- Probation extended
- Reconsideration created
- Probation passed
- MID generated
- Offer letter generated
- Offer letter sent
- Signed offer submitted
- Signed offer mismatch
- Signed offer verified
- Signed offer rejected

---

9. HR Login

Page File

src/pages/HRLogin.jsx

Data Required

dummyUsers.js

What This Page Should Show

For V1 dummy testing, this page can be a placeholder login screen.

Later, it will connect with Supabase Auth.

Suggested Dummy Login Roles

Role| Purpose
HR Executive| Review probation and offer flow
HR Lead| Higher-level review and override
System Admin| Testing/admin access

---

Suggested Connection Order

Pages should be connected in this order:

1. HR Dashboard
2. Probation Review
3. Offer Letter Process
4. Active Interns
5. Signed Offer Verification
6. Activity Log
7. Candidate Probation Form
8. Signed Offer Upload
9. HR Login

This order is recommended because dashboard and review pages depend most directly on dummy data.

---

Summary

The HR Lifecycle Module should first connect dummy data to the HR Dashboard.

After that, data should be connected page by page.

The recommended flow is:

Dummy data files
↓
Dashboard counts
↓
Probation review list
↓
Offer letter process list
↓
Active interns list
↓
Signed offer verification list
↓
Activity log timeline

Once this flow works with dummy data, the same structure can later connect with Supabase.
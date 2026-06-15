HR Lifecycle Module V1

Overview

The HR Lifecycle Module V1 is a React-based frontend module designed to manage the intern HR lifecycle from probation submission to active intern status and signed offer verification.

The module is designed to work with a Supabase backend and later integrate with the company-wide master database and official repository structure.

The system focuses on structured HR workflow management, status tracking, role-based access planning, offer letter handling, MID generation, signed offer tracking, and audit-ready activity logging.

---

Project Purpose

The purpose of this module is to provide a clear and structured workflow for managing intern lifecycle operations.

The module covers:

- Candidate probation form submission
- Probation tracking and HR review
- Probation approval, rejection, extension, and reconsideration
- Offer Letter Process
- MID generation
- Offer letter tracking
- Active intern creation
- Signed offer submission
- Signed offer verification or rejection
- Activity log and notification tracking
- Future integration with master users, roles, teams, departments, and projects

---

Core Workflow

Candidate Probation Form
↓
Candidate Record Created
↓
Probation Attempt Created
↓
Probation Started
↓
HR Review
↓
Probation Passed / Rejected / Extended
↓
Offer Letter Approved
↓
MID Generation
↓
Offer Letter PDF Generation
↓
Offer Email Sent
↓
Active Intern Created
↓
Signed Offer Submitted
↓
HR Verification / Rejection

---

Tech Stack

- React
- Vite
- JavaScript
- Supabase-ready frontend structure
- Supabase planned for backend, database, authentication, and storage integration
- Google Drive planned for offer letter and signed offer file storage in V1
- Apps Script / n8n / Supabase Edge Functions can be used later for automation

---

V1 Scope

Included in V1

- Public candidate probation form
- HR login structure
- HR dashboard
- Probation review flow
- Probation approve, reject, and extend actions
- Reconsideration attempt planning
- Offer letter approval flow
- MID generation logic
- Offer letter tracking
- Active intern list
- Signed offer submission tracking
- Signed offer verification and rejection
- Email/phone mismatch warning logic
- Activity log planning
- Dummy data workflow testing
- Supabase-ready table planning
- Integration planning with master database

Not Included in Immediate V1

- Leave management
- Performance tracking
- Certificate generation
- LOR generation
- Awards
- Full Team Lead dashboard
- Full Candidate dashboard
- Complete Supabase Row Level Security implementation
- Production-level PDF/email automation

These features are considered future extensions after the core HR lifecycle flow is stable.

---

Folder Structure

hr-lifecycle-module-v1/
├── docs/
│   ├── workflow.md
│   ├── status-values.md
│   ├── table-plan.md
│   ├── dummy-data-plan.md
│   ├── automation-points.md
│   └── integration-notes.md
│
├── public/
│
├── src/
│   ├── assets/
│   ├── components/
│   ├── data/
│   ├── pages/
│   ├── services/
│   ├── utils/
│   ├── App.jsx
│   ├── App.css
│   └── main.jsx
│
├── package.json
├── package-lock.json
├── README.md
└── .gitignore

---

Repository Structure Explanation

"docs/"

Contains all planning, workflow, table, status, dummy data, automation, and integration documentation for the HR Lifecycle Module.

"public/"

Contains public static assets that can be served directly by the frontend.

"src/"

Main source code folder for the React application.

"src/assets/"

Stores images, icons, and static frontend assets.

"src/components/"

Stores reusable UI components such as cards, buttons, status badges, tables, headers, and shared layouts.

"src/data/"

Stores dummy data files used for frontend workflow testing before Supabase integration.

Expected dummy data files may include:

dummyUsers.js
dummyRoles.js
dummyDepartments.js
dummyTeams.js
dummyProjects.js
dummyCandidates.js
dummyProbationAttempts.js
dummyOffers.js
dummyMidRegistry.js
dummyActiveInterns.js
dummySignedOffers.js
dummyActivityLogs.js
dummyNotifications.js

"src/pages/"

Stores page-level React components for the main screens of the HR Lifecycle Module.

"src/services/"

Stores service files such as Supabase client configuration and future API/service helpers.

"src/utils/"

Stores utility functions such as MID generation, status rules, date helpers, validation helpers, and workflow helpers.

---

Planned Pages

The following pages are planned for the HR Lifecycle V1 prototype:

CandidateProbationForm.jsx
HRLogin.jsx
HRDashboard.jsx
ProbationReview.jsx
OfferApproval.jsx
ActiveInterns.jsx
SignedOfferUpload.jsx
SignedOfferVerification.jsx
ActivityLog.jsx

---

Page Purpose

Page| Purpose
CandidateProbationForm| Public form for candidates to submit probation details
HRLogin| Login screen for HR users
HRDashboard| Overview of candidates, probation, offers, active interns, and signed offers
ProbationReview| HR page to approve, reject, or extend probation
OfferApproval| HR page to approve offer process and trigger MID generation
ActiveInterns| List of interns who became active after offer email was sent
SignedOfferUpload| Candidate-facing signed offer submission page
SignedOfferVerification| HR page to verify or reject signed offer
ActivityLog| Timeline of important actions and status changes

---

Documentation Files

"workflow.md"

Defines the complete HR lifecycle workflow from candidate probation form submission to signed offer verification.

"status-values.md"

Defines all important statuses used across the module, including candidate status, probation status, offer status, active intern status, signed offer status, email/phone match status, and activity log event types.

"table-plan.md"

Defines the planned HR module tables, fields, and their purpose for future Supabase integration.

"dummy-data-plan.md"

Defines dummy records and test cases required to test the HR lifecycle workflow before database integration.

"automation-points.md"

Defines where automation is required in the workflow, including probation start email, probation review reminder, MID generation, offer PDF generation, offer email, active intern creation, signed offer tracking, and activity log creation.

"integration-notes.md"

Defines how the HR Lifecycle module connects with the company-wide Supabase master database, official repository, master users, roles, teams, departments, projects, file storage, and automation tools.

---

Important Business Rules

- Candidate probation form is public in V1.
- HR login is required for review and approval actions.
- Default probation duration is 7 days.
- Probation can be approved, rejected, or extended.
- Rejected candidates can be reconsidered through a new probation attempt.
- Previous probation attempts should not be overwritten.
- MID is generated only after HR approves the offer process.
- Candidate becomes active after the offer email is sent.
- Signed offer verification does not block active intern status.
- Signed offer status matters later for certificate/LOR eligibility.
- Email or phone mismatch during signed offer submission should show a warning.
- Email or phone mismatch should not block the active intern flow.
- Activity logs should be created for important workflow actions.

---

MID Generation Rule

Final MID format:

ROLE_CODE / NAME_CODE / SERIAL

Examples:

AU/AS/001
AU/AS/002
HR/KA/001

MID Logic

- "ROLE_CODE" comes from the selected role.
- "NAME_CODE" comes from the candidate name.
- If the candidate has first and last name, use initials.
- If the candidate has a single name, use the first two letters.
- Serial number increases only for the same "role_code + name_code" combination.
- MID should not be generated before HR offer approval.
- MID history should be stored in a separate MID registry table.

---

Master Database Dependency

The HR Lifecycle module is designed to depend on common/master tables from the company-wide Supabase database.

Expected master tables:

users / profiles
roles
permissions
departments
teams
projects
resources / media

The HR module should avoid creating permanent duplicate versions of master users, roles, departments, teams, and projects.

---

Planned HR Module Tables

The following HR-specific tables are planned for Supabase integration:

hr_candidates
hr_probation_attempts
hr_offer_letters
hr_mid_registry
hr_active_interns
hr_signed_offers
hr_activity_logs
hr_notifications

These tables use the "hr_" prefix to avoid conflict with shared master tables.

---

Candidate Source Handling

The HR module supports multiple candidate entry sources.

Possible values:

candidate_form
hr_manual
stage0_import

Source| Meaning
candidate_form| Candidate submitted the public probation form
hr_manual| HR created the candidate manually
stage0_import| Candidate came from Assignment / Stage 0 module

This keeps the module ready for future integration with the Assignment module.

---

Signed Offer Handling

Signed offer is treated as a separate process from offer letter generation and active intern status.

Important rules:

- Signed offer does not block active intern status.
- Candidate can submit signed offer after offer email is sent.
- Candidate may submit signed offer using a different email or phone.
- Email/phone mismatch should create a warning.
- HR can verify or reject signed offer manually.
- If rejected, candidate can be asked to resubmit.
- Signed offer status matters later for certificate/LOR eligibility.

---

File Storage Plan

For V1, offer letter PDFs and signed offer files can be stored in Google Drive.

Supabase stores:

- Offer letter PDF link
- Signed offer file link
- File status
- Submission status
- Verification status

Future storage can be shifted to Supabase Storage if required.

---

Automation Plan

Since Django backend is not being used in V1, automation can be handled using:

- Google Apps Script
- n8n
- Supabase Edge Functions
- Make.com

Recommended V1 automation flow:

Supabase stores candidate and offer data
↓
Automation tool reads data
↓
Google Docs template generates offer letter
↓
PDF is stored in Google Drive
↓
Email is sent through Gmail
↓
Supabase is updated with PDF link and email status

---

Setup Instructions

Install dependencies

npm install

Run development server

npm run dev

Open local app

Vite usually runs on:

http://localhost:5173/

---

Environment Variables

When Supabase is connected, create a ".env" file.

Example:

VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=

Important:

- Do not commit real Supabase keys to GitHub.
- Keep real keys only in local ".env".
- Add ".env" to ".gitignore".

---

Team Work Division

Arjun

- HR workflow logic
- Status values
- Table and field planning
- MID logic
- Dummy data cases
- Automation planning
- Integration notes
- Documentation

Ananya

- React + Vite setup
- GitHub setup
- Folder structure
- Page structure
- Basic frontend screens
- Dummy data connection
- Supabase client setup
- UI testing support

Both members review and test the workflow together.

---

Future Scope

After the V1 workflow is stable, the module can be extended with:

- Supabase Auth
- Supabase Row Level Security
- Team Lead dashboard
- Candidate dashboard
- Leave tracking
- Performance tracking
- Extension requests
- Certificate/LOR eligibility
- Full PDF/email automation
- Integration with Assignment / Stage 0 module
- Integration with Project Tracking module

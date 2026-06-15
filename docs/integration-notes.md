HR Lifecycle V1 Integration Notes

Purpose

This document explains how the HR Lifecycle Module V1 will connect with the company-wide master Supabase database and the official JCF repository in later stages.

For the first phase, the HR Lifecycle Module will be developed independently using React, dummy data, and a Supabase-ready structure. Once the master database and official repo structure are finalized, the module can be integrated without major rework.

---

Current Project Direction

The HR Lifecycle Module V1 will use:

- React + Vite for frontend
- Supabase as backend/database/auth platform
- Dummy data during initial development
- Google Drive for offer letter PDF and signed offer storage in V1
- Apps Script / n8n / Supabase Edge Functions later for automation
- Official JCF repository integration later

Django backend is not part of V1.

---

Development Approach

Phase 1: Independent HR Module Prototype

In the first phase, the HR Lifecycle Module will be developed as a separate working prototype.

This phase includes:

- React project setup
- Folder structure
- Basic page templates
- Dummy data files
- Workflow documentation
- Status values
- HR module table planning
- Automation points
- Activity log planning

The purpose is to create a working module structure before connecting with the final master database.

---

Phase 2: Dummy Data Workflow Testing

Before connecting Supabase, the HR lifecycle flow will be tested using dummy data.

The dummy data will simulate:

- Candidate probation submission
- Probation approval
- Probation rejection
- Probation extension
- Reconsideration attempt
- Offer approval
- MID generation
- Offer sent
- Active intern creation
- Signed offer submission
- Email/phone mismatch
- Signed offer verification
- Signed offer rejection

This helps the team validate the workflow before database integration.

---

Phase 3: Supabase Connection

After the dummy-data workflow is stable, the module can be connected with Supabase.

Recommended HR module tables:

- hr_candidates
- hr_probation_attempts
- hr_offer_letters
- hr_mid_registry
- hr_active_interns
- hr_signed_offers
- hr_activity_logs
- hr_notifications

These tables can first be created with "hr_" prefix to avoid conflict with common/master tables.

---

Master Database Dependency

The HR Lifecycle Module will depend on company-wide master tables created by the database team.

Expected master/common tables:

Master Table| HR Module Usage
users / profiles| HR users, Team Leads, Project Managers, POD Leads, Admin users
roles| Role/designation mapping
permissions| Role-based action access
departments| Candidate and intern department mapping
teams| Intern team assignment
projects| Project assignment after activation
resources / media| File/document references

Until these master tables are finalized, the HR module will use dummy master data inside the React project.

---

How HR Tables Will Connect Later

Once the master database is ready, HR module tables can reference master tables.

Examples:

HR Field| Future Master Table Reference
reviewed_by| users / profiles
approved_by| users / profiles
verified_by| users / profiles
assigned_team_lead_id| users / profiles
department_id| departments
team_id| teams
project_id| projects
role_code| roles / designations
file_url| resources / media or Google Drive link

The HR module should avoid creating duplicate permanent versions of users, roles, teams, departments, and projects.

---

Candidate Source Integration

The HR module should support multiple candidate entry sources.

Possible candidate sources:

Source| Meaning
candidate_form| Candidate submitted public probation form
hr_manual| HR manually created candidate record
stage0_import| Candidate came from Assignment / Stage 0 module

The "created_source" field should be used to track where the candidate record came from.

This is important because the Assignment module may later send candidate data into the HR Lifecycle Module.

---

GitHub Integration Plan

Current Working Repo

The HR Lifecycle Module can start in a separate GitHub repository during development.

Suggested working repo:

- hr-lifecycle-module-v1

This repo should contain:

- React frontend
- docs folder
- dummy data
- page structure
- Supabase client setup
- README
- integration notes

Future Official Repo Integration

Later, once the official JCF/company repository structure is finalized, the HR Lifecycle Module can be moved into the official repo as a separate folder/module.

Possible final structure:

jcf-platform/
├── master-database/
├── assignment-module/
├── hr-lifecycle/
└── project-tracking/

The HR module should be built in a clean structure so it can be moved or merged easily.

---

Supabase Access Boundary

Until the master database is finalized, the HR module should avoid changing shared master tables directly.

Safe approach:

1. Use dummy data first inside React.
2. If allowed, create temporary HR tables with "hr_" prefix.
3. Avoid editing master tables unless confirmed by the database owner.
4. Later connect HR fields to master table IDs.

Recommended temporary HR table prefix:

hr_

Example:

hr_candidates
hr_probation_attempts
hr_offer_letters
hr_signed_offers

---

Authentication and Access Plan

V1 Login Scope

Recommended V1 login scope:

User Type| V1 Requirement
Candidate| Public form only
HR| Login required
Team Lead| Later phase
Project Manager| Later phase
POD Lead| Later phase
System Admin| Later phase / testing

For V1, the candidate probation form can be public. HR login is required for review, approval, verification, and status changes.

Candidate login and Team Lead login can be added later.

---

Supabase Row Level Security

Supabase Row Level Security is important for the final system, but it does not need to block early development.

Recommended approach:

Phase 1

Use dummy data and frontend role-based display.

Phase 2

Use Supabase Auth and profiles table.

Phase 3

Add role-based checks.

Phase 4

Add proper Supabase Row Level Security policies after roles and permissions are finalized.

Important note:

RLS should be designed carefully because HR, Team Lead, Project Manager, and Admin users will have different access levels.

---

File Storage Integration

For V1, offer letter PDFs and signed offer files can be stored in Google Drive.

Supabase should store:

- PDF link
- Signed offer file link
- File status
- Submission status
- Verification status

Future options:

- Move files to Supabase Storage
- Keep Google Drive as storage
- Store only file references in Supabase

Recommended V1 approach:

Google Drive stores files
Supabase stores links and statuses

---

PDF and Email Automation Integration

Since Django backend is not being used, PDF and email automation can be handled using automation tools.

Possible tools:

- Google Apps Script
- n8n
- Supabase Edge Functions
- Make.com

Recommended V1 flow:

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

This keeps the system practical and aligned with automation workflow development.

---

MID Integration

The finalized MID format is:

ROLE_CODE / NAME_CODE / SERIAL

Examples:

AU/AS/001
AU/AS/002
HR/KA/001

MID generation should happen only after HR approves the offer process.

MID rules:

- Role code comes from the selected role.
- Name code comes from the candidate name.
- If candidate has first and last name, use initials.
- If candidate has a single name, use first two letters.
- Serial number increases only for the same role_code + name_code combination.
- MID history should be stored in "hr_mid_registry".

---

Signed Offer Integration

Signed offer should be treated as a separate entity.

Important rules:

- Signed offer does not block active intern status.
- Candidate becomes active after offer email is sent.
- Signed offer verification matters later for certificate/LOR eligibility.
- Candidate can submit signed offer using a different email or phone.
- Email/phone mismatch should create a warning, not block the flow.
- HR can verify or reject the signed offer.
- If rejected, candidate can be asked to resubmit.

Recommended table:

hr_signed_offers

---

Activity Log Integration

The activity log should track important events across the HR lifecycle.

Events to track:

- Candidate form submitted
- Probation started
- Probation passed
- Probation rejected
- Probation extended
- Reconsideration created
- Offer approved
- MID generated
- Offer PDF generated
- Offer email sent
- Intern activated
- Signed offer submitted
- Signed offer email/phone mismatch
- Signed offer verified
- Signed offer rejected

Recommended table:

hr_activity_logs

This helps with audit, HR review, and debugging.

---

Module Boundary

The HR Lifecycle Module owns:

- Candidate probation flow
- Probation attempts
- HR review
- Offer approval
- MID generation
- Offer letter status
- Active intern creation
- Signed offer tracking
- HR activity logs
- HR notification tracking

The HR Lifecycle Module does not fully own:

- Company-wide users
- Company-wide roles
- Company-wide permissions
- Master teams
- Master departments
- Master projects
- Assignment/Stage 0 module
- Project tracking module

Those should come from the master database or other modules.

---

Integration Notes for Team Discussion

The HR Lifecycle Module can start independently with dummy data while keeping the structure ready for master database integration.

Key alignment points:

- HR module should use master users/profiles later.
- HR module should use master roles/permissions later.
- HR module should use master teams/departments/projects later.
- HR-specific tables should use "hr_" prefix.
- Dummy data should be temporary.
- React screens should be built first.
- Supabase connection should come after workflow and table plan are stable.
- PDF/email automation can be added after core workflow is working.
- Official JCF repo integration can happen after the module structure is clean.

---

Summary

The HR Lifecycle Module V1 should be built as an independent React + dummy data prototype first.

It should later connect with the company-wide Supabase master database.

The development approach is:

React screens
↓
Dummy data workflow
↓
Supabase HR tables
↓
Master database integration
↓
PDF/email automation
↓
Official JCF repo merge

This approach allows work to start immediately without waiting for the full master database to be completed.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP VIEW IF EXISTS activity_log_view;
DROP VIEW IF EXISTS candidate_detail_view;
DROP VIEW IF EXISTS signed_offer_verification_view;
DROP VIEW IF EXISTS active_interns_view;
DROP VIEW IF EXISTS offer_letter_process_view;
DROP VIEW IF EXISTS probation_review_view;
DROP VIEW IF EXISTS hr_dashboard_view;
DROP VIEW IF EXISTS leave_requests_view;
DROP VIEW IF EXISTS leave_balance_view;

DROP TABLE IF EXISTS hr_activity_logs;
DROP TABLE IF EXISTS signed_offer_verifications;
DROP TABLE IF EXISTS hr_offer_letters;
DROP TABLE IF EXISTS hr_lifecycle;
DROP TABLE IF EXISTS master_candidates;
DROP TABLE IF EXISTS internship_extensions;
DROP TABLE IF EXISTS leave_requests;
DROP TABLE IF EXISTS leave_balances;

CREATE TABLE master_candidates (
    candidate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone VARCHAR(30),
    alternate_phone VARCHAR(30),
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    applied_role VARCHAR(100),
    role_code VARCHAR(20),
    department VARCHAR(100),
    qualification VARCHAR(150),
    college_name VARCHAR(150),
    source VARCHAR(100),
    referral_name VARCHAR(150),
    availability_status VARCHAR(60),
    notes TEXT,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE hr_lifecycle (
    lifecycle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES master_candidates(candidate_id) ON DELETE CASCADE,
    lifecycle_status VARCHAR(60) NOT NULL,
    probation_start_date DATE,
    probation_end_date DATE,
    original_end_date DATE,
    internship_duration_months INTEGER CHECK (internship_duration_months IN (3,4,6,12)),
    total_extension_months INTEGER NOT NULL DEFAULT 0,
    total_internship_duration_days INTEGER,
    current_internship_duration_days INTEGER,
    current_end_date DATE,
    probation_extension_count INTEGER DEFAULT 0,
    probation_review_notes TEXT,
    hr_decision VARCHAR(60),
    mid VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE hr_offer_letters (
    offer_letter_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES master_candidates(candidate_id) ON DELETE CASCADE,
    offer_status VARCHAR(60) NOT NULL,
    offer_letter_number VARCHAR(50),
    generated_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE signed_offer_verifications (
    verification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES master_candidates(candidate_id) ON DELETE CASCADE,
    signed_offer_status VARCHAR(60) NOT NULL,
    signed_offer_submitted_at TIMESTAMPTZ,
    verified_at TIMESTAMPTZ,
    email_match_status VARCHAR(30),
    phone_match_status VARCHAR(30),
    verification_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE hr_activity_logs (
    activity_log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES master_candidates(candidate_id) ON DELETE CASCADE,
    activity_type VARCHAR(100) NOT NULL,
    from_status VARCHAR(60),
    to_status VARCHAR(60),
    remarks TEXT,
    activity_status VARCHAR(30) DEFAULT 'SUCCESS',
    error_message TEXT,
    metadata JSONB,
    performed_by VARCHAR(150),
    performed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE leave_requests (
    leave_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    candidate_id UUID NOT NULL
        REFERENCES master_candidates(candidate_id)
        ON DELETE CASCADE,

    mid VARCHAR(50) ,

    leave_type VARCHAR(50) NOT NULL,

    start_date DATE NOT NULL,

    end_date DATE NOT NULL,

    requested_leave_days INTEGER NOT NULL CHECK (requested_leave_days > 0),

    reason TEXT,

    supporting_document TEXT,

    leave_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (leave_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    approved_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ
);

CREATE TABLE leave_balances (
    candidate_id UUID PRIMARY KEY
        REFERENCES master_candidates(candidate_id)
        ON DELETE CASCADE,

    mid VARCHAR(50) ,

    allocated_leave_days INTEGER NOT NULL DEFAULT 15,

    approved_leave_days INTEGER NOT NULL DEFAULT 0,

    remaining_leave_days INTEGER NOT NULL DEFAULT 15,

    extra_leave_days INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE internship_extensions (

    extension_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    candidate_id UUID NOT NULL
        REFERENCES master_candidates(candidate_id)
        ON DELETE CASCADE,

    mid VARCHAR(50),

    extension_type VARCHAR(20)
        CHECK (extension_type IN ('MONTHS','LEAVE')),

    extension_value INTEGER,

    reason TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    is_processed BOOLEAN DEFAULT FALSE
);


INSERT INTO master_candidates (
    candidate_id,
    first_name,
    last_name,
    full_name,
    email,
    phone,
    alternate_phone,
    address,
    city,
    state,
    applied_role,
    role_code,
    department,
    qualification,
    college_name,
    source,
    referral_name,
    availability_status,
    notes,
    submitted_at
) VALUES
('00000000-0000-0000-0000-000000000001', 'Aarav', 'Sharma', 'Aarav Sharma', 'aarav.sharma@example.com', '+91-9876500001', '+91-9123400001', '12 MG Road', 'Bengaluru', 'Karnataka', 'Software Intern', NULL, 'Engineering', 'B.Tech Computer Science', 'JCF Institute of Technology', 'Website', NULL, 'Immediate', 'New candidate awaiting HR review.', NOW() - INTERVAL '18 days'),
('00000000-0000-0000-0000-000000000002', 'Isha', 'Nair', 'Isha Nair', 'isha.nair@example.com', '+91-9876500002', '+91-9123400002', '45 Lake View Street', 'Kochi', 'Kerala', 'HR Intern', NULL, 'Human Resources', 'MBA Human Resources', 'Kerala School of Management', 'Referral', 'Meera Thomas', 'Two weeks notice', 'HR profile approved for probation.', NOW() - INTERVAL '17 days'),
('00000000-0000-0000-0000-000000000003', 'Kabir', 'Mehta', 'Kabir Mehta', 'kabir.mehta@example.com', '+91-9876500003', '+91-9123400003', '8 Design Colony', 'Mumbai', 'Maharashtra', 'Design Intern', NULL, 'Creative', 'B.Des Visual Design', 'Mumbai Design College', 'LinkedIn', NULL, 'Immediate', 'Probation initiated for design role.', NOW() - INTERVAL '16 days'),
('00000000-0000-0000-0000-000000000004', 'Meera', 'Iyer', 'Meera Iyer', 'meera.iyer@example.com', '+91-9876500004', '+91-9123400004', '21 Anna Salai', 'Chennai', 'Tamil Nadu', 'Marketing Intern', NULL, 'Marketing', 'BBA Marketing', 'Chennai Business School', 'Website', NULL, 'Immediate', 'Welcome mail sent after probation setup.', NOW() - INTERVAL '15 days'),
('00000000-0000-0000-0000-000000000005', 'Rohan', 'Gupta', 'Rohan Gupta', 'rohan.gupta@example.com', '+91-9876500005', '+91-9123400005', '67 Civil Lines', 'Delhi', 'Delhi', 'Data Intern', NULL, 'Analytics', 'B.Sc Statistics', 'Delhi Science College', 'Campus Drive', NULL, 'Immediate', 'Candidate is currently in probation.', NOW() - INTERVAL '14 days'),
('00000000-0000-0000-0000-000000000006', 'Ananya', 'Rao', 'Ananya Rao', 'ananya.rao@example.com', '+91-9876500006', '+91-9123400006', '19 Jubilee Hills', 'Hyderabad', 'Telangana', 'Finance Intern', NULL, 'Finance', 'B.Com Finance', 'Hyderabad Commerce College', 'Referral', 'Sanjay Rao', 'One month notice', 'Probation review pending.', NOW() - INTERVAL '13 days'),
('00000000-0000-0000-0000-000000000007', 'Dev', 'Patel', 'Dev Patel', 'dev.patel@example.com', '+91-9876500007', '+91-9123400007', '34 Satellite Road', 'Ahmedabad', 'Gujarat', 'Operations Intern', NULL, 'Operations', 'BBA Operations', 'Ahmedabad Management Institute', 'LinkedIn', NULL, 'Immediate', 'Probation rejected after review.', NOW() - INTERVAL '12 days'),
('00000000-0000-0000-0000-000000000008', 'Nisha', 'Verma', 'Nisha Verma', 'nisha.verma@example.com', '+91-9876500008', '+91-9123400008', '52 Gomti Nagar', 'Lucknow', 'Uttar Pradesh', 'QA Intern', NULL, 'Quality Assurance', 'B.Tech Information Technology', 'Lucknow Engineering College', 'Website', NULL, 'Two weeks notice', 'Probation extended for additional assessment.', NOW() - INTERVAL '11 days'),
('00000000-0000-0000-0000-000000000009', 'Arjun', 'Reddy', 'Arjun Reddy', 'arjun.reddy@example.com', '+91-9876500009', '+91-9123400009', '73 Hitech City', 'Hyderabad', 'Telangana', 'Software Intern', NULL, 'Engineering', 'MCA', 'Deccan Computer Academy', 'Campus Drive', NULL, 'Immediate', 'MID generated after probation passed.', NOW() - INTERVAL '10 days'),
('00000000-0000-0000-0000-000000000010', 'Priya', 'Menon', 'Priya Menon', 'priya.menon@example.com', '+91-9876500010', '+91-9123400010', '11 Brigade Road', 'Bengaluru', 'Karnataka', 'Content Intern', NULL, 'Content', 'BA English', 'Bengaluru Arts College', 'Referral', 'Anita Menon', 'Immediate', 'Offer letter generated and awaiting send.', NOW() - INTERVAL '9 days'),
('00000000-0000-0000-0000-000000000011', 'Vikram', 'Singh', 'Vikram Singh', 'vikram.singh@example.com', '+91-9876500011', '+91-9123400011', '88 Park Street', 'Kolkata', 'West Bengal', 'Business Analyst Intern', NULL, 'Strategy', 'BBA Business Analytics', 'Kolkata Business College', 'LinkedIn', NULL, 'Immediate', 'Active intern with verified signed offer.', NOW() - INTERVAL '8 days'),
('00000000-0000-0000-0000-000000000012', 'Sara', 'Khan', 'Sara Khan', 'sara.khan@example.com', '+91-9876500012', '+91-9123400012', '15 FC Road', 'Pune', 'Maharashtra', 'Support Intern', NULL, 'Customer Support', 'BA Psychology', 'Pune Liberal Arts College', 'Website', NULL, 'Immediate', 'Signed offer requires mismatch review.', NOW() - INTERVAL '7 days'),
('00000000-0000-0000-0000-000000000013', 'Neha', 'Joshi', 'Neha Joshi', 'neha.joshi@example.com', '+91-9876500013', '+91-9123400013', '24 University Road', 'Jaipur', 'Rajasthan', 'Product Intern', NULL, 'Product', 'B.Tech Electronics', 'Jaipur Technical University', 'Campus Drive', NULL, 'Two weeks notice', 'Probation passed; MID generation pending.', NOW() - INTERVAL '6 days'),
('00000000-0000-0000-0000-000000000014', 'Aditya', 'Bose', 'Aditya Bose', 'aditya.bose@example.com', '+91-9876500014', '+91-9123400014', '6 Salt Lake Sector V', 'Kolkata', 'West Bengal', 'Research Intern', NULL, 'Research', 'M.Sc Data Science', 'Eastern Research University', 'Referral', 'Ritika Bose', 'Immediate', 'Active intern with signed offer submitted.', NOW() - INTERVAL '5 days');

INSERT INTO hr_lifecycle (
    candidate_id,
    lifecycle_status,
    probation_start_date,
    probation_end_date,
    probation_review_notes,
    hr_decision,
    mid
) VALUES
('00000000-0000-0000-0000-000000000001', 'HR_REVIEW_PENDING', NULL, NULL, NULL, NULL, NULL),
('00000000-0000-0000-0000-000000000002', 'HR_APPROVED_FOR_PROBATION', NULL, NULL, 'HR approved candidate for probation.', NULL, NULL),
('00000000-0000-0000-0000-000000000003', 'WELCOME_MAIL_SENT', CURRENT_DATE - 2, CURRENT_DATE + 28, 'Probation record created.', NULL, NULL),
('00000000-0000-0000-0000-000000000004', 'WELCOME_MAIL_SENT', CURRENT_DATE - 5, CURRENT_DATE + 25, 'Welcome mail sent by HR.', NULL, NULL),
('00000000-0000-0000-0000-000000000005', 'IN_PROBATION', CURRENT_DATE - 12, CURRENT_DATE + 18, 'Candidate is currently in probation.', NULL, NULL),
('00000000-0000-0000-0000-000000000006', 'PROBATION_REVIEW', CURRENT_DATE - 30, CURRENT_DATE, 'Probation review pending with HR.', NULL, NULL),
('00000000-0000-0000-0000-000000000007', 'PROBATION_REJECTED', CURRENT_DATE - 35, CURRENT_DATE - 5, 'Candidate did not meet probation expectations.', 'PROBATION_REJECTED', NULL),
('00000000-0000-0000-0000-000000000008', 'PROBATION_EXTENDED', CURRENT_DATE - 30, CURRENT_DATE + 15, 'Probation extended for additional assessment.', 'PROBATION_EXTENDED', NULL),
('00000000-0000-0000-0000-000000000009', 'MID_GENERATED', CURRENT_DATE - 40, CURRENT_DATE - 10, 'Probation passed and MID generated.', 'PROBATION_PASSED', 'JCF-MID-0009'),
('00000000-0000-0000-0000-000000000010', 'OFFER_LETTER_GENERATED', CURRENT_DATE - 42, CURRENT_DATE - 12, 'Probation passed and offer letter generated.', 'PROBATION_PASSED', 'JCF-MID-0010'),
('00000000-0000-0000-0000-000000000011', 'ACTIVE', CURRENT_DATE - 45, CURRENT_DATE - 15, 'Offer letter sent and candidate marked active intern.', 'PROBATION_PASSED', 'JCF-MID-0011'),
('00000000-0000-0000-0000-000000000012', 'MISMATCH_REVIEW', CURRENT_DATE - 50, CURRENT_DATE - 20, 'Signed offer submitted with mismatch review required.', 'PROBATION_PASSED', 'JCF-MID-0012'),
('00000000-0000-0000-0000-000000000013', 'PROBATION_PASSED', CURRENT_DATE - 32, CURRENT_DATE - 2, 'Probation passed. MID is pending generation.', 'PROBATION_PASSED', NULL),
('00000000-0000-0000-0000-000000000014', 'ACTIVE', CURRENT_DATE - 48, CURRENT_DATE - 18, 'Offer letter sent and candidate marked active intern.', 'PROBATION_PASSED', 'JCF-MID-0014');

INSERT INTO hr_offer_letters (
    candidate_id,
    offer_status,
    offer_letter_number,
    generated_at,
    sent_at
) VALUES
('00000000-0000-0000-0000-000000000009', 'MID_GENERATED', NULL, NULL, NULL),
('00000000-0000-0000-0000-000000000010', 'OFFER_LETTER_GENERATED', 'JCF-OL-0010', NOW() - INTERVAL '2 days', NULL),
('00000000-0000-0000-0000-000000000011', 'OFFER_LETTER_SENT', 'JCF-OL-0011', NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'),
('00000000-0000-0000-0000-000000000012', 'OFFER_LETTER_SENT', 'JCF-OL-0012', NOW() - INTERVAL '8 days', NOW() - INTERVAL '7 days'),
('00000000-0000-0000-0000-000000000014', 'OFFER_LETTER_SENT', 'JCF-OL-0014', NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days');

INSERT INTO signed_offer_verifications (
    candidate_id,
    signed_offer_status,
    signed_offer_submitted_at,
    verified_at,
    email_match_status,
    phone_match_status,
    verification_notes
) VALUES
('00000000-0000-0000-0000-000000000011', 'SIGNED_OFFER_VERIFIED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day', 'MATCH', 'MATCH', 'Signed offer verified successfully.'),
('00000000-0000-0000-0000-000000000012', 'MISMATCH_REVIEW', NOW() - INTERVAL '3 days', NULL, 'MATCH', 'MISMATCH', 'Phone mismatch found during signed offer verification.'),
('00000000-0000-0000-0000-000000000014', 'SIGNED_OFFER_SUBMITTED', NOW() - INTERVAL '1 day', NULL, NULL, NULL, 'Signed offer submitted and pending HR verification.');

INSERT INTO hr_activity_logs (
    candidate_id,
    activity_type,
    from_status,
    to_status,
    remarks,
    activity_status,
    error_message,
    metadata,
    performed_by
) VALUES
('00000000-0000-0000-0000-000000000001', 'CANDIDATE_FORM_SUBMITTED', NULL, 'HR_REVIEW_PENDING', 'Candidate form submitted.', 'SUCCESS', NULL, '{"module": "candidate_intake"}'::jsonb, 'system'),
('00000000-0000-0000-0000-000000000002', 'HR_REVIEW_COMPLETED', 'HR_REVIEW_PENDING', 'HR_APPROVED_FOR_PROBATION', 'Candidate approved for probation.', 'SUCCESS', NULL, '{"module": "hr_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000003', 'PROBATION_INITIATED', 'HR_APPROVED_FOR_PROBATION', 'PROBATION_INITIATED', 'Probation initiated.', 'SUCCESS', NULL, '{"module": "probation"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000004', 'WELCOME_MAIL_SENT', 'PROBATION_INITIATED', 'WELCOME_MAIL_SENT', 'Welcome mail sent.', 'SUCCESS', NULL, '{"module": "probation"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000005', 'PROBATION_ACTIVE', 'WELCOME_MAIL_SENT', 'IN_PROBATION', 'Candidate is in probation.', 'SUCCESS', NULL, '{"module": "probation"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000006', 'PROBATION_REVIEW_STARTED', 'IN_PROBATION', 'PROBATION_REVIEW', 'Probation review started.', 'SUCCESS', NULL, '{"module": "probation_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000007', 'HR_DECISION', 'PROBATION_REVIEW', 'PROBATION_REJECTED', 'Probation rejected.', 'SUCCESS', NULL, '{"module": "probation_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000008', 'HR_DECISION', 'PROBATION_REVIEW', 'PROBATION_EXTENDED', 'Probation extended.', 'SUCCESS', NULL, '{"module": "probation_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000009', 'HR_DECISION', 'PROBATION_REVIEW', 'PROBATION_PASSED', 'Probation passed.', 'SUCCESS', NULL, '{"module": "probation_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000009', 'MID_GENERATED', 'PROBATION_PASSED', 'MID_GENERATED', 'MID generated after probation passed.', 'SUCCESS', NULL, '{"module": "offer_letter_process"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000010', 'OFFER_LETTER_GENERATION_FAILED', 'MID_GENERATED', NULL, 'Dummy offer letter generation failure for activity log testing.', 'FAILED', 'Dummy PDF generation failed during test', '{"module": "offer_letter_process"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000010', 'OFFER_LETTER_GENERATED', 'MID_GENERATED', 'OFFER_LETTER_GENERATED', 'Offer letter generated.', 'SUCCESS', NULL, '{"module": "offer_letter_process"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000011', 'OFFER_LETTER_SENT', 'OFFER_LETTER_GENERATED', 'OFFER_LETTER_SENT', 'Offer letter sent.', 'SUCCESS', NULL, '{"module": "offer_letter_process"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000011', 'ACTIVE_INTERN_CREATED', 'OFFER_LETTER_SENT', 'ACTIVE', 'Candidate marked as active intern.', 'SUCCESS', NULL, '{"module": "active_interns"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000011', 'SIGNED_OFFER_SUBMITTED', 'ACTIVE', 'SIGNED_OFFER_SUBMITTED', 'Signed offer submitted by active intern.', 'SUCCESS', NULL, '{"module": "signed_offer_verification"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000011', 'SIGNED_OFFER_VERIFIED', 'SIGNED_OFFER_SUBMITTED', 'SIGNED_OFFER_VERIFIED', 'Signed offer verified.', 'SUCCESS', NULL, '{"module": "signed_offer_verification"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000012', 'SIGNED_OFFER_SUBMITTED', 'ACTIVE', 'SIGNED_OFFER_SUBMITTED', 'Signed offer submitted by active intern.', 'SUCCESS', NULL, '{"module": "signed_offer_verification"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000012', 'MISMATCH_REVIEW', 'SIGNED_OFFER_SUBMITTED', 'MISMATCH_REVIEW', 'Signed offer moved to mismatch review.', 'SUCCESS', NULL, '{"module": "signed_offer_verification"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000013', 'HR_DECISION', 'PROBATION_REVIEW', 'PROBATION_PASSED', 'Probation passed. MID generation is pending.', 'SUCCESS', NULL, '{"module": "probation_review"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000014', 'OFFER_LETTER_SENT', 'OFFER_LETTER_GENERATED', 'OFFER_LETTER_SENT', 'Offer letter sent.', 'SUCCESS', NULL, '{"module": "offer_letter_process"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000014', 'ACTIVE_INTERN_CREATED', 'OFFER_LETTER_SENT', 'ACTIVE', 'Candidate marked as active intern.', 'SUCCESS', NULL, '{"module": "active_interns"}'::jsonb, 'hr.admin@jcf.example'),
('00000000-0000-0000-0000-000000000014', 'SIGNED_OFFER_SUBMITTED', 'ACTIVE', 'SIGNED_OFFER_SUBMITTED', 'Signed offer submitted by active intern.', 'SUCCESS', NULL, '{"module": "signed_offer_verification"}'::jsonb, 'hr.admin@jcf.example');

INSERT INTO leave_balances (
    candidate_id,
    mid,
    allocated_leave_days,
    approved_leave_days,
    remaining_leave_days,
    extra_leave_days
)
VALUES
('00000000-0000-0000-0000-000000000009','JCF-MID-0009',15,2,13,0),
('00000000-0000-0000-0000-000000000010','JCF-MID-0010',15,0,15,0),
('00000000-0000-0000-0000-000000000011','JCF-MID-0011',15,4,11,0),
('00000000-0000-0000-0000-000000000012','JCF-MID-0012',15,1,14,0),
('00000000-0000-0000-0000-000000000014','JCF-MID-0014',15,3,12,2);

INSERT INTO leave_requests (
    candidate_id,
    mid,
    leave_type,
    start_date,
    end_date,
    requested_leave_days,
    reason,
    supporting_document,
    leave_status,
    approved_at,
    rejected_at
)
VALUES

(
'00000000-0000-0000-0000-000000000011',
'JCF-MID-0011',
'Casual Leave',
CURRENT_DATE,
CURRENT_DATE + 1,
2,
'Family function',
NULL,
'APPROVED',
NOW() - INTERVAL '1 day',
NULL
),

(
'00000000-0000-0000-0000-000000000012',
'JCF-MID-0012',
'Sick Leave',
CURRENT_DATE + 5,
CURRENT_DATE + 6,
2,
'Fever',
NULL,
'PENDING',
NULL,
NULL
),

(
'00000000-0000-0000-0000-000000000014',
'JCF-MID-0014',
'Emergency Leave',
CURRENT_DATE + 2,
CURRENT_DATE + 2,
1,
'Medical emergency',
NULL,
'REJECTED',
NULL,
NOW() - INTERVAL '2 hours'
);


INSERT INTO internship_extensions (
    candidate_id,
    mid,
    extension_type,
    extension_value,
    reason,
    is_processed
)
VALUES

(
'00000000-0000-0000-0000-000000000011',
'JCF-MID-0011',
'MONTHS',
1,
'Performance improvement period',
TRUE
),

(
'00000000-0000-0000-0000-000000000014',
'JCF-MID-0014',
'LEAVE',
5,
'Approved leave extension',
FALSE
);


CREATE VIEW hr_dashboard_view AS
SELECT
    COUNT(DISTINCT c.candidate_id) AS total_candidates,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'HR_REVIEW_PENDING') AS hr_review_pending_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status IN ('WELCOME_MAIL_SENT', 'IN_PROBATION')) AS in_probation_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'PROBATION_REVIEW') AS probation_review_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'PROBATION_PASSED') AS probation_passed_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'PROBATION_REJECTED') AS probation_rejected_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'PROBATION_EXTENDED') AS probation_extended_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status IN ('PROBATION_PASSED', 'MID_GENERATED', 'OFFER_LETTER_GENERATED')) AS offer_letter_process_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE l.lifecycle_status = 'ACTIVE' OR o.offer_status = 'OFFER_LETTER_SENT') AS active_intern_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE s.signed_offer_status = 'SIGNED_OFFER_SUBMITTED') AS signed_offer_submitted_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE s.signed_offer_status = 'SIGNED_OFFER_VERIFIED') AS signed_offer_verified_count,
    COUNT(DISTINCT c.candidate_id) FILTER (WHERE s.signed_offer_status = 'MISMATCH_REVIEW') AS mismatch_review_count
FROM master_candidates c
LEFT JOIN hr_lifecycle l ON l.candidate_id = c.candidate_id
LEFT JOIN hr_offer_letters o ON o.candidate_id = c.candidate_id
LEFT JOIN signed_offer_verifications s ON s.candidate_id = c.candidate_id;

CREATE VIEW probation_review_view AS
SELECT
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    c.role_code,
    c.source,
    l.lifecycle_status AS probation_status,
    l.probation_start_date,
    l.probation_end_date,
    l.internship_duration_months,
    l.original_end_date,
    l.current_end_date,
    l.probation_extension_count,
    l.probation_review_notes,
    l.hr_decision,
    l.mid,
    l.created_at,
    l.updated_at
FROM master_candidates c
JOIN hr_lifecycle l ON l.candidate_id = c.candidate_id
WHERE l.lifecycle_status IN (
    'HR_REVIEW_PENDING',
    'HR_APPROVED_FOR_PROBATION',
    'WELCOME_MAIL_SENT',
    'IN_PROBATION',
    'PROBATION_REVIEW',
    'PROBATION_PASSED',
    'PROBATION_REJECTED',
    'PROBATION_EXTENDED'
);

CREATE VIEW offer_letter_process_view AS
SELECT
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    l.lifecycle_status,
    l.hr_decision,
    l.mid,
    o.offer_status,
    o.offer_letter_number,
    o.generated_at,
    o.sent_at
FROM master_candidates c
JOIN hr_lifecycle l ON l.candidate_id = c.candidate_id
LEFT JOIN hr_offer_letters o ON o.candidate_id = c.candidate_id
WHERE l.lifecycle_status IN (
        'PROBATION_PASSED',
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED'
   );

CREATE VIEW active_interns_view AS
SELECT
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    l.lifecycle_status,
    l.mid,
    o.offer_letter_number,
    o.sent_at AS offer_letter_sent_at,
    s.signed_offer_status,
    s.signed_offer_submitted_at,
    s.verified_at
FROM master_candidates c
JOIN hr_lifecycle l ON l.candidate_id = c.candidate_id
LEFT JOIN hr_offer_letters o ON o.candidate_id = c.candidate_id
LEFT JOIN signed_offer_verifications s ON s.candidate_id = c.candidate_id
WHERE l.lifecycle_status = 'ACTIVE'
   OR o.offer_status = 'OFFER_LETTER_SENT';

CREATE VIEW signed_offer_verification_view AS
SELECT
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    l.lifecycle_status,
    s.signed_offer_status,
    s.signed_offer_submitted_at,
    s.verified_at,
    s.email_match_status,
    s.phone_match_status,
    s.verification_notes,
    CASE
        WHEN s.email_match_status = 'MATCH' AND s.phone_match_status = 'MATCH' THEN 'MATCH'
        WHEN s.email_match_status IS NULL OR s.phone_match_status IS NULL THEN 'PENDING'
        ELSE 'MISMATCH'
    END AS overall_match_status
FROM master_candidates c
JOIN signed_offer_verifications s ON s.candidate_id = c.candidate_id
LEFT JOIN hr_lifecycle l ON l.candidate_id = c.candidate_id;

CREATE VIEW candidate_detail_view AS
SELECT
    c.candidate_id,
    c.first_name,
    c.last_name,
    c.full_name,
    c.email,
    c.phone,
    c.alternate_phone,
    c.address,
    c.city,
    c.state,
    c.applied_role,
    c.role_code,
    c.department,
    c.qualification,
    c.college_name,
    c.source,
    c.referral_name,
    c.availability_status,
    c.notes,

    l.lifecycle_status,
    l.probation_start_date,
    l.probation_end_date,

    l.original_end_date,
    l.current_end_date,
    l.internship_duration_months,
    l.total_extension_months,
    l.total_internship_duration_days,
    l.current_internship_duration_days,
    l.probation_extension_count,

    l.probation_review_notes,
    l.hr_decision,
    l.mid,
    l.updated_at AS lifecycle_updated_at,

    o.offer_status,
    o.offer_letter_number,
    o.generated_at,
    o.sent_at,

    s.signed_offer_status,
    s.signed_offer_submitted_at,
    s.verified_at,
    s.email_match_status,
    s.phone_match_status,
    s.verification_notes,

    lb.allocated_leave_days,
    lb.approved_leave_days,
    lb.remaining_leave_days,
    lb.extra_leave_days,

    CASE
        WHEN s.email_match_status='MATCH'
         AND s.phone_match_status='MATCH'
            THEN 'MATCH'
        WHEN s.email_match_status IS NULL
          OR s.phone_match_status IS NULL
            THEN 'PENDING'
        ELSE 'MISMATCH'
    END AS overall_match_status

FROM master_candidates c
LEFT JOIN hr_lifecycle l
ON c.candidate_id = l.candidate_id

LEFT JOIN hr_offer_letters o
ON c.candidate_id = o.candidate_id

LEFT JOIN signed_offer_verifications s
ON c.candidate_id = s.candidate_id

LEFT JOIN leave_balances lb
ON c.candidate_id = lb.candidate_id;


CREATE VIEW activity_log_view AS
SELECT
    a.activity_log_id,
    a.candidate_id,
    c.full_name,
    c.email,
    a.activity_type,
    a.from_status,
    a.to_status,
    a.remarks,
    a.activity_status,
    a.error_message,
    a.metadata,
    a.performed_by,
    a.performed_at
FROM hr_activity_logs a
JOIN master_candidates c ON c.candidate_id = a.candidate_id;


CREATE VIEW leave_requests_view AS
SELECT
    lr.leave_request_id,
    lr.candidate_id,
    lr.mid,
    mc.full_name,
    mc.email,
    mc.applied_role,
    hl.lifecycle_status,
    lr.leave_type,
    lr.start_date,
    lr.end_date,
    lr.requested_leave_days,
    lr.reason,
    lr.supporting_document,
    lr.leave_status,
    lr.approved_at,
    lr.rejected_at
FROM leave_requests lr
JOIN master_candidates mc
    ON lr.candidate_id = mc.candidate_id
JOIN hr_lifecycle hl
    ON lr.candidate_id = hl.candidate_id;


CREATE VIEW leave_balance_view AS
SELECT
    lb.candidate_id,
    lb.mid,
    mc.full_name,
    mc.applied_role,
    lb.allocated_leave_days,
    lb.approved_leave_days,
    lb.remaining_leave_days,
    lb.extra_leave_days
FROM leave_balances lb
JOIN master_candidates mc
ON lb.candidate_id = mc.candidate_id;

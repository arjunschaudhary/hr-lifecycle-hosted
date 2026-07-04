ALTER TABLE hr_lifecycle
ADD COLUMN IF NOT EXISTS probation_extension_count INTEGER DEFAULT 0;

CREATE OR REPLACE VIEW candidate_detail_view AS
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
    l.probation_extension_count,

    l.probation_review_notes,
    l.hr_decision,
    l.mid,

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

CREATE OR REPLACE VIEW probation_review_view AS
SELECT
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
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

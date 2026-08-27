ALTER TABLE master_candidates
ADD COLUMN IF NOT EXISTS role_code VARCHAR(20);

ALTER TABLE hr_lifecycle
ADD COLUMN IF NOT EXISTS total_extension_months INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_internship_duration_days INTEGER,
ADD COLUMN IF NOT EXISTS current_internship_duration_days INTEGER;

ALTER TABLE internship_extensions
ALTER COLUMN mid DROP NOT NULL;

DROP VIEW IF EXISTS candidate_detail_view;

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
    l.total_extension_months AS extension_months,
    (COALESCE(l.total_extension_months, 0) * 30) AS extension_duration_days,
    l.total_internship_duration_days,
    COALESCE(
        l.total_internship_duration_days,
        (l.internship_duration_months * 30) + (COALESCE(l.total_extension_months, 0) * 30)
    ) AS total_duration_days,
    (
        COALESCE(
            l.total_internship_duration_days,
            (l.internship_duration_months * 30) + (COALESCE(l.total_extension_months, 0) * 30)
        ) / 30
    ) AS total_internship_duration_months,
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

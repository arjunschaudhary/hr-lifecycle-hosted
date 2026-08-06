/*
=========================================================
HR LIFECYCLE V1
EXIT MANAGEMENT MODULE
Migration : 20260731_exit_module.sql
Part 1
=========================================================
*/

---------------------------------------------------------
-- EXTENSION
---------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;

---------------------------------------------------------
-- UPDATED_AT TRIGGER FUNCTION
---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

---------------------------------------------------------
-- TABLE 1
-- EXIT CASES
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exit_cases
(
    exit_case_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    candidate_id UUID NOT NULL,

    lifecycle_id UUID NOT NULL,

    pod_id UUID,

    initiated_by UUID,

    mid VARCHAR(50),

    pod_name_snapshot TEXT,

    exit_date DATE NOT NULL,

    exit_type VARCHAR(30) NOT NULL,

    overall_status VARCHAR(30)
        NOT NULL
        DEFAULT 'INITIATED',

    candidate_form_completed BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    hr_form_completed BOOLEAN
        NOT NULL
        DEFAULT FALSE,

    exit_completed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_exit_case_candidate
        FOREIGN KEY(candidate_id)
        REFERENCES master_candidates(candidate_id),

    CONSTRAINT fk_exit_case_lifecycle
        FOREIGN KEY(lifecycle_id)
        REFERENCES hr_lifecycle(lifecycle_id),

    CONSTRAINT fk_exit_case_pod
        FOREIGN KEY(pod_id)
        REFERENCES pods(id),

    CONSTRAINT fk_exit_case_initiated_by
        FOREIGN KEY(initiated_by)
        REFERENCES users(id),

    CONSTRAINT chk_exit_type
        CHECK
        (
            exit_type IN
            (
                'COMPLETED_TERM',
                'EARLY_EXIT',
                'TERMINATED'
            )
        ),

    CONSTRAINT chk_exit_status
        CHECK
        (
            overall_status IN
            (
                'INITIATED',
                'CANDIDATE_PENDING',
                'HR_PENDING',
                'COMPLETED'
            )
        )
);

---------------------------------------------------------
-- INDEXES
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_exit_cases_candidate
ON public.exit_cases(candidate_id);

CREATE INDEX IF NOT EXISTS idx_exit_cases_lifecycle
ON public.exit_cases(lifecycle_id);

CREATE INDEX IF NOT EXISTS idx_exit_cases_status
ON public.exit_cases(overall_status);

CREATE INDEX IF NOT EXISTS idx_exit_cases_pod
ON public.exit_cases(pod_id);

CREATE INDEX IF NOT EXISTS idx_exit_cases_exit_date
ON public.exit_cases(exit_date);

---------------------------------------------------------
-- COMMENTS
---------------------------------------------------------

COMMENT ON TABLE public.exit_cases
IS 'Master workflow table for every intern exit process.';

COMMENT ON COLUMN public.exit_cases.exit_type
IS 'Completed Term / Early Exit / Terminated';

COMMENT ON COLUMN public.exit_cases.overall_status
IS 'Workflow state of the exit process';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_exit_cases_updated_at
BEFORE UPDATE
ON public.exit_cases
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

---------------------------------------------------------
-- TABLE 2
-- CANDIDATE EXIT FEEDBACK
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.candidate_exit_feedback
(
    feedback_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    exit_case_id UUID
        NOT NULL
        UNIQUE,

    candidate_id UUID
        NOT NULL,

    -----------------------------------------------------
    -- EXIT INFORMATION
    -----------------------------------------------------

    completed_full_duration BOOLEAN,

    primary_exit_reason TEXT,

    other_exit_reasons TEXT[],

    other_reason_text TEXT,

    preventable_exit VARCHAR(30),

    wanted_extension VARCHAR(40),

    extension_reason TEXT,

    -----------------------------------------------------
    -- LEARNING
    -----------------------------------------------------

    overall_experience_rating INTEGER,

    nps_score INTEGER,

    expectation_match VARCHAR(30),

    learning_rating INTEGER,

    meaningful_work VARCHAR(30),

    missing_exposure TEXT[],

    missing_exposure_other TEXT,

    -----------------------------------------------------
    -- MENTORSHIP
    -----------------------------------------------------

    guidance_rating INTEGER,

    feedback_frequency VARCHAR(30),

    psychological_safety_rating INTEGER,

    valued_contributor_rating INTEGER,

    work_distribution_rating INTEGER,

    pod_culture_rating INTEGER,

    -----------------------------------------------------
    -- SAFETY
    -----------------------------------------------------

    safety_issue VARCHAR(20),

    safety_issue_details TEXT,

    is_confidential BOOLEAN
        DEFAULT FALSE,

    -----------------------------------------------------
    -- HR COMMUNICATION
    -----------------------------------------------------

    hr_communication_issues TEXT[],

    hr_communication_other TEXT,

    -----------------------------------------------------
    -- FINAL FEEDBACK
    -----------------------------------------------------

    improvement_suggestions TEXT[],

    improvement_other TEXT,

    rejoin_interest VARCHAR(20),

    -----------------------------------------------------
    -- METADATA
    -----------------------------------------------------

    submitted_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    -----------------------------------------------------
    -- FOREIGN KEYS
    -----------------------------------------------------

    CONSTRAINT fk_candidate_feedback_exit_case
        FOREIGN KEY(exit_case_id)
        REFERENCES public.exit_cases(exit_case_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_candidate_feedback_candidate
        FOREIGN KEY(candidate_id)
        REFERENCES public.master_candidates(candidate_id),

    -----------------------------------------------------
    -- CHECKS
    -----------------------------------------------------

    CONSTRAINT chk_nps
        CHECK
        (
            nps_score BETWEEN 0 AND 10
        ),

    CONSTRAINT chk_overall_rating
        CHECK
        (
            overall_experience_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_learning_rating
        CHECK
        (
            learning_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_guidance_rating
        CHECK
        (
            guidance_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_psychological_safety
        CHECK
        (
            psychological_safety_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_valued_rating
        CHECK
        (
            valued_contributor_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_work_distribution
        CHECK
        (
            work_distribution_rating BETWEEN 1 AND 5
        ),

    CONSTRAINT chk_pod_culture
        CHECK
        (
            pod_culture_rating BETWEEN 1 AND 5
        )
);

---------------------------------------------------------
-- INDEXES
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_candidate_feedback_candidate
ON public.candidate_exit_feedback(candidate_id);

CREATE INDEX IF NOT EXISTS idx_candidate_feedback_exit_case
ON public.candidate_exit_feedback(exit_case_id);

CREATE INDEX IF NOT EXISTS idx_candidate_feedback_rejoin
ON public.candidate_exit_feedback(rejoin_interest);

CREATE INDEX IF NOT EXISTS idx_candidate_feedback_primary_reason
ON public.candidate_exit_feedback(primary_exit_reason);

---------------------------------------------------------
-- COMMENTS
---------------------------------------------------------

COMMENT ON TABLE public.candidate_exit_feedback
IS 'Candidate submitted exit feedback questionnaire.';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_candidate_feedback_updated_at
BEFORE UPDATE
ON public.candidate_exit_feedback
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();


---------------------------------------------------------
-- TABLE 3
-- HR EXIT EVALUATIONS
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.hr_exit_evaluations
(
    evaluation_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    exit_case_id UUID
        NOT NULL
        UNIQUE,

    reviewer_id UUID
        NOT NULL,

    -----------------------------------------------------
    -- PERFORMANCE RATINGS
    -----------------------------------------------------

    skill_rating INTEGER,

    communication_rating INTEGER,

    ownership_rating INTEGER,

    reliability_rating INTEGER,

    collaboration_rating INTEGER,

    adaptability_rating INTEGER,

    timeliness_rating INTEGER,

    independence_rating INTEGER,

    -----------------------------------------------------
    -- EXIT CONTEXT
    -----------------------------------------------------

    hr_primary_reason TEXT,

    hr_other_reasons TEXT[],

    hr_preventable VARCHAR(30),

    retention_attempt BOOLEAN
        DEFAULT FALSE,

    retention_notes TEXT,

    extension_offer VARCHAR(30),

    lead_extension_recommendation VARCHAR(30),

    -----------------------------------------------------
    -- DECISION FIELDS
    -----------------------------------------------------

    certificate_recommendation VARCHAR(20),

    certificate_condition TEXT,

    lor_recommendation VARCHAR(20),

    lor_condition TEXT,

    rehire_eligibility VARCHAR(20),

    internal_notes TEXT,

    candidate_summary TEXT,

    -----------------------------------------------------
    -- KNOWLEDGE TRANSFER
    -----------------------------------------------------

    handover_complete VARCHAR(20),

    handover_method TEXT[],

    handover_gap TEXT,

    verified_by UUID,

    -----------------------------------------------------
    -- METADATA
    -----------------------------------------------------

    submitted_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    -----------------------------------------------------
    -- FOREIGN KEYS
    -----------------------------------------------------

    CONSTRAINT fk_hr_eval_exit_case
        FOREIGN KEY(exit_case_id)
        REFERENCES public.exit_cases(exit_case_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_hr_eval_reviewer
        FOREIGN KEY(reviewer_id)
        REFERENCES public.users(id),

    CONSTRAINT fk_hr_eval_verified_by
        FOREIGN KEY(verified_by)
        REFERENCES public.users(id),

    -----------------------------------------------------
    -- CHECKS
    -----------------------------------------------------

    CONSTRAINT chk_skill_rating
        CHECK (skill_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_communication_rating
        CHECK (communication_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_ownership_rating
        CHECK (ownership_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_reliability_rating
        CHECK (reliability_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_collaboration_rating
        CHECK (collaboration_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_adaptability_rating
        CHECK (adaptability_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_timeliness_rating
        CHECK (timeliness_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_independence_rating
        CHECK (independence_rating BETWEEN 1 AND 5)
);

---------------------------------------------------------
-- INDEXES
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_hr_eval_exit_case
ON public.hr_exit_evaluations(exit_case_id);

CREATE INDEX IF NOT EXISTS idx_hr_eval_reviewer
ON public.hr_exit_evaluations(reviewer_id);

CREATE INDEX IF NOT EXISTS idx_hr_eval_rehire
ON public.hr_exit_evaluations(rehire_eligibility);

---------------------------------------------------------
-- COMMENT
---------------------------------------------------------

COMMENT ON TABLE public.hr_exit_evaluations
IS 'HR evaluation submitted after candidate exit feedback.';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_hr_exit_evaluations_updated_at
BEFORE UPDATE
ON public.hr_exit_evaluations
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();





---------------------------------------------------------
-- TABLE 4
-- EXIT HANDOVER ITEMS
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exit_handover_items
(
    handover_item_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    exit_case_id UUID
        NOT NULL,

    task_name TEXT
        NOT NULL,

    task_status TEXT,

    next_steps TEXT,

    successor_name TEXT,

    repository_link TEXT,

    transfer_documents TEXT,

    access_to_revoke TEXT,

    time_sensitive_notes TEXT,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_handover_exit_case
        FOREIGN KEY(exit_case_id)
        REFERENCES public.exit_cases(exit_case_id)
        ON DELETE CASCADE
);

---------------------------------------------------------
-- INDEX
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_handover_exit_case
ON public.exit_handover_items(exit_case_id);

---------------------------------------------------------
-- COMMENT
---------------------------------------------------------

COMMENT ON TABLE public.exit_handover_items
IS 'One row represents one project/task handed over during exit.';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_exit_handover_updated_at
BEFORE UPDATE
ON public.exit_handover_items
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();





---------------------------------------------------------
-- TABLE 5
-- EXIT CLEARANCE
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exit_clearance
(
    clearance_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    exit_case_id UUID
        NOT NULL
        UNIQUE,

    certificate_generated BOOLEAN
        DEFAULT FALSE,

    lor_generated BOOLEAN
        DEFAULT FALSE,

    github_removed BOOLEAN
        DEFAULT FALSE,

    slack_removed BOOLEAN
        DEFAULT FALSE,

    email_removed BOOLEAN
        DEFAULT FALSE,

    drive_access_removed BOOLEAN
        DEFAULT FALSE,

    assets_returned BOOLEAN
        DEFAULT FALSE,

    final_clearance_status VARCHAR(30)
        DEFAULT 'PENDING',

    cleared_by UUID,

    cleared_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_clearance_exit_case
        FOREIGN KEY(exit_case_id)
        REFERENCES public.exit_cases(exit_case_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_clearance_user
        FOREIGN KEY(cleared_by)
        REFERENCES public.users(id),

    CONSTRAINT chk_clearance_status
        CHECK
        (
            final_clearance_status IN
            (
                'PENDING',
                'IN_PROGRESS',
                'COMPLETED'
            )
        )
);

---------------------------------------------------------
-- INDEX
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_clearance_exit_case
ON public.exit_clearance(exit_case_id);

---------------------------------------------------------
-- COMMENT
---------------------------------------------------------

COMMENT ON TABLE public.exit_clearance
IS 'Tracks operational closure of intern exit.';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_exit_clearance_updated_at
BEFORE UPDATE
ON public.exit_clearance
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();





---------------------------------------------------------
-- TABLE 6
-- EXIT DOCUMENTS
---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exit_documents
(
    document_id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    exit_case_id UUID
        NOT NULL,

    document_type VARCHAR(30)
        NOT NULL,

    storage_path TEXT
        NOT NULL,

    uploaded_by UUID,

    uploaded_at TIMESTAMPTZ
        DEFAULT NOW(),

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_exit_document_case
        FOREIGN KEY(exit_case_id)
        REFERENCES public.exit_cases(exit_case_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_exit_document_user
        FOREIGN KEY(uploaded_by)
        REFERENCES public.users(id),

    CONSTRAINT chk_document_type
        CHECK
        (
            document_type IN
            (
                'CERTIFICATE',
                'LOR',
                'EXIT_LETTER',
                'EXIT_REPORT'
            )
        )
);

---------------------------------------------------------
-- INDEXES
---------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_exit_documents_case
ON public.exit_documents(exit_case_id);

CREATE INDEX IF NOT EXISTS idx_exit_documents_type
ON public.exit_documents(document_type);

---------------------------------------------------------
-- COMMENT
---------------------------------------------------------

COMMENT ON TABLE public.exit_documents
IS 'Stores generated exit-related documents.';

---------------------------------------------------------
-- TRIGGER
---------------------------------------------------------

CREATE TRIGGER trg_exit_documents_updated_at
BEFORE UPDATE
ON public.exit_documents
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
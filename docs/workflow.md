# HR Lifecycle V1 Workflow

## Objective

This module manages the HR lifecycle from candidate probation submission to active intern status and signed offer verification.

## V1 Workflow

1. Candidate submits the public probation form.
2. Candidate record is created with status `HR_REVIEW_PENDING`.
3. HR reviews the submitted form.
4. If HR approves the candidate for probation, probation is initiated.
5. Welcome mail is sent.
6. Candidate enters probation with status `IN_PROBATION`.
7. HR reviews probation after the probation period.
8. HR can pass, reject, or extend probation.
9. If rejected, the candidate can be reconsidered through a new probation attempt.
10. If probation is passed, the system automatically starts the offer letter process.
11. MID is generated using `ROLE_CODE / NAME_CODE / SERIAL` format.
12. Offer letter is generated.
13. Offer letter is sent to the candidate.
14. Candidate becomes an active intern after offer letter is sent.
15. Candidate submits signed offer letter.
16. HR verifies or rejects the signed offer.
17. Signed offer verification does not affect active intern status.
18. Signed offer status will matter later for certificate/LOR eligibility.

## Important Business Rules

- Candidate form is public for V1.
- HR login is required for review and approval.
- Candidate becomes active after offer letter is sent.
- Signed offer is a separate process and does not block active status.
- Rejected candidates can have a new probation attempt.
- MID is generated automatically after probation is passed.
- Offer letter PDF will be stored in Google Drive for V1.
- Supabase will store data, status, and file links.


- There is no separate offer approval stage in V1.
- `Probation Passed` directly triggers MID generation, offer letter generation, and offer letter sending.
export const ELIGIBLE_LEAVE_STATUSES = [
  "HR_APPROVED_FOR_PROBATION",
  "WELCOME_MAIL_SENT",
  "IN_PROBATION",
  "PROBATION_REVIEW",
  "PROBATION_EXTENDED",
  "PROBATION_PASSED",
  "MID_GENERATED",
  "OFFER_LETTER_GENERATED",
  "OFFER_LETTER_SENT",
  "ACTIVE",
  "SIGNED_OFFER_SUBMITTED",
  "SIGNED_OFFER_VERIFIED",
  "MISMATCH_REVIEW",
];

function parseDateOnly(dateValue, fieldName = "date") {
  const [year, month, day] = String(dateValue || "")
    .split("-")
    .map(Number);

  if (!year || !month || !day) {
    throw new Error(`A valid ${fieldName} is required.`);
  }

  return new Date(Date.UTC(year, month - 1, day));
}

function formatDateOnly(dateValue) {
  return dateValue.toISOString().split("T")[0];
}

function addCalendarDays(dateValue, daysToAdd) {
  const date = parseDateOnly(dateValue);
  date.setUTCDate(date.getUTCDate() + Number(daysToAdd || 0));

  return formatDateOnly(date);
}

function addDaysSkippingSundays(dateValue, daysToAdd) {
  const date = parseDateOnly(dateValue);
  let countedDays = 0;

  while (countedDays < Number(daysToAdd || 0)) {
    date.setUTCDate(date.getUTCDate() + 1);

    if (date.getUTCDay() !== 0) {
      countedDays += 1;
    }
  }

  return formatDateOnly(date);
}

export function calculateLeaveDays(startDate, endDate) {
  const start = parseDateOnly(startDate, "start date");
  const end = parseDateOnly(endDate, "end date");

  if (start > end) {
    throw new Error("Start Date cannot be after End Date.");
  }

  let days = 0;
  const current = new Date(start);

  while (current <= end) {
    if (current.getUTCDay() !== 0) {
      days += 1;
    }

    current.setUTCDate(current.getUTCDate() + 1);
  }

  return days;
}

export function getInternshipDurationDays(durationMonths) {
  const normalizedDuration = Number(durationMonths);

  if (!Number.isFinite(normalizedDuration) || normalizedDuration <= 0) {
    throw new Error("Internship duration is required for leave calculation.");
  }

  return normalizedDuration * 30;
}

export function calculateAllocatedLeaveDays(
  durationMonths,
  extensionMonths = 0
) {
  const normalizedDuration = Number(durationMonths);
  const normalizedExtensionMonths = Number(extensionMonths || 0);

  if (normalizedDuration === 3) {
    return 9 + normalizedExtensionMonths * 3;
  }

  if (normalizedDuration === 4) {
    return 15 + normalizedExtensionMonths * 3;
  }

  throw new Error("Leave entitlement is defined only for 3 or 4 month internships.");
}

export function calculateRemainingLeaveDays(
  allocatedLeaveDays,
  approvedLeaveDays
) {
  return Math.max(
    Number(allocatedLeaveDays || 0) - Number(approvedLeaveDays || 0),
    0
  );
}

export function calculateLeaveApprovalBalance({
  allocatedLeaveDays,
  approvedLeaveDays,
  extraLeaveDays,
  requestedLeaveDays,
}) {
  const allocated = Number(allocatedLeaveDays || 0);
  const existingApproved = Number(approvedLeaveDays || 0);
  const existingExtra = Number(extraLeaveDays || 0);
  const requested = Number(requestedLeaveDays || 0);

  const availableWithinEntitlement = Math.max(
    allocated - existingApproved,
    0
  );
  const approvedPortion = Math.min(requested, availableWithinEntitlement);
  const extraPortion = Math.max(requested - approvedPortion, 0);
  const nextApproved = existingApproved + approvedPortion;
  const nextExtra = existingExtra + extraPortion;

  return {
    approved_leave_days: nextApproved,
    remaining_leave_days: calculateRemainingLeaveDays(allocated, nextApproved),
    extra_leave_days: nextExtra,
  };
}

export function calculateCurrentEndDate({
  probationStartDate,
  durationMonths,
  extensionMonths = 0,
  approvedLeaveDays = 0,
  extraLeaveDays = 0,
}) {
  const totalDurationDays =
    getInternshipDurationDays(durationMonths) +
    Number(extensionMonths || 0) * 30;
  const leaveImpact =
    Number(approvedLeaveDays || 0) + Number(extraLeaveDays || 0);
  const baseEndDate = addCalendarDays(probationStartDate, totalDurationDays);

  return addDaysSkippingSundays(baseEndDate, leaveImpact);
}

export function getTodayKolkataString() {
  const options = { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" };
  const formatter = new Intl.DateTimeFormat("en-CA", options);
  return formatter.format(new Date());
}


/**
 * exitAnalyticsService.js
 * Supabase service layer for fetching and calculating Exit Analytics data.
 * Contains no React code or UI state.
 */

import { supabase } from "./supabaseClient";
import { EXIT_REASONS } from "../constants/exitFormOptions";

const EXIT_ANALYTICS_LOAD_ERROR = "Unable to load exit analytics cases.";
const EXIT_DETAILS_LOAD_ERROR = "Unable to load the completed Exit record.";
const SAFE_EXIT_ANALYTICS_MESSAGES = new Set([
  "Authorized HR access is required.",
  "Exit analytics filters must be a valid object.",
  "Exit analytics filters are too large.",
  "One or more Exit analytics filters are invalid.",
  "One or more Exit analytics filters are too long.",
  "Exit analytics start date is invalid.",
  "Exit analytics end date is invalid.",
  "One or more Exit analytics dates are invalid.",
]);

function getSafeRpcMessage(error, fallbackMessage, safeMessages) {
  const message =
    error && typeof error.message === "string" ? error.message.trim() : "";

  return safeMessages.has(message) ? message : fallbackMessage;
}

/**
 * Fetches the non-confidential raw Exit analytics data exposed by the secure RPC.
 */
export async function fetchExitRawData(filters = {}) {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error("Supabase client is not configured.");
  }

  const serverFilters = {};
  ["exitType", "overallStatus", "startDate", "endDate"].forEach((key) => {
    if (filters[key]) {
      serverFilters[key] = filters[key];
    }
  });

  const { data, error } = await supabase.rpc("get_exit_analytics", {
    p_filters: serverFilters,
  });

  if (error) {
    throw new Error(
      getSafeRpcMessage(
        error,
        EXIT_ANALYTICS_LOAD_ERROR,
        SAFE_EXIT_ANALYTICS_MESSAGES,
      ),
    );
  }

  return {
    exitCases: data?.exitCases || [],
    candidateFeedbacks: data?.candidateFeedbacks || [],
    hrEvaluations: data?.hrEvaluations || [],
    handoverItems: data?.handoverItems || [],
  };
}

/**
 * Computes descriptive exit analytics metrics from raw Supabase data according to active filters.
 */
export async function getExitAnalyticsData(filters = {}) {
  const { exitCases, candidateFeedbacks, hrEvaluations, handoverItems } =
    await fetchExitRawData(filters);

  // Maps for quick lookup by exit_case_id
  const feedbackMap = {};
  candidateFeedbacks.forEach((fb) => {
    feedbackMap[fb.exit_case_id] = fb;
  });

  const hrEvalMap = {};
  hrEvaluations.forEach((ev) => {
    hrEvalMap[ev.exit_case_id] = ev;
  });

  const handoverMap = {};
  handoverItems.forEach((item) => {
    if (!handoverMap[item.exit_case_id]) {
      handoverMap[item.exit_case_id] = [];
    }
    handoverMap[item.exit_case_id].push(item);
  });

  // Client-side filtering for Department, Completed Internship, Rehire Eligibility
  const filteredCases = exitCases.filter((item) => {
    const candidateDept =
      item.pod_name_snapshot || item.master_candidates?.department || "Unassigned";

    if (
      filters.department &&
      filters.department !== "ALL" &&
      candidateDept !== filters.department
    ) {
      return false;
    }

    const fb = feedbackMap[item.exit_case_id];
    if (filters.completedInternship && filters.completedInternship !== "ALL") {
      if (filters.completedInternship === "yes" && fb?.completed_full_duration !== true) {
        return false;
      }
      if (filters.completedInternship === "no" && fb?.completed_full_duration !== false) {
        return false;
      }
    }

    const hrEval = hrEvalMap[item.exit_case_id];
    if (filters.rehireEligibility && filters.rehireEligibility !== "ALL") {
      if (hrEval?.rehire_eligibility !== filters.rehireEligibility) {
        return false;
      }
    }

    return true;
  });

  // Unique list of departments for filter dropdown
  const allDepartments = Array.from(
    new Set(
      exitCases.map(
        (c) => c.pod_name_snapshot || c.master_candidates?.department || "Unassigned"
      )
    )
  ).sort();

  // ---------------------------------------------------------------------------
  // 1. SUMMARY CARDS
  // ---------------------------------------------------------------------------
  const totalExits = filteredCases.length;
  const completedExitProcess = filteredCases.filter(
    (c) => c.overall_status === "COMPLETED"
  ).length;
  const pendingCandidateForms = filteredCases.filter(
    (c) => !c.candidate_form_completed
  ).length;
  const pendingHRReviews = filteredCases.filter(
    (c) => c.candidate_form_completed && !c.hr_form_completed
  ).length;

  let totalExpRating = 0;
  let expRatingCount = 0;
  let totalNpsScore = 0;
  let npsCount = 0;
  let totalPerfRatingSum = 0;
  let perfRatingCount = 0;
  let preventableCount = 0;
  let totalPreventableAnswered = 0;

  filteredCases.forEach((c) => {
    const fb = feedbackMap[c.exit_case_id];
    if (fb) {
      if (typeof fb.overall_experience_rating === "number") {
        totalExpRating += fb.overall_experience_rating;
        expRatingCount++;
      }
      if (typeof fb.nps_score === "number") {
        totalNpsScore += fb.nps_score;
        npsCount++;
      }
      if (fb.preventable_exit) {
        totalPreventableAnswered++;
        if (
          fb.preventable_exit === "definitely_yes" ||
          fb.preventable_exit === "probably_yes" ||
          fb.preventable_exit === "YES"
        ) {
          preventableCount++;
        }
      }
    }

    const hrEval = hrEvalMap[c.exit_case_id];
    if (hrEval) {
      const perfRatings = [
        hrEval.skill_rating,
        hrEval.communication_rating,
        hrEval.ownership_rating,
        hrEval.reliability_rating,
        hrEval.collaboration_rating,
        hrEval.adaptability_rating,
        hrEval.timeliness_rating,
        hrEval.independence_rating,
      ].filter((r) => typeof r === "number" && r > 0);

      if (perfRatings.length > 0) {
        const avgForEval =
          perfRatings.reduce((a, b) => a + b, 0) / perfRatings.length;
        totalPerfRatingSum += avgForEval;
        perfRatingCount++;
      }
    }
  });

  const avgOverallExperience =
    expRatingCount > 0 ? (totalExpRating / expRatingCount).toFixed(1) : "0.0";
  const avgNps = npsCount > 0 ? (totalNpsScore / npsCount).toFixed(1) : "0.0";
  const avgPerformanceRating =
    perfRatingCount > 0
      ? (totalPerfRatingSum / perfRatingCount).toFixed(1)
      : "0.0";
  const preventableExitPercentage =
    totalPreventableAnswered > 0
      ? Math.round((preventableCount / totalPreventableAnswered) * 100)
      : 0;

  const summary = {
    totalExits,
    completedExitProcess,
    pendingCandidateForms,
    pendingHRReviews,
    avgOverallExperience: parseFloat(avgOverallExperience),
    avgNps: parseFloat(avgNps),
    avgPerformanceRating: parseFloat(avgPerformanceRating),
    preventableExitPercentage,
  };

  // ---------------------------------------------------------------------------
  // 2. SECTION 1: EXIT REASONS
  // ---------------------------------------------------------------------------
  const REASON_LABELS = Object.fromEntries(
    EXIT_REASONS.map(({ value, label }) => [value, label]),
  );

  const reasonCounts = {};
  Object.keys(REASON_LABELS).forEach((key) => {
    reasonCounts[key] = 0;
  });

  filteredCases.forEach((c) => {
    const fb = feedbackMap[c.exit_case_id];
    if (fb?.primary_exit_reason) {
      const r = fb.primary_exit_reason;
      if (reasonCounts[r] !== undefined) {
        reasonCounts[r]++;
      } else {
        reasonCounts["other"] = (reasonCounts["other"] || 0) + 1;
      }
    }
  });

  const exitReasons = Object.keys(REASON_LABELS).map((key) => ({
    key,
    label: REASON_LABELS[key],
    count: reasonCounts[key] || 0,
  }));

  // ---------------------------------------------------------------------------
  // 3. SECTION 2: EXIT TREND (Monthly)
  // ---------------------------------------------------------------------------
  const monthlyTrendMap = {};
  filteredCases.forEach((c) => {
    if (c.exit_date) {
      const monthKey = c.exit_date.substring(0, 7); // YYYY-MM
      monthlyTrendMap[monthKey] = (monthlyTrendMap[monthKey] || 0) + 1;
    }
  });

  const sortedMonths = Object.keys(monthlyTrendMap).sort();
  const exitTrend = sortedMonths.map((m) => ({
    month: m,
    count: monthlyTrendMap[m],
  }));

  // ---------------------------------------------------------------------------
  // 4. SECTION 3: EXPERIENCE ANALYTICS
  // ---------------------------------------------------------------------------
  let sumExp = 0,
    sumLearn = 0,
    sumGuidance = 0,
    sumSafety = 0,
    sumCulture = 0,
    sumDist = 0,
    sumValued = 0;
  let countExp = 0,
    countLearn = 0,
    countGuidance = 0,
    countSafety = 0,
    countCulture = 0,
    countDist = 0,
    countValued = 0;

  filteredCases.forEach((c) => {
    const fb = feedbackMap[c.exit_case_id];
    if (fb) {
      if (fb.overall_experience_rating) {
        sumExp += fb.overall_experience_rating;
        countExp++;
      }
      if (fb.learning_rating) {
        sumLearn += fb.learning_rating;
        countLearn++;
      }
      if (fb.guidance_rating) {
        sumGuidance += fb.guidance_rating;
        countGuidance++;
      }
      if (fb.psychological_safety_rating) {
        sumSafety += fb.psychological_safety_rating;
        countSafety++;
      }
      if (fb.pod_culture_rating) {
        sumCulture += fb.pod_culture_rating;
        countCulture++;
      }
      if (fb.work_distribution_rating) {
        sumDist += fb.work_distribution_rating;
        countDist++;
      }
      if (fb.valued_contributor_rating) {
        sumValued += fb.valued_contributor_rating;
        countValued++;
      }
    }
  });

  const experienceRatings = [
    { label: "Overall Experience", rating: countExp ? (sumExp / countExp).toFixed(1) : 0 },
    { label: "Learning Rating", rating: countLearn ? (sumLearn / countLearn).toFixed(1) : 0 },
    { label: "Guidance Rating", rating: countGuidance ? (sumGuidance / countGuidance).toFixed(1) : 0 },
    { label: "Psychological Safety", rating: countSafety ? (sumSafety / countSafety).toFixed(1) : 0 },
    { label: "Pod Culture", rating: countCulture ? (sumCulture / countCulture).toFixed(1) : 0 },
    { label: "Work Distribution", rating: countDist ? (sumDist / countDist).toFixed(1) : 0 },
    { label: "Valued Contributor", rating: countValued ? (sumValued / countValued).toFixed(1) : 0 },
  ];

  // ---------------------------------------------------------------------------
  // 5. SECTION 4: NPS BREAKDOWN
  // ---------------------------------------------------------------------------
  let promoters = 0,
    passives = 0,
    detractors = 0,
    npsTotal = 0;

  filteredCases.forEach((c) => {
    const fb = feedbackMap[c.exit_case_id];
    if (typeof fb?.nps_score === "number") {
      npsTotal++;
      if (fb.nps_score >= 9) promoters++;
      else if (fb.nps_score >= 7) passives++;
      else detractors++;
    }
  });

  const promoterPct = npsTotal > 0 ? Math.round((promoters / npsTotal) * 100) : 0;
  const passivePct = npsTotal > 0 ? Math.round((passives / npsTotal) * 100) : 0;
  const detractorPct = npsTotal > 0 ? Math.round((detractors / npsTotal) * 100) : 0;
  const netNpsScore = promoterPct - detractorPct;

  const npsSummary = {
    averageNps: summary.avgNps,
    netNpsScore,
    promoters,
    passives,
    detractors,
    promoterPct,
    passivePct,
    detractorPct,
    totalResponses: npsTotal,
  };

  // ---------------------------------------------------------------------------
  // 6. SECTION 5: PREVENTABLE EXITS CHART
  // ---------------------------------------------------------------------------
  const preventableCounts = {
    definitely_yes: 0,
    probably_yes: 0,
    not_sure: 0,
    probably_not: 0,
    definitely_not: 0,
    not_applicable: 0,
  };

  filteredCases.forEach((c) => {
    const fb = feedbackMap[c.exit_case_id];
    if (fb?.preventable_exit) {
      const p = fb.preventable_exit.toLowerCase();
      if (preventableCounts[p] !== undefined) {
        preventableCounts[p]++;
      } else {
        preventableCounts.not_sure++;
      }
    }
  });

  const preventableData = [
    { label: "Definitely Yes", key: "definitely_yes", count: preventableCounts.definitely_yes, color: "#ef4444" },
    { label: "Probably Yes", key: "probably_yes", count: preventableCounts.probably_yes, color: "#f97316" },
    { label: "Not Sure", key: "not_sure", count: preventableCounts.not_sure, color: "#eab308" },
    { label: "Probably Not", key: "probably_not", count: preventableCounts.probably_not, color: "#3b82f6" },
    { label: "Definitely Not", key: "definitely_not", count: preventableCounts.definitely_not, color: "#22c55e" },
    { label: "Not Applicable", key: "not_applicable", count: preventableCounts.not_applicable, color: "#64748b" },
  ];

  // ---------------------------------------------------------------------------
  // 7. SECTION 6: PERFORMANCE RATINGS (8 Dimensions)
  // ---------------------------------------------------------------------------
  const perfSum = {
    Skill: 0,
    Communication: 0,
    Ownership: 0,
    Reliability: 0,
    Collaboration: 0,
    Adaptability: 0,
    Timeliness: 0,
    Independence: 0,
  };
  const perfCount = {
    Skill: 0,
    Communication: 0,
    Ownership: 0,
    Reliability: 0,
    Collaboration: 0,
    Adaptability: 0,
    Timeliness: 0,
    Independence: 0,
  };

  filteredCases.forEach((c) => {
    const ev = hrEvalMap[c.exit_case_id];
    if (ev) {
      if (ev.skill_rating) { perfSum.Skill += ev.skill_rating; perfCount.Skill++; }
      if (ev.communication_rating) { perfSum.Communication += ev.communication_rating; perfCount.Communication++; }
      if (ev.ownership_rating) { perfSum.Ownership += ev.ownership_rating; perfCount.Ownership++; }
      if (ev.reliability_rating) { perfSum.Reliability += ev.reliability_rating; perfCount.Reliability++; }
      if (ev.collaboration_rating) { perfSum.Collaboration += ev.collaboration_rating; perfCount.Collaboration++; }
      if (ev.adaptability_rating) { perfSum.Adaptability += ev.adaptability_rating; perfCount.Adaptability++; }
      if (ev.timeliness_rating) { perfSum.Timeliness += ev.timeliness_rating; perfCount.Timeliness++; }
      if (ev.independence_rating) { perfSum.Independence += ev.independence_rating; perfCount.Independence++; }
    }
  });

  const performanceDimensions = Object.keys(perfSum).map((dimension) => ({
    dimension,
    score: perfCount[dimension] ? parseFloat((perfSum[dimension] / perfCount[dimension]).toFixed(1)) : 0,
  }));

  // ---------------------------------------------------------------------------
  // 8. SECTION 7: KNOWLEDGE TRANSFER (HR Evaluation Data ONLY)
  // ---------------------------------------------------------------------------
  const ktCounts = { YES: 0, PARTIAL: 0, NO: 0, NOT_APPLICABLE: 0 };
  const methodCounts = {
    live_meeting: 0,
    whatsapp: 0,
    email: 0,
    shared_document: 0,
    not_done: 0,
    other: 0,
  };
  let gapsIdentifiedCount = 0;
  let verifiedByCount = 0;
  let totalHrEvaluationsCount = 0;
  let totalHrHandoverItems = 0;

  filteredCases.forEach((c) => {
    const ev = hrEvalMap[c.exit_case_id];
    if (ev) {
      totalHrEvaluationsCount++;

      if (ev.handover_complete) {
        const hc = ev.handover_complete.toUpperCase();
        if (hc === "YES") ktCounts.YES++;
        else if (hc === "PARTIALLY" || hc === "PARTIAL") ktCounts.PARTIAL++;
        else if (hc === "NO") ktCounts.NO++;
        else if (hc === "NOT_APPLICABLE") ktCounts.NOT_APPLICABLE++;
      }

      if (Array.isArray(ev.handover_method)) {
        ev.handover_method.forEach((m) => {
          const key = m.toLowerCase();
          if (methodCounts[key] !== undefined) {
            methodCounts[key]++;
          } else {
            methodCounts.other++;
          }
        });
      }

      if (ev.handover_gap && ev.handover_gap.trim()) {
        gapsIdentifiedCount++;
      }

      if (ev.verified_by) {
        verifiedByCount++;
      }
    }

    const items = handoverMap[c.exit_case_id] || [];
    if (items.length > 0) {
      totalHrHandoverItems += items.length;
    }
  });

  const totalEval = totalHrEvaluationsCount || 1;
  const knowledgeTransfer = {
    completeStatus: ktCounts,
    methodCounts,
    gapsIdentifiedCount,
    gapsIdentifiedPct: Math.round((gapsIdentifiedCount / totalEval) * 100),
    verifiedByCount,
    verificationPct: Math.round((verifiedByCount / totalEval) * 100),
    totalHrEvaluationsCount,
    totalHrHandoverItems,
    avgHrItemsPerCase: (totalHrHandoverItems / totalEval).toFixed(1),
  };

  // ---------------------------------------------------------------------------
  // 9. SECTION 8: DEPARTMENT ANALYTICS
  // ---------------------------------------------------------------------------
  const deptDataMap = {};

  filteredCases.forEach((c) => {
    const dept = c.pod_name_snapshot || c.master_candidates?.department || "Unassigned";

    if (!deptDataMap[dept]) {
      deptDataMap[dept] = {
        department: dept,
        totalExits: 0,
        expSum: 0,
        expCount: 0,
        perfSum: 0,
        perfCount: 0,
        npsSum: 0,
        npsCount: 0,
        preventableCount: 0,
      };
    }

    const d = deptDataMap[dept];
    d.totalExits++;

    const fb = feedbackMap[c.exit_case_id];
    if (fb) {
      if (typeof fb.overall_experience_rating === "number") {
        d.expSum += fb.overall_experience_rating;
        d.expCount++;
      }
      if (typeof fb.nps_score === "number") {
        d.npsSum += fb.nps_score;
        d.npsCount++;
      }
      if (
        fb.preventable_exit === "definitely_yes" ||
        fb.preventable_exit === "probably_yes" ||
        fb.preventable_exit === "YES"
      ) {
        d.preventableCount++;
      }
    }

    const ev = hrEvalMap[c.exit_case_id];
    if (ev) {
      const pRatings = [
        ev.skill_rating, ev.communication_rating, ev.ownership_rating,
        ev.reliability_rating, ev.collaboration_rating, ev.adaptability_rating,
        ev.timeliness_rating, ev.independence_rating,
      ].filter((r) => typeof r === "number" && r > 0);

      if (pRatings.length > 0) {
        d.perfSum += pRatings.reduce((a, b) => a + b, 0) / pRatings.length;
        d.perfCount++;
      }
    }
  });

  const departmentAnalytics = Object.values(deptDataMap).map((d) => ({
    department: d.department,
    totalExits: d.totalExits,
    avgExperience: d.expCount ? parseFloat((d.expSum / d.expCount).toFixed(1)) : 0,
    avgPerformance: d.perfCount ? parseFloat((d.perfSum / d.perfCount).toFixed(1)) : 0,
    avgNps: d.npsCount ? parseFloat((d.npsSum / d.npsCount).toFixed(1)) : 0,
    preventablePct: d.totalExits ? Math.round((d.preventableCount / d.totalExits) * 100) : 0,
  }));

  // ---------------------------------------------------------------------------
  // 10. SECTION 9: PENDING WORKFLOW TABLE
  // ---------------------------------------------------------------------------
  const pendingWorkflow = filteredCases
    .filter((c) => c.overall_status !== "COMPLETED")
    .map((c) => ({
      exitCaseId: c.exit_case_id,
      candidateName: c.master_candidates?.full_name || "Unknown Candidate",
      mid: c.mid || "N/A",
      exitType: c.exit_type,
      overallStatus: c.overall_status,
      candidateFormCompleted: c.candidate_form_completed,
      hrFormCompleted: c.hr_form_completed,
      exitDate: c.exit_date,
    }));

  // ---------------------------------------------------------------------------
  // 11. SECTION 10: COMPLETED EXIT CASE RECORDS TABLE
  // ---------------------------------------------------------------------------
  const completedExitRecords = filteredCases
    .filter((c) => c.overall_status === "COMPLETED")
    .map((c) => {
      const ev = hrEvalMap[c.exit_case_id];
      const evalDate = ev?.submitted_at
        ? ev.submitted_at.substring(0, 10)
        : c.exit_completed_at
        ? c.exit_completed_at.substring(0, 10)
        : c.exit_date || "—";

      return {
        exitCaseId: c.exit_case_id,
        candidateName: c.master_candidates?.full_name || "Unknown Candidate",
        mid: c.mid || "N/A",
        department: c.pod_name_snapshot || c.master_candidates?.department || "N/A",
        exitType: c.exit_type ? c.exit_type.replaceAll("_", " ") : "N/A",
        exitDate: c.exit_date || "N/A",
        candidateFormCompleted: Boolean(c.candidate_form_completed),
        hrFormCompleted: Boolean(c.hr_form_completed),
        reviewedBy: ev?.reviewer_id ? "HR Reviewer" : "HR Evaluator",
        evaluationDate: evalDate,
      };
    });

  return {
    allDepartments,
    summary,
    exitReasons,
    exitTrend,
    experienceRatings,
    npsSummary,
    preventableData,
    performanceDimensions,
    knowledgeTransfer,
    departmentAnalytics,
    pendingWorkflow,
    completedExitRecords,
  };
}

/**
 * Fetch complete historical record details (Candidate Questionnaire + HR Evaluation) for a completed exit case.
 */
export async function getCompletedExitCaseDetails(exitCaseId) {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error("Supabase client is not configured.");
  }

  if (!exitCaseId) {
    throw new Error("Exit case record not found.");
  }

  const { data, error } = await supabase.rpc(
    "get_completed_exit_case_details",
    { p_exit_case_id: exitCaseId },
  );

  if (error || !data?.exitCase) {
    const message =
      error?.message?.trim() === "Completed Exit case was not found."
        ? "Exit case record not found."
        : EXIT_DETAILS_LOAD_ERROR;
    throw new Error(message);
  }

  const exitCaseRaw = data.exitCase;
  const candidateFeedback = data.candidateFeedback || null;
  const hrEvaluation = data.hrEvaluation || null;
  const handoverItems = data.handoverItems || [];
  const reviewerName = data.reviewer?.name || "HR Evaluator";
  const reviewerRole = data.reviewer?.role || "HR Executive";
  const verifierName = data.verifier?.name || reviewerName;

  const candidateProfile = exitCaseRaw.master_candidates || {};
  const lifecycleInfo = exitCaseRaw.hr_lifecycle || {};

  return {
    exitCase: {
      exitCaseId: exitCaseRaw.exit_case_id,
      candidateId: exitCaseRaw.candidate_id,
      mid: exitCaseRaw.mid || "—",
      exitDate: exitCaseRaw.exit_date || "—",
      exitType: exitCaseRaw.exit_type || "—",
      overallStatus: exitCaseRaw.overall_status || "—",
      candidateFormCompleted: Boolean(exitCaseRaw.candidate_form_completed),
      hrFormCompleted: Boolean(exitCaseRaw.hr_form_completed),
      exitCompletedAt: exitCaseRaw.exit_completed_at || exitCaseRaw.created_at,
    },
    profile: {
      fullName: candidateProfile.full_name || "—",
      email: candidateProfile.email || "—",
      phone: candidateProfile.phone || "—",
      department: exitCaseRaw.pod_name_snapshot || candidateProfile.department || "—",
      mid: exitCaseRaw.mid || "—",
      startDate: lifecycleInfo.probation_start_date || null,
      endDate: lifecycleInfo.current_end_date || lifecycleInfo.original_end_date || null,
      internshipDurationMonths: lifecycleInfo.internship_duration_months || null,
    },
    candidateFeedback,
    hrEvaluation,
    handoverItems,
    reviewer: { name: reviewerName, role: reviewerRole },
    verifier: { name: verifierName },
  };
}

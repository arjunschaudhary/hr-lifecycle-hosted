import { supabase } from "./supabaseClient";

const leaveDashboardService = {
  // ===============================
  // Dashboard Counts
  // ===============================
  async getDashboardCounts() {
    const today = new Date().toISOString().split("T")[0];

    const [
      pending,
      approved,
      rejected,
      onLeaveToday,
      upcoming
    ] = await Promise.all([
      supabase
        .from("leave_requests")
        .select("*", { count: "exact", head: true })
        .eq("leave_status", "PENDING"),

      supabase
        .from("leave_requests")
        .select("*", { count: "exact", head: true })
        .eq("leave_status", "APPROVED"),

      supabase
        .from("leave_requests")
        .select("*", { count: "exact", head: true })
        .eq("leave_status", "REJECTED"),

      supabase
        .from("leave_requests")
        .select("*", { count: "exact", head: true })
        .eq("leave_status", "APPROVED")
        .lte("start_date", today)
        .gte("end_date", today),

      supabase
        .from("leave_requests")
        .select("*", { count: "exact", head: true })
        .eq("leave_status", "APPROVED")
        .gt("start_date", today),
    ]);
    if (
      pending.error ||
      approved.error ||
      rejected.error ||
      onLeaveToday.error ||
      upcoming.error
    ) {
      throw (
        pending.error ||
        approved.error ||
        rejected.error ||
        onLeaveToday.error ||
        upcoming.error
      );
    }

    return {
      pending: pending.count || 0,
      approved: approved.count || 0,
      rejected: rejected.count || 0,
      onLeaveToday: onLeaveToday.count || 0,
      upcomingLeaves: upcoming.count || 0,
    };
  },

  // ===============================
  // Pending Leave Requests
  // ===============================
  async getPendingLeaves() {
    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .eq("leave_status", "PENDING")
      .order("start_date", { ascending: true });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Approved Leaves
  // ===============================
  async getApprovedLeaves() {
    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .eq("leave_status", "APPROVED")
      .order("start_date", { ascending: false });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Rejected Leaves
  // ===============================
  async getRejectedLeaves() {
    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .eq("leave_status", "REJECTED")
      .order("start_date", { ascending: false });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Who is on Leave Today
  // ===============================
  async getOnLeaveToday() {
    const today = new Date().toISOString().split("T")[0];

    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .eq("leave_status", "APPROVED")
      .lte("start_date", today)
      .gte("end_date", today)
      .order("start_date", { ascending: true });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Upcoming Leaves
  // ===============================
  async getUpcomingLeaves() {
    const today = new Date().toISOString().split("T")[0];

    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .eq("leave_status", "APPROVED")
      .gt("start_date", today)
      .order("start_date", { ascending: true });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Leave History
  // ===============================
  async getAllLeaveRequests() {
    const { data, error } = await supabase
      .from("leave_requests_view")
      .select("*")
      .order("start_date", { ascending: false });

    if (error) throw error;

    return data;
  },

  // ===============================
  // Leave Balance
  // ===============================
  async getLeaveBalances() {
    const { data, error } = await supabase
      .from("leave_balance_view")
      .select("*")
      .order("full_name");

    if (error) throw error;

    return data;
  },

  // ===============================
  // Single Candidate Leave Balance
  // ===============================
  async getCandidateLeaveBalance(candidateId) {
    const { data, error } = await supabase
      .from("leave_balance_view")
      .select("*")
      .eq("candidate_id", candidateId)
      .single();

    if (error) throw error;

    return data;
  }
};

export default leaveDashboardService;
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, FocusDashboard, FocusState } from "@/lib/supabase/types";

/** Explain an unapplied migration without exposing raw schema-cache errors in the UI. */
export function focusError(error: unknown): string {
  const value = error as { code?: string; message?: string } | null;
  if (isMissingFocusApi(error)) {
    return "Focus isn't available yet. Your reminders still work. Try again after the app is updated.";
  }
  return value?.message ?? "Couldn't connect to Focus. Check your connection and retry.";
}

/** The RPC/table is not in the hosted schema yet (web deployed before migrations 0015/0016). */
export function isMissingFocusApi(error: unknown): boolean {
  return ["PGRST202", "PGRST205", "42P01", "42883"].includes((error as { code?: string } | null)?.code ?? "");
}

/** Blocked because a session is running ("Finish the current session first"). */
export const isSessionBlocked = (error: unknown) => (error as { code?: string } | null)?.code === "55000";

/**
 * Dashboard plus which migrations the hosted database has. Without 0015 (`preferences: false`) the
 * client behaves like the Focus MVP with a 25 min default; without 0016 (`times: false`) Focus times
 * and plans are hidden; without 0017 (`intents: false`) planned starts skip the intended outcome and
 * archiving a Focus time offers no Undo.
 */
export type FocusData = FocusDashboard & { api: { preferences: boolean; times: boolean; intents: boolean } };

/** When v2 was last seen missing: skip the doomed call on every refresh, but look again every 5 minutes. */
let v2MissingAt = 0;

export async function fetchFocusDashboard(supabase: SupabaseClient<Database>): Promise<FocusData> {
  const v2 = Date.now() - v2MissingAt < 300_000 ? null : await supabase.rpc("get_focus_dashboard_v2");
  if (v2 && !v2.error) {
    v2MissingAt = 0;
    const data = v2.data as unknown as Partial<FocusDashboard> & FocusState;
    // 0015 without 0016 returns no focus_times/assignments.
    const times = Array.isArray(data.focus_times);
    return {
      ...data,
      preferred_minutes: data.preferred_minutes ?? 25,
      highlight_next_step: data.highlight_next_step ?? null,
      session_next_step: data.session_next_step ?? null,
      focus_times: times ? data.focus_times! : [],
      assignments: times && Array.isArray(data.assignments) ? data.assignments : [],
      api: { preferences: true, times, intents: times && (data.focus_api ?? 0) >= 17 },
    };
  }
  if (v2 && !["PGRST202", "42883"].includes(v2.error!.code ?? "")) throw v2.error;
  v2MissingAt = Date.now();
  const { data, error } = await supabase.rpc("get_focus_state");
  if (error) throw error;
  return {
    ...(data as unknown as FocusState),
    preferred_minutes: 25, highlight_next_step: null, session_next_step: null, focus_times: [], assignments: [],
    api: { preferences: false, times: false, intents: false },
  };
}

export async function fetchFocusNextStep(supabase: SupabaseClient<Database>, reminderId: string): Promise<string | null> {
  const { data, error } = await supabase.from("focus_sessions")
    .select("next_step")
    .eq("reminder_id", reminderId)
    .not("finished_at", "is", null)
    .order("finished_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data?.next_step ?? null;
}

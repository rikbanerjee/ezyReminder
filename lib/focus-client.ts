import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, FocusState } from "@/lib/supabase/types";

/** Explain an unapplied migration without exposing raw schema-cache errors in the UI. */
export function focusError(error: unknown): string {
  const value = error as { code?: string; message?: string } | null;
  if (["PGRST202", "PGRST205", "42P01", "42883"].includes(value?.code ?? "")) {
    return "Focus isn't available yet. Your reminders still work. Try again after the app is updated.";
  }
  return value?.message ?? "Couldn't connect to Focus. Check your connection and retry.";
}

export async function fetchFocusState(supabase: SupabaseClient<Database>): Promise<FocusState> {
  const { data, error } = await supabase.rpc("get_focus_state");
  if (error) throw error;
  return data as unknown as FocusState;
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

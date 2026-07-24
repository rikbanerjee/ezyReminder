import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import type { HomeSidegigDetails } from "@/components/home/types";

/** Side Gig initiative-details rows keyed by reminder_id (server-only). */
export async function fetchSidegigDetailsMap(
  supabase: SupabaseClient<Database>,
): Promise<Map<string, HomeSidegigDetails>> {
  const { data } = await supabase.from("sidegig_details").select("reminder_id, initiative_name, client_name");

  const map = new Map<string, HomeSidegigDetails>();
  for (const s of data ?? []) {
    map.set(s.reminder_id, {
      initiativeName: s.initiative_name,
      clientName: s.client_name,
    });
  }
  return map;
}

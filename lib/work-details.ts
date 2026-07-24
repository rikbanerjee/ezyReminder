import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import type { HomeWorkDetails } from "@/components/home/types";

/** Work-details rows keyed by reminder_id, for attaching to HomeReminder (server-only). */
export async function fetchWorkDetailsMap(supabase: SupabaseClient<Database>): Promise<Map<string, HomeWorkDetails>> {
  const { data } = await supabase
    .from("work_details")
    .select("reminder_id, manager_name, department_resource, project_name");

  const map = new Map<string, HomeWorkDetails>();
  for (const w of data ?? []) {
    map.set(w.reminder_id, {
      managerName: w.manager_name,
      departmentResource: w.department_resource,
      projectName: w.project_name,
    });
  }
  return map;
}

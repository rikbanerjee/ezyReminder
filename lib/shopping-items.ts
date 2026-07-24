import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import type { HomeShoppingItem } from "@/components/home/types";

/** Shopping checklist items grouped by reminder_id, ordered by position (server-only). */
export async function fetchShoppingItemsMap(
  supabase: SupabaseClient<Database>,
): Promise<Map<string, HomeShoppingItem[]>> {
  const { data } = await supabase
    .from("shopping_items")
    .select("id, reminder_id, label, checked")
    .order("position", { ascending: true });

  const map = new Map<string, HomeShoppingItem[]>();
  for (const item of data ?? []) {
    const list = map.get(item.reminder_id) ?? [];
    list.push({ id: item.id, label: item.label, checked: item.checked });
    map.set(item.reminder_id, list);
  }
  return map;
}

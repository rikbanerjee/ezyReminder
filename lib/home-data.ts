import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import type { HomeContext, HomeReminder } from "@/components/home/types";
import { fetchOrdersMap } from "@/lib/orders";
import { fetchWorkDetailsMap } from "@/lib/work-details";
import { fetchSidegigDetailsMap } from "@/lib/sidegig-details";
import { fetchShoppingItemsMap } from "@/lib/shopping-items";

/** Shared by the Today (/) and All (/all) screens — both render HomeView. */
export async function fetchHomeData(supabase: SupabaseClient<Database>): Promise<{
  contexts: HomeContext[];
  reminders: HomeReminder[];
  doneToday: HomeReminder[];
  shipSoonCount: number;
}> {
  const { data: contextRows } = await supabase
    .from("contexts")
    .select("id, slug, name, color, default_channel")
    .order("name");

  const contexts: HomeContext[] = (contextRows ?? []) as HomeContext[];
  const contextById = new Map(contexts.map((c) => [c.id, c]));

  const reminderSelect =
    "id, title, notes, due_at, snoozed_until, status, channels, is_order, context_id";

  const { data: activeRows } = await supabase
    .from("reminders")
    .select(reminderSelect)
    .in("status", ["open", "snoozed"])
    .order("due_at", { ascending: true, nullsFirst: false });

  const since = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
  const { data: doneRows } = await supabase
    .from("reminders")
    .select(reminderSelect)
    .eq("status", "done")
    .gte("updated_at", since)
    .order("updated_at", { ascending: false });

  type Row = {
    id: string;
    title: string;
    notes: string | null;
    due_at: string | null;
    snoozed_until: string | null;
    status: HomeReminder["status"];
    channels: HomeReminder["channels"];
    is_order: boolean;
    context_id: string;
  };

  const { data: failedRows } = await supabase
    .from("notifications")
    .select("id, reminder_id")
    .eq("status", "failed")
    .order("updated_at", { ascending: false });

  const failedByReminder = new Map<string, string>();
  for (const n of failedRows ?? []) {
    if (!failedByReminder.has(n.reminder_id)) failedByReminder.set(n.reminder_id, n.id);
  }

  const ordersByReminder = await fetchOrdersMap(supabase);
  const workDetailsByReminder = await fetchWorkDetailsMap(supabase);
  const sidegigDetailsByReminder = await fetchSidegigDetailsMap(supabase);
  const shoppingItemsByReminder = await fetchShoppingItemsMap(supabase);

  const toReminder = (r: Row): HomeReminder => ({
    id: r.id,
    title: r.title,
    notes: r.notes,
    due_at: r.due_at,
    snoozed_until: r.snoozed_until,
    status: r.status,
    channels: r.channels ?? [],
    is_order: r.is_order,
    context: contextById.get(r.context_id) ?? null,
    failedNotificationId: failedByReminder.get(r.id) ?? null,
    order: ordersByReminder.get(r.id) ?? null,
    workDetails: workDetailsByReminder.get(r.id) ?? null,
    sidegigDetails: sidegigDetailsByReminder.get(r.id) ?? null,
    shoppingItems: shoppingItemsByReminder.get(r.id) ?? [],
  });

  const reminders = ((activeRows ?? []) as Row[]).map(toReminder);
  const doneToday = ((doneRows ?? []) as Row[]).map(toReminder);

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  const shipSoonCount = [...ordersByReminder.values()].filter((o) => {
    if (!o.shipBy || o.shippedAt) return false;
    const days = Math.round((new Date(`${o.shipBy}T00:00:00`).getTime() - todayStart.getTime()) / 86_400_000);
    return days <= 3;
  }).length;

  return { contexts, reminders, doneToday, shipSoonCount };
}

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import type { HomeOrder } from "@/components/home/types";

/** Order rows keyed by reminder_id, for attaching to HomeReminder (server-only). */
export async function fetchOrdersMap(supabase: SupabaseClient<Database>): Promise<Map<string, HomeOrder>> {
  const { data } = await supabase
    .from("orders")
    .select("reminder_id, order_ref, recipient_name, ship_by, carrier, tracking_number, shipped_at");

  const map = new Map<string, HomeOrder>();
  for (const o of data ?? []) {
    map.set(o.reminder_id, {
      orderRef: o.order_ref,
      recipientName: o.recipient_name,
      shipBy: o.ship_by,
      carrier: o.carrier,
      trackingNumber: o.tracking_number,
      shippedAt: o.shipped_at,
    });
  }
  return map;
}

import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ShipQueueView } from "@/components/ship-queue/ship-queue-view";
import type { ShipQueueRow } from "@/components/ship-queue/types";

/** Ship Queue (PLAN.md §5.2, DESIGN.md §4.3) — orders sorted by ship-by date. */
export default async function ShipQueuePage() {
  const supabase = await createClient();

  const orderSelect = "reminder_id, order_ref, recipient_name, ship_by, carrier, tracking_number, shipped_at, reminder:reminders(title, context:contexts(name, color))";

  const [{ data: pendingRows }, { data: shippedRows }] = await Promise.all([
    supabase.from("orders").select(orderSelect).is("shipped_at", null),
    supabase
      .from("orders")
      .select(orderSelect)
      .not("shipped_at", "is", null)
      .gte("shipped_at", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
      .order("shipped_at", { ascending: false }),
  ]);

  type Raw = {
    reminder_id: string;
    order_ref: string | null;
    recipient_name: string | null;
    ship_by: string | null;
    carrier: string | null;
    tracking_number: string | null;
    shipped_at: string | null;
    reminder: { title: string; context: { name: string; color: string } | null } | null;
  };

  const toRow = (o: Raw): ShipQueueRow => ({
    reminderId: o.reminder_id,
    title: o.reminder?.title ?? "(deleted reminder)",
    context: o.reminder?.context ?? null,
    orderRef: o.order_ref,
    recipientName: o.recipient_name,
    shipBy: o.ship_by,
    carrier: o.carrier,
    trackingNumber: o.tracking_number,
    shippedAt: o.shipped_at,
  });

  const pending = ((pendingRows ?? []) as unknown as Raw[]).map(toRow);
  const shippedThisWeek = ((shippedRows ?? []) as unknown as Raw[]).map(toRow);

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-5 px-4 py-8">
      <header className="flex items-center gap-2">
        <Link href="/" className="grid size-8 place-items-center rounded-lg text-text-2 hover:bg-muted" aria-label="Back">
          <ArrowLeft className="size-4" />
        </Link>
        <h1 className="text-[20px] font-bold tracking-tight">Ship Queue</h1>
      </header>

      <ShipQueueView pending={pending} shippedThisWeek={shippedThisWeek} />
    </main>
  );
}

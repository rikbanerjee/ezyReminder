"use client";

import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { ShipQueueRowItem } from "./ship-queue-row";
import { daysUntilShipBy, type ShipQueueRow } from "./types";
import { cn } from "@/lib/utils";

export function ShipQueueView({ pending, shippedThisWeek }: { pending: ShipQueueRow[]; shippedThisWeek: ShipQueueRow[] }) {
  const [showShipped, setShowShipped] = useState(false);

  const sorted = [...pending].sort((a, b) => {
    const da = daysUntilShipBy(a);
    const db = daysUntilShipBy(b);
    if (da === null && db === null) return 0;
    if (da === null) return 1;
    if (db === null) return -1;
    return da - db;
  });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between px-1">
        <h2 className="text-[15px] font-semibold">Ship Queue ({sorted.length})</h2>
      </div>

      {sorted.length === 0 ? (
        <p className="px-1 py-8 text-center text-[15px] text-text-2">Nothing to ship. Flag a reminder with #order.</p>
      ) : (
        <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3">
          {sorted.map((row) => (
            <ShipQueueRowItem key={row.reminderId} row={row} />
          ))}
        </div>
      )}

      {shippedThisWeek.length > 0 && (
        <section>
          <button
            type="button"
            onClick={() => setShowShipped((s) => !s)}
            className="flex w-full items-center gap-1 px-1 pb-1.5 pt-1 text-[13px] font-semibold uppercase tracking-wide text-text-2"
          >
            <ChevronDown className={cn("size-3.5 transition-transform", !showShipped && "-rotate-90")} />
            Shipped this week
            <span className="text-text-2/70">{shippedThisWeek.length}</span>
          </button>
          {showShipped && (
            <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3">
              {shippedThisWeek.map((row) => (
                <ShipQueueRowItem key={row.reminderId} row={row} />
              ))}
            </div>
          )}
        </section>
      )}
    </div>
  );
}

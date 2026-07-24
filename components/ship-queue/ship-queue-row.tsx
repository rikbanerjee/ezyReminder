"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { markShipped, createFollowUp } from "@/app/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { daysUntilShipBy, formatShipBy, type ShipQueueRow } from "./types";

export function ShipQueueRowItem({ row }: { row: ShipQueueRow }) {
  const [showTracking, setShowTracking] = useState(false);
  const [tracking, setTracking] = useState("");
  const [carrier, setCarrier] = useState(row.carrier ?? "");
  const [pending, startTransition] = useTransition();

  const days = daysUntilShipBy(row);
  const overdue = days !== null && days < 0;

  function confirmShipped() {
    startTransition(async () => {
      const res = await markShipped(row.reminderId, tracking.trim(), carrier.trim() || null);
      if (!res.ok) {
        toast.error("Couldn't mark shipped", { description: res.error });
        return;
      }
      toast.success("Shipped ✓", {
        description: "Remind me to follow up?",
        action: {
          label: "+3d follow-up",
          onClick: () => {
            createFollowUp(row.reminderId).then((r) => {
              if (!r.ok) toast.error("Couldn't create follow-up", { description: r.error });
              else toast.success("Follow-up scheduled");
            });
          },
        },
      });
    });
  }

  return (
    <div className={cn("flex flex-col gap-2 py-2.5", pending && "opacity-50")}>
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 truncate text-[15px] font-medium">
            {row.context && <span className="size-2 shrink-0 rounded-full" style={{ backgroundColor: row.context.color }} />}
            <span className="truncate">{row.orderRef || row.title}</span>
            {row.recipientName && <span className="shrink-0 text-text-2">· {row.recipientName}</span>}
          </div>
          <div className="mt-0.5 text-[13px] text-text-2">
            {row.carrier || "no carrier set"}
            {row.trackingNumber ? ` · ${row.trackingNumber}` : ""}
          </div>
        </div>
        <span className={cn("shrink-0 text-[12px] font-semibold uppercase tracking-wide", overdue && !row.shippedAt && "text-danger")}>
          {row.shippedAt ? `Shipped ${new Date(row.shippedAt).toLocaleDateString(undefined, { month: "short", day: "numeric" })}` : formatShipBy(row)}
        </span>
      </div>

      {row.shippedAt ? null : showTracking ? (
        <div className="flex items-center gap-2">
          <Input value={carrier} onChange={(e) => setCarrier(e.target.value)} placeholder="Carrier (USPS…)" className="w-32" />
          <Input value={tracking} onChange={(e) => setTracking(e.target.value)} placeholder="Tracking #" className="flex-1" />
          <Button size="sm" disabled={pending} onClick={confirmShipped}>
            Confirm
          </Button>
        </div>
      ) : (
        <Button size="sm" variant="outline" className="self-start" disabled={pending} onClick={() => setShowTracking(true)}>
          Mark shipped
        </Button>
      )}
    </div>
  );
}

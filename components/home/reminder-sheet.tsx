"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { toast } from "sonner";
import { X, Trash2, Truck, Mail, MessageSquare, MessageCircle, Check, RotateCcw, Briefcase, Lightbulb } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  updateReminder,
  updateOrderDetails,
  updateWorkDetails,
  updateSidegigDetails,
  markShipped,
  deleteReminder,
  completeReminder,
  reopenReminder,
  createFollowUp,
} from "@/app/actions";
import type { Channel } from "@/lib/supabase/types";
import type { HomeContext, HomeReminder } from "./types";
import { ShoppingChecklist } from "./shopping-checklist";
import { cn } from "@/lib/utils";

const CHANNELS: { key: Channel; label: string; icon: typeof Mail }[] = [
  { key: "email", label: "Email", icon: Mail },
  { key: "slack", label: "Slack", icon: MessageSquare },
  { key: "whatsapp", label: "WhatsApp", icon: MessageCircle },
];

function toDatetimeLocal(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromDatetimeLocal(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/**
 * Editing an existing reminder (tapping a row, or the "Add details" toast
 * action right after quick-add creates one) — never the primary creation
 * path (DESIGN.md §5.1).
 */
export function ReminderSheet({
  reminder,
  contexts,
  scrollToOrderPanel,
  onClose,
}: {
  reminder: HomeReminder;
  contexts: HomeContext[];
  /** Opened via the post-create "Add order details?" toast action. */
  scrollToOrderPanel?: boolean;
  onClose: () => void;
}) {
  // Mounted closed, then flipped open next frame so the slide-up transition
  // actually runs (DESIGN.md §2 motion — 300ms cubic-bezier(0.32,0.72,0,1)).
  const [open, setOpen] = useState(false);
  useEffect(() => {
    let raf2 = 0;
    const raf1 = requestAnimationFrame(() => {
      raf2 = requestAnimationFrame(() => setOpen(true));
    });
    return () => {
      cancelAnimationFrame(raf1);
      cancelAnimationFrame(raf2);
    };
  }, []);

  function requestClose() {
    setOpen(false);
    window.setTimeout(onClose, 300);
  }

  const [title, setTitle] = useState(reminder.title);
  const [titleError, setTitleError] = useState(false);
  const [notes, setNotes] = useState(reminder.notes ?? "");
  const [dueLocal, setDueLocal] = useState(toDatetimeLocal(reminder.due_at));
  const [contextId, setContextId] = useState(reminder.context?.id ?? contexts[0]?.id ?? "");
  const [channels, setChannels] = useState<Channel[]>(reminder.channels);
  const [isOrder, setIsOrder] = useState(reminder.is_order);

  const [orderRef, setOrderRef] = useState(reminder.order?.orderRef ?? "");
  const [recipientName, setRecipientName] = useState(reminder.order?.recipientName ?? "");
  const [shipBy, setShipBy] = useState(reminder.order?.shipBy ?? "");
  const [carrier, setCarrier] = useState(reminder.order?.carrier ?? "");
  const [trackingInput, setTrackingInput] = useState("");
  const [showTrackingField, setShowTrackingField] = useState(false);

  const hasWorkDetails = !!(reminder.workDetails?.managerName || reminder.workDetails?.departmentResource || reminder.workDetails?.projectName);
  const [showWorkPanel, setShowWorkPanel] = useState(hasWorkDetails);
  const [managerName, setManagerName] = useState(reminder.workDetails?.managerName ?? "");
  const [departmentResource, setDepartmentResource] = useState(reminder.workDetails?.departmentResource ?? "");
  const [projectName, setProjectName] = useState(reminder.workDetails?.projectName ?? "");

  const hasSidegigDetails = !!(reminder.sidegigDetails?.initiativeName || reminder.sidegigDetails?.clientName);
  const [showSidegigPanel, setShowSidegigPanel] = useState(hasSidegigDetails);
  const [initiativeName, setInitiativeName] = useState(reminder.sidegigDetails?.initiativeName ?? "");
  const [clientName, setClientName] = useState(reminder.sidegigDetails?.clientName ?? "");

  const [pending, startTransition] = useTransition();

  const done = reminder.status === "done";
  const shipped = !!reminder.order?.shippedAt;
  const selectedContext = contexts.find((c) => c.id === contextId) ?? null;
  const isWork = selectedContext?.slug === "work";
  const isSidegig = selectedContext?.slug === "sidegig";
  const isShopping = selectedContext?.slug === "shopping";

  const orderPanelRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (open && scrollToOrderPanel) {
      orderPanelRef.current?.scrollIntoView({ block: "nearest" });
    }
  }, [open, scrollToOrderPanel]);

  function toggleChannel(ch: Channel) {
    setChannels((prev) => (prev.includes(ch) ? prev.filter((c) => c !== ch) : [...prev, ch]));
  }

  function save() {
    if (!title.trim()) {
      setTitleError(true);
      return;
    }
    startTransition(async () => {
      const res = await updateReminder({
        id: reminder.id,
        title,
        notes: notes.trim() || null,
        dueAt: fromDatetimeLocal(dueLocal),
        contextId,
        channels,
        isOrder,
      });
      if (!res.ok) {
        toast.error("Couldn't save", { description: res.error });
        return;
      }
      if (isOrder) {
        const orderRes = await updateOrderDetails({
          reminderId: reminder.id,
          orderRef: orderRef.trim() || null,
          recipientName: recipientName.trim() || null,
          shipBy: shipBy || null,
          carrier: carrier.trim() || null,
        });
        if (!orderRes.ok) {
          toast.error("Saved, but order details failed", { description: orderRes.error });
          return;
        }
      }
      if (isWork && showWorkPanel) {
        const workRes = await updateWorkDetails({
          reminderId: reminder.id,
          managerName: managerName.trim() || null,
          departmentResource: departmentResource.trim() || null,
          projectName: projectName.trim() || null,
        });
        if (!workRes.ok) {
          toast.error("Saved, but follow-up details failed", { description: workRes.error });
          return;
        }
      }
      if (isSidegig && !isOrder && showSidegigPanel) {
        const sidegigRes = await updateSidegigDetails({
          reminderId: reminder.id,
          initiativeName: initiativeName.trim() || null,
          clientName: clientName.trim() || null,
        });
        if (!sidegigRes.ok) {
          toast.error("Saved, but initiative details failed", { description: sidegigRes.error });
          return;
        }
      }
      toast.success("Saved");
      requestClose();
    });
  }

  function handleMarkShipped() {
    startTransition(async () => {
      const res = await markShipped(reminder.id, trackingInput.trim(), carrier.trim() || null);
      if (!res.ok) {
        toast.error("Couldn't mark shipped", { description: res.error });
        return;
      }
      toast.success("Shipped ✓", {
        description: "Remind me to follow up?",
        action: {
          label: "+3d follow-up",
          onClick: () => {
            createFollowUp(reminder.id).then((r) => {
              if (!r.ok) toast.error("Couldn't create follow-up", { description: r.error });
              else toast.success("Follow-up scheduled");
            });
          },
        },
      });
      requestClose();
    });
  }

  function handleDelete() {
    startTransition(async () => {
      const res = await deleteReminder(reminder.id);
      if (!res.ok) toast.error("Couldn't delete", { description: res.error });
      else requestClose();
    });
  }

  function handleToggleDone() {
    startTransition(async () => {
      const res = done ? await reopenReminder(reminder.id) : await completeReminder(reminder.id);
      if (!res.ok) toast.error("Couldn't update", { description: res.error });
      else requestClose();
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <div
        className={cn(
          "fixed inset-0 bg-black/40 transition-opacity duration-[250ms]",
          open ? "opacity-100" : "opacity-0",
        )}
        onClick={requestClose}
        aria-hidden
      />
      <div
        className={cn(
          "relative flex max-h-[85vh] w-full max-w-md flex-col overflow-y-auto rounded-t-[20px] bg-surface p-4 shadow-sheet transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] sm:rounded-[20px]",
          open ? "translate-y-0" : "translate-y-full",
        )}
      >
        <div className="mx-auto mb-3 h-1 w-10 shrink-0 rounded-full bg-hairline sm:hidden" />

        <div className="flex items-start justify-between gap-2">
          <input
            value={title}
            onChange={(e) => {
              setTitle(e.target.value);
              if (titleError) setTitleError(false);
            }}
            className={cn(
              "w-full rounded-md bg-transparent text-[20px] font-semibold outline-none",
              titleError && "rounded-md border border-danger px-1 -mx-1",
            )}
            placeholder="Reminder title"
          />
          <button type="button" onClick={requestClose} aria-label="Close" className="shrink-0 rounded-md p-1 text-text-2 hover:bg-muted">
            <X className="size-5" />
          </button>
        </div>
        {titleError && <p className="mt-1 text-[12px] font-medium text-danger">Title required</p>}

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select
            value={contextId}
            onChange={(e) => setContextId(e.target.value)}
            className="h-8 rounded-lg border border-input bg-transparent px-2 text-sm outline-none"
          >
            {contexts.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <input
            type="datetime-local"
            value={dueLocal}
            onChange={(e) => setDueLocal(e.target.value)}
            className="h-8 rounded-lg border border-input bg-transparent px-2 text-sm outline-none"
          />
        </div>

        {isShopping ? (
          <ShoppingChecklist reminderId={reminder.id} initialItems={reminder.shoppingItems} />
        ) : (
          <>
            <div className="mt-3">
              <Label className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-text-2">Notes</Label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={3}
                className="w-full resize-none rounded-lg border border-input bg-transparent p-2 text-sm outline-none placeholder:text-text-2"
                placeholder="Add notes…"
              />
            </div>

            <div className="mt-3">
              <Label className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-text-2">Deliver via</Label>
              <div className="flex gap-1.5">
                {CHANNELS.map(({ key, label, icon: Icon }) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => toggleChannel(key)}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1 text-[13px]",
                      channels.includes(key) ? "border-transparent bg-foreground text-background" : "border-hairline text-text-2",
                    )}
                  >
                    <Icon className="size-3.5" />
                    {label}
                  </button>
                ))}
              </div>
              <p className="mt-1 text-[12px] text-text-2">No selection uses the context&apos;s default channel.</p>
            </div>
          </>
        )}

        <div className={cn("mt-4 border-t border-hairline pt-3", isShopping && "hidden")} ref={orderPanelRef}>
          <PanelToggle icon={Truck} label="This is an order" on={isOrder} onToggle={() => setIsOrder((v) => !v)} />

          {isOrder && (
            <div className="mt-3 flex flex-col gap-2 rounded-lg border border-hairline p-2.5">
              <Field label="Order ref">
                <Input value={orderRef} onChange={(e) => setOrderRef(e.target.value)} placeholder="Etsy #1042" />
              </Field>
              <Field label="Recipient">
                <Input value={recipientName} onChange={(e) => setRecipientName(e.target.value)} placeholder="Sarah M." />
              </Field>
              <Field label="Ship by">
                <Input type="date" value={shipBy} onChange={(e) => setShipBy(e.target.value)} />
              </Field>
              <Field label="Carrier">
                <Input value={carrier} onChange={(e) => setCarrier(e.target.value)} placeholder="USPS" />
              </Field>

              {shipped ? (
                <p className="mt-1 text-[13px] text-text-2">
                  Shipped {reminder.order?.trackingNumber ? `· ${reminder.order.trackingNumber}` : ""}
                </p>
              ) : showTrackingField ? (
                <div className="mt-1 flex items-center gap-2">
                  <Input
                    value={trackingInput}
                    onChange={(e) => setTrackingInput(e.target.value)}
                    placeholder="Tracking #"
                    className="flex-1"
                  />
                  <Button size="sm" disabled={pending} onClick={handleMarkShipped}>
                    Confirm
                  </Button>
                </div>
              ) : (
                <Button size="sm" variant="outline" className="mt-1 self-start" onClick={() => setShowTrackingField(true)}>
                  Mark shipped
                </Button>
              )}
            </div>
          )}
        </div>

        {isWork && (
          <div className="mt-4 border-t border-hairline pt-3">
            <PanelToggle
              icon={Briefcase}
              label="Add follow-up details"
              on={showWorkPanel}
              onToggle={() => setShowWorkPanel((v) => !v)}
            />
            {showWorkPanel && (
              <div className="mt-3 flex flex-col gap-2 rounded-lg border border-hairline p-2.5">
                <Field label="Manager">
                  <Input value={managerName} onChange={(e) => setManagerName(e.target.value)} placeholder="Priya T." />
                </Field>
                <Field label="Dept/resource">
                  <Input value={departmentResource} onChange={(e) => setDepartmentResource(e.target.value)} placeholder="Design" />
                </Field>
                <Field label="Project">
                  <Input value={projectName} onChange={(e) => setProjectName(e.target.value)} placeholder="Q3 capacity plan" />
                </Field>
              </div>
            )}
          </div>
        )}

        {isSidegig && !isOrder && (
          <div className="mt-4 border-t border-hairline pt-3">
            <PanelToggle
              icon={Lightbulb}
              label="Add initiative details"
              on={showSidegigPanel}
              onToggle={() => setShowSidegigPanel((v) => !v)}
            />
            {showSidegigPanel && (
              <div className="mt-3 flex flex-col gap-2 rounded-lg border border-hairline p-2.5">
                <Field label="Initiative">
                  <Input value={initiativeName} onChange={(e) => setInitiativeName(e.target.value)} placeholder="Etsy shop refresh" />
                </Field>
                <Field label="Client/buyer">
                  <Input value={clientName} onChange={(e) => setClientName(e.target.value)} placeholder="Sarah M." />
                </Field>
              </div>
            )}
          </div>
        )}

        <div className="mt-5 flex items-center justify-between border-t border-hairline pt-3">
          <Button variant="ghost" size="sm" disabled={pending} onClick={handleDelete} className="text-danger">
            <Trash2 className="size-3.5" />
            Delete
          </Button>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" disabled={pending} onClick={handleToggleDone}>
              {done ? <RotateCcw className="size-3.5" /> : <Check className="size-3.5" />}
              {done ? "Reopen" : "Done"}
            </Button>
            <Button size="sm" disabled={pending} onClick={save}>
              Save
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-20 shrink-0 text-[13px] text-text-2">{label}</span>
      {children}
    </div>
  );
}

/** Toggle-reveal switch shared by the Order/Work/Side Gig detail panels (DESIGN.md §4.2). */
function PanelToggle({
  icon: Icon,
  label,
  on,
  onToggle,
}: {
  icon: typeof Truck;
  label: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button type="button" onClick={onToggle} className="flex w-full items-center justify-between text-[14px] font-medium">
      <span className="flex items-center gap-2">
        <Icon className="size-4" />
        {label}
      </span>
      <span className={cn("relative h-5 w-9 shrink-0 rounded-full transition-colors", on ? "bg-primary" : "bg-muted")}>
        <span
          className={cn(
            "absolute top-0.5 size-4 rounded-full bg-white transition-transform",
            on ? "translate-x-4" : "translate-x-0.5",
          )}
        />
      </span>
    </button>
  );
}

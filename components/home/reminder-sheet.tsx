"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { toast } from "sonner";
import { X, Trash2, Truck, Mail, MessageSquare, Check, RotateCcw, Briefcase, Lightbulb } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  createReminder,
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
import { DateTimePicker } from "./date-time-picker";
import { cn } from "@/lib/utils";

// WhatsApp hidden for now — Twilio/Meta integration not wired up yet
// (v1.5, see CLAUDE.md); `whatsapp` stays a valid Channel value so any
// reminder already tagged with it still renders fine elsewhere.
const CHANNELS: { key: Channel; label: string; icon: typeof Mail }[] = [
  { key: "email", label: "Email", icon: Mail },
  { key: "slack", label: "Slack", icon: MessageSquare },
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
 * Editing an existing reminder (tapping a row), or — with `reminder={null}`
 * — creating a fresh one from scratch. Tapping the docked quick-add bar
 * (DESIGN.md §3/§5.1, revised 2026-07) opens this in create mode; it's the
 * one creation path now, not a secondary option.
 */
export function ReminderSheet({
  reminder,
  initialTitle,
  contexts,
  scrollToOrderPanel,
  onClose,
  onCreated,
}: {
  reminder: HomeReminder | null;
  /** Pre-fills the title when creating fresh (share-target hand-off). */
  initialTitle?: string;
  contexts: HomeContext[];
  /** Opened via the post-create "Add order details?" toast action. */
  scrollToOrderPanel?: boolean;
  onClose: () => void;
  /** Shopping lists only: instead of closing after the first save, the
   * caller swaps this sheet into edit mode for the reminder just created —
   * a checklist is useless if you have to reopen it to add the first item. */
  onCreated?: (reminder: HomeReminder) => void;
}) {
  const isNew = reminder === null;
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

  const [title, setTitle] = useState(reminder?.title ?? initialTitle ?? "");
  const [titleError, setTitleError] = useState(false);
  const [notes, setNotes] = useState(reminder?.notes ?? "");
  const [dueLocal, setDueLocal] = useState(toDatetimeLocal(reminder?.due_at ?? null));
  // Deliberately blank when creating fresh — "Choose Template" forces an
  // explicit pick instead of silently defaulting to whichever context
  // happens to sort first.
  const [contextId, setContextId] = useState(reminder?.context?.id ?? "");
  const [contextError, setContextError] = useState(false);
  const [channels, setChannels] = useState<Channel[]>(reminder?.channels ?? []);
  const [isOrder, setIsOrder] = useState(reminder?.is_order ?? false);

  const [orderRef, setOrderRef] = useState(reminder?.order?.orderRef ?? "");
  const [recipientName, setRecipientName] = useState(reminder?.order?.recipientName ?? "");
  const [shipBy, setShipBy] = useState(reminder?.order?.shipBy ?? "");
  const [carrier, setCarrier] = useState(reminder?.order?.carrier ?? "");
  const [trackingInput, setTrackingInput] = useState("");
  const [showTrackingField, setShowTrackingField] = useState(false);

  const hasWorkDetails = !!(reminder?.workDetails?.managerName || reminder?.workDetails?.departmentResource || reminder?.workDetails?.projectName);
  const [showWorkPanel, setShowWorkPanel] = useState(hasWorkDetails);
  const [managerName, setManagerName] = useState(reminder?.workDetails?.managerName ?? "");
  const [departmentResource, setDepartmentResource] = useState(reminder?.workDetails?.departmentResource ?? "");
  const [projectName, setProjectName] = useState(reminder?.workDetails?.projectName ?? "");

  const hasSidegigDetails = !!(reminder?.sidegigDetails?.initiativeName || reminder?.sidegigDetails?.clientName);
  const [showSidegigPanel, setShowSidegigPanel] = useState(hasSidegigDetails);
  const [initiativeName, setInitiativeName] = useState(reminder?.sidegigDetails?.initiativeName ?? "");
  const [clientName, setClientName] = useState(reminder?.sidegigDetails?.clientName ?? "");

  const [pending, startTransition] = useTransition();

  const done = reminder?.status === "done";
  const shipped = !!reminder?.order?.shippedAt;
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
    let hasError = false;
    if (!title.trim()) {
      setTitleError(true);
      hasError = true;
    }
    if (isNew && !contextId) {
      setContextError(true);
      hasError = true;
    }
    if (hasError) return;

    startTransition(async () => {
      // Resolve the id we'll attach work/sidegig details to below — either
      // the existing reminder's, or the freshly-created one's.
      let id: string;

      if (isNew) {
        const res = await createReminder({
          title,
          notes: notes.trim() || null,
          dueAt: fromDatetimeLocal(dueLocal),
          contextId,
          channels,
          isOrder,
          order: isOrder
            ? {
                orderRef: orderRef.trim() || null,
                recipientName: recipientName.trim() || null,
                shipBy: shipBy || null,
                carrier: carrier.trim() || null,
              }
            : null,
        });
        if (!res.ok) {
          toast.error("Couldn't save", { description: res.error });
          return;
        }
        id = res.id;

        // Shopping lists: don't close — a checklist with nowhere to add
        // items yet is a dead end. Hand off to the caller to reopen this
        // same sheet in edit mode for the reminder we just created, so the
        // checklist (which needs a real reminder id) is usable immediately.
        if (isShopping && onCreated) {
          onCreated({
            id,
            title,
            notes: notes.trim() || null,
            due_at: fromDatetimeLocal(dueLocal),
            snoozed_until: null,
            status: "open",
            channels,
            is_order: false,
            context: selectedContext,
            failedNotificationId: null,
            order: null,
            workDetails: null,
            sidegigDetails: null,
            shoppingItems: [],
          });
          return;
        }
      } else {
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
        id = reminder.id;
        if (isOrder) {
          const orderRes = await updateOrderDetails({
            reminderId: id,
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
      }

      if (isWork && showWorkPanel) {
        const workRes = await updateWorkDetails({
          reminderId: id,
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
          reminderId: id,
          initiativeName: initiativeName.trim() || null,
          clientName: clientName.trim() || null,
        });
        if (!sidegigRes.ok) {
          toast.error("Saved, but initiative details failed", { description: sidegigRes.error });
          return;
        }
      }
      toast.success(isNew ? "Added ✓" : "Saved");
      requestClose();
    });
  }

  function handleMarkShipped() {
    if (!reminder) return; // only reachable once saved — button is hidden pre-save
    const id = reminder.id;
    startTransition(async () => {
      const res = await markShipped(id, trackingInput.trim(), carrier.trim() || null);
      if (!res.ok) {
        toast.error("Couldn't mark shipped", { description: res.error });
        return;
      }
      toast.success("Shipped ✓", {
        description: "Remind me to follow up?",
        action: {
          label: "+3d follow-up",
          onClick: () => {
            createFollowUp(id).then((r) => {
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
    if (!reminder) return;
    const id = reminder.id;
    startTransition(async () => {
      const res = await deleteReminder(id);
      if (!res.ok) toast.error("Couldn't delete", { description: res.error });
      else requestClose();
    });
  }

  function handleToggleDone() {
    if (!reminder) return;
    const id = reminder.id;
    startTransition(async () => {
      const res = done ? await reopenReminder(id) : await completeReminder(id);
      if (!res.ok) toast.error("Couldn't update", { description: res.error });
      else requestClose();
    });
  }

  return (
    // Always bottom-anchored (items-end, no sm:items-center) — matches
    // design/prototype.html's .sheet exactly, which never switches to a
    // centered dialog at any width. The app frame itself is capped at
    // ~420px even on desktop, so there's no point where a centered-dialog
    // treatment made sense; it was just an unintended deviation.
    <div className="absolute inset-0 z-50 flex items-end justify-center">
      {/* absolute, not fixed — stays within the app "frame" (app/layout.tsx
          is `relative`) instead of covering the raw viewport, so on wider
          screens the scrim/sheet only cover the framed app card. */}
      <div
        className={cn(
          "absolute inset-0 bg-black/40 transition-opacity duration-[250ms]",
          open ? "opacity-100" : "opacity-0",
        )}
        onClick={requestClose}
        aria-hidden
      />
      <div
        className={cn(
          // [scrollbar-gutter:stable] reserves the scrollbar's width up
          // front so it can't intermittently eat into content (the toggle
          // switches sitting flush against the right edge, per feedback) —
          // the content box stays the same whether or not a scrollbar is
          // actually showing.
          //
          // overflow-x-hidden is deliberate, not decorative: with only
          // overflow-y set, the CSS spec forces the x-axis to "auto" too,
          // and DateTimePicker's absolutely-positioned popover can extend
          // past the sheet's left edge depending on how wide the selected
          // context name renders — which then made the whole sheet
          // horizontally scrollable on some phone widths (iPhone Pro
          // reported). Pinning x to hidden keeps the sheet's own width
          // fixed; an overflowing popover just clips instead.
          "relative flex max-h-[85vh] w-full max-w-md flex-col overflow-y-auto overflow-x-hidden rounded-t-[20px] bg-surface p-4 shadow-sheet transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] [scrollbar-gutter:stable]",
          open ? "translate-y-0" : "translate-y-full",
        )}
      >
        <div className="mx-auto mb-3 h-1 w-10 shrink-0 rounded-full bg-hairline" />

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
            autoFocus={isNew}
          />
          <button type="button" onClick={requestClose} aria-label="Close" className="shrink-0 rounded-md p-1 text-text-2 hover:bg-muted">
            <X className="size-5" />
          </button>
        </div>
        {titleError && <p className="mt-1 text-[12px] font-medium text-danger">Title required</p>}

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select
            value={contextId}
            onChange={(e) => {
              setContextId(e.target.value);
              if (contextError) setContextError(false);
            }}
            className={cn(
              "h-8 rounded-lg border border-input bg-transparent px-2 text-sm outline-none",
              contextError && "border-danger text-danger",
            )}
          >
            <option value="" disabled>
              Choose template
            </option>
            {contexts.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <DateTimePicker value={dueLocal} onChange={setDueLocal} />
        </div>
        {contextError && <p className="mt-1 text-[12px] font-medium text-danger">Choose a template</p>}

        {isShopping ? (
          reminder ? (
            <ShoppingChecklist reminderId={reminder.id} initialItems={reminder.shoppingItems} />
          ) : (
            // Matches the notes+channels section's height on other templates
            // (min-h) rather than leaving a short sheet — a short sheet here
            // clipped the date popover's OK button below the fold, forcing a
            // scroll to confirm. Fill the space with real instructions
            // instead of blank whitespace.
            <div className="mt-3 flex min-h-[220px] flex-col items-center justify-center gap-1.5 rounded-lg border border-hairline bg-background px-4 py-6 text-center">
              <p className="text-[13px] font-medium text-foreground">This will be a running checklist</p>
              <p className="text-[13px] text-text-2">
                Save the list first, then add items one at a time — check them off as you shop.
              </p>
            </div>
          )
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

              {isNew ? null : shipped ? (
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
                <Button
                  size="sm"
                  className="mt-1 w-full bg-sidegig text-white hover:bg-sidegig/90"
                  onClick={() => setShowTrackingField(true)}
                >
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

        <div className={cn("mt-5 flex items-center border-t border-hairline pt-3", isNew ? "justify-end" : "justify-between")}>
          {!isNew && (
            <Button variant="ghost" size="sm" disabled={pending} onClick={handleDelete} className="text-danger">
              <Trash2 className="size-3.5" />
              Delete
            </Button>
          )}
          <div className="flex items-center gap-2">
            {!isNew && (
              <Button variant="outline" size="sm" disabled={pending} onClick={handleToggleDone}>
                {done ? <RotateCcw className="size-3.5" /> : <Check className="size-3.5" />}
                {done ? "Reopen" : "Done"}
              </Button>
            )}
            <Button size="sm" disabled={pending} onClick={save}>
              {isNew ? "Add" : "Save"}
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
    // gap + min-w-0/truncate on the label (rather than justify-between
    // alone) guarantees the switch is always fully visible — a long label
    // can never push it past the edge, it just truncates instead.
    <button type="button" onClick={onToggle} className="flex w-full items-center gap-3 text-[14px] font-medium">
      <span className="flex min-w-0 flex-1 items-center gap-2">
        <Icon className="size-4 shrink-0" />
        <span className="truncate">{label}</span>
      </span>
      {/* Matches design/prototype.html's .switch exactly: 46x28 track,
          hairline (not muted-gray-on-white, which was nearly invisible
          against the surface) when off, social green when on, and a
          shadowed white knob so it reads against either state.
          overflow-hidden is the safety net — without it, the knob's own
          box-shadow blurs a few px past the track's rounded edge and reads
          as "the white circle spilling outside the green pill" exactly
          like the reported bug. translate-x-5 (20px) + left-0.5 base (2px)
          = knob's right edge lands exactly 2px inside the track on the
          right, matching the 2px it starts with on the left when off —
          the previous 18px value left an uneven 4px gap that made the
          asymmetry (and the shadow bleed) more obvious. */}
      <span className={cn("relative h-7 w-[46px] shrink-0 overflow-hidden rounded-full transition-colors", on ? "bg-social" : "bg-hairline")}>
        <span
          className={cn(
            "absolute left-0.5 top-0.5 size-6 rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.25)] transition-transform",
            on ? "translate-x-5" : "translate-x-0",
          )}
        />
      </span>
    </button>
  );
}

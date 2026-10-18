"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { X } from "lucide-react";
import { toast } from "sonner";
import { saveMaintenance, recordService } from "@/app/home/actions";
import { deleteReminder } from "@/app/actions";
import { DateTimePicker } from "@/components/home/date-time-picker";
import {
  homeTemplate,
  repeatValue,
  repeatLabel,
  validateHomeDetails,
  type HomeTaskField,
  localDateValue,
  type HomeCategory,
  type MaintenanceItem,
} from "@/lib/household";

const field =
  "min-h-11 w-full rounded-xl border border-hairline bg-surface px-3 py-2 text-[15px]";
export function MaintenanceSheet({
  item,
  category,
  onClose,
}: {
  item?: MaintenanceItem;
  category: HomeCategory;
  onClose: () => void;
}) {
  const template = homeTemplate(category);
  const [details, setDetails] = useState<Record<string, string>>(
    item?.details ?? {},
  );
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState(item?.title ?? template.title);
  const [asset, setAsset] = useState(item?.asset ?? "");
  const [notes, setNotes] = useState(item?.notes ?? "");
  const [due, setDue] = useState(localDateValue(item?.due_at ?? null));
  const [repeat, setRepeat] = useState(repeatValue(item));
  const [apns, setApns] = useState(item?.channels.includes("apns") ?? false);
  const [service, setService] = useState(false);
  const [servicedAt, setServicedAt] = useState(
    localDateValue(new Date().toISOString()),
  );
  const [serviceNotes, setServiceNotes] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [pending, start] = useTransition();
  const dialog = useRef<HTMLDivElement>(null);
  const dragStart = useRef<number | null>(null);
  const close = () => {
    if (pending) return;
    setOpen(false);
    setTimeout(onClose, 300);
  };
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const raf = requestAnimationFrame(() => {
      setOpen(true);
      dialog.current?.focus({ preventScroll: true });
    });
    return () => {
      cancelAnimationFrame(raf);
      document.body.style.overflow = oldOverflow;
      prev?.focus({ preventScroll: true });
    };
  }, []);
  function submit() {
    const next: Record<string, string> = {};
    if (!service && !title.trim())
      next.title = `${template.taskLabel} required`;
    const taskDetails = Object.fromEntries(
      template.fields
        .map((f) => [f.key, (details[f.key] ?? "").trim()])
        .filter(([, value]) => value),
    );
    if (!service)
      Object.assign(next, validateHomeDetails(category, taskDetails));
    if (!service && (!due || !Number.isFinite(new Date(due).getTime())))
      next.due = template.dueError;
    if (
      service &&
      (!servicedAt ||
        !Number.isFinite(new Date(servicedAt).getTime()) ||
        new Date(servicedAt) > new Date())
    )
      next.service = `Choose ${template.recordDate.toLowerCase()} that is now or earlier`;
    setErrors(next);
    if (Object.keys(next).length) return;
    start(async () => {
      try {
        const result =
          service && item
            ? await recordService({
                p_id: item.reminder_id,
                p_expected_updated_at: item.updated_at,
                p_serviced_at: new Date(servicedAt).toISOString(),
                p_notes: serviceNotes,
              })
            : await saveMaintenance({
                p_id: item?.reminder_id ?? null,
                p_title: title,
                p_notes: notes,
                p_due_at: new Date(due).toISOString(),
                p_category: category,
                p_asset: asset,
                p_repeat_months: repeat.startsWith("m")
                  ? Number(repeat.slice(1))
                  : null,
                p_repeat_days: repeat.startsWith("d")
                  ? Number(repeat.slice(1))
                  : null,
                p_details: taskDetails,
                p_channels: apns ? ["email", "apns"] : ["email"],
              });
        if (!result.ok) {
          setErrors({ save: result.error });
          return;
        }
        toast.success(service ? template.recordSuccess : "Home reminder saved");
        onClose();
      } catch {
        setErrors({
          save: "Could not save. Check your connection and try again.",
        });
      }
    });
  }
  return (
    <div className="absolute inset-0 z-50 flex items-end justify-center">
      <button
        aria-label="Close Home task"
        className={`absolute inset-0 bg-black/40 transition-opacity duration-300 ${open ? "opacity-100" : "opacity-0"}`}
        onClick={close}
      />
      <div
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby="maintenance-heading"
        tabIndex={-1}
        onKeyDown={(e) => {
          if (e.key === "Escape") close();
          if (e.key === "Tab") {
            const nodes = dialog.current?.querySelectorAll<HTMLElement>(
              "button:not([disabled]),input,select,textarea",
            );
            if (!nodes?.length) return;
            const first = nodes[0],
              last = nodes[nodes.length - 1];
            if (
              e.shiftKey &&
              (document.activeElement === first ||
                document.activeElement === dialog.current)
            ) {
              e.preventDefault();
              last.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault();
              first.focus();
            }
          }
        }}
        className={`relative max-h-[88%] w-full max-w-md overflow-y-auto rounded-t-[20px] border border-hairline bg-surface p-5 pb-8 shadow-sheet outline-none transition-transform duration-300 motion-reduce:transition-none ${open ? "translate-y-0" : "translate-y-full"}`}
        style={{ transitionTimingFunction: "cubic-bezier(0.32,0.72,0,1)" }}
      >
        <div
          className="mx-auto mb-3 flex h-6 w-20 touch-none items-center justify-center"
          onPointerDown={(e) => {
            dragStart.current = e.clientY;
            e.currentTarget.setPointerCapture(e.pointerId);
          }}
          onPointerUp={(e) => {
            if (
              dragStart.current !== null &&
              e.clientY - dragStart.current > 70
            )
              close();
            dragStart.current = null;
          }}
        >
          <div className="h-1 w-9 rounded-full bg-hairline" />
        </div>
        <div className="mb-4 flex items-center justify-between">
          <h2 id="maintenance-heading" className="text-xl font-semibold">
            {service ? template.recordTitle : template.label}
          </h2>
          <button
            aria-label="Close"
            className="grid size-11 place-items-center"
            onClick={close}
          >
            <X className="size-5" />
          </button>
        </div>
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
        >
          {service ? (
            <>
              <p className="font-semibold">
                {item?.title} {item?.asset && `· ${item.asset}`}
              </p>
              <div>
                <p className="mb-2 text-sm text-text-2">
                  {template.recordDate}
                </p>
                <DateTimePicker value={servicedAt} onChange={setServicedAt} />
                {errors.service && (
                  <p role="alert" className="text-sm text-danger">
                    {errors.service}
                  </p>
                )}
              </div>
              <label className="block text-sm">
                {template.recordNotes}
                <textarea
                  className={`${field} mt-1`}
                  rows={3}
                  value={serviceNotes}
                  onChange={(e) => setServiceNotes(e.target.value)}
                  placeholder={template.recordPlaceholder}
                />
              </label>
              <p className="text-sm text-text-2">
                {repeatValue(item) !== "off"
                  ? template.section === "bills" || template.section === "study"
                    ? `The next reminder follows its ${repeatLabel(repeatValue(item)).toLowerCase()} schedule from the current due date.`
                    : `The next reminder repeats ${repeatLabel(repeatValue(item)).toLowerCase()} after this ${template.recordNoun}.`
                  : `This completes the reminder and keeps a ${template.recordNoun} record.`}
              </p>
            </>
          ) : (
            <>
              <p className="text-[13px] font-semibold uppercase tracking-wide text-social">
                {template.label}
              </p>
              <label className="block text-sm">
                {template.taskLabel}
                <input
                  className={`${field} mt-1 ${errors.title ? "border-danger" : ""}`}
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  aria-invalid={!!errors.title}
                  placeholder={template.taskPlaceholder}
                />
                {errors.title && (
                  <span role="alert" className="text-danger">
                    {errors.title}
                  </span>
                )}
              </label>
              <label className="block text-sm">
                {template.assetLabel}
                <input
                  className={`${field} mt-1`}
                  value={asset}
                  onChange={(e) => setAsset(e.target.value)}
                  placeholder={template.assetPlaceholder}
                />
              </label>
              {(template.fields as HomeTaskField[]).map((f) => (
                <label key={f.key} className="block text-sm">
                  {f.label}
                  <input
                    className={`${field} mt-1 ${errors[f.key] ? "border-danger" : ""}`}
                    value={details[f.key] ?? ""}
                    placeholder={f.placeholder}
                    maxLength={f.input === "currency" ? 3 : 1000}
                    inputMode={f.input === "decimal" ? "decimal" : "text"}
                    aria-invalid={!!errors[f.key]}
                    onChange={(e) =>
                      setDetails((prev) => ({
                        ...prev,
                        [f.key]:
                          f.input === "currency"
                            ? e.target.value.toUpperCase()
                            : e.target.value,
                      }))
                    }
                  />
                  {errors[f.key] && (
                    <span role="alert" className="text-danger">
                      {errors[f.key]}
                    </span>
                  )}
                </label>
              ))}
              <div>
                <p className="mb-2 text-sm">{template.dueLabel}</p>
                <DateTimePicker value={due} onChange={setDue} />
                {errors.due && (
                  <p role="alert" className="text-sm text-danger">
                    {errors.due}
                  </p>
                )}
              </div>
              <label className="block text-sm">
                {template.repeatLabel}
                <select
                  className={`${field} mt-1`}
                  value={repeat}
                  onChange={(e) => setRepeat(e.target.value)}
                >
                  {[...new Set([...template.repeatOptions, repeat])].map(
                    (value) => (
                      <option key={value} value={value}>
                        {repeatLabel(value)}
                      </option>
                    ),
                  )}
                </select>
              </label>
              <label className="block text-sm">
                {template.notesLabel}
                <textarea
                  className={`${field} mt-1`}
                  rows={3}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder={template.notesPlaceholder}
                />
              </label>
              <p className="text-sm text-text-2">
                Email reminders on · Personal quiet hours apply.
              </p>
              <label className="flex min-h-11 items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={apns}
                  onChange={(e) => setApns(e.target.checked)}
                />
                Also send to my registered iPhone
              </label>
            </>
          )}
          {errors.save && (
            <p role="alert" className="text-sm text-danger">
              {errors.save}
            </p>
          )}
          <button
            disabled={pending}
            className="min-h-11 w-full rounded-xl bg-social px-4 py-3 font-semibold text-black disabled:opacity-50"
          >
            {pending
              ? "Saving…"
              : service
                ? template.recordSave
                : "Save reminder"}
          </button>
          {item && !service && item.status !== "done" && (
            <button
              type="button"
              disabled={pending}
              className={`${field} font-semibold text-social`}
              onClick={() => {
                setErrors({});
                setService(true);
              }}
            >
              {template.recordAction}
            </button>
          )}
          {service && (
            <button
              type="button"
              className={field}
              disabled={pending}
              onClick={() => setService(false)}
            >
              Back to reminder
            </button>
          )}
          {item && !service && (
            <button
              type="button"
              disabled={pending}
              className="min-h-11 w-full text-danger"
              onClick={() => {
                if (
                  !window.confirm(
                    `Delete this reminder? Saved ${template.recordNoun} records will remain.`,
                  )
                )
                  return;
                start(async () => {
                  try {
                    const r = await deleteReminder(item.reminder_id);
                    if (r.ok) onClose();
                    else setErrors({ save: r.error });
                  } catch {
                    setErrors({ save: "Could not delete. Try again." });
                  }
                });
              }}
            >
              Delete reminder
            </button>
          )}
        </form>
      </div>
    </div>
  );
}

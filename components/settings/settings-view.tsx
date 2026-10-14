"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateTimezone, updateQuietHours } from "@/app/actions";

export interface SettingsContext {
  id: string;
  name: string;
  color: string;
  quiet_hours: { start?: string; end?: string };
}

export interface SettingsViewProps {
  timezone: string;
  contexts: SettingsContext[];
}

export function SettingsView({ timezone, contexts }: SettingsViewProps) {
  return (
    <div className="flex flex-col gap-6">
      <TimezoneSection initialTimezone={timezone} />
      <QuietHoursSection contexts={contexts} />
    </div>
  );
}

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-hairline bg-surface p-4">
      <h2 className="text-[15px] font-semibold">{title}</h2>
      {description && <p className="mt-0.5 text-[13px] text-text-2">{description}</p>}
      <div className="mt-3">{children}</div>
    </section>
  );
}

function TimezoneSection({ initialTimezone }: { initialTimezone: string }) {
  const [timezone, setTimezone] = useState(initialTimezone);
  const [pending, startTransition] = useTransition();

  function save() {
    const value = timezone.trim();
    if (!value) return;
    startTransition(async () => {
      const res = await updateTimezone(value);
      if (res.ok) toast.success("Timezone saved");
      else toast.error("Couldn't save timezone", { description: res.error });
    });
  }

  return (
    <Section title="Timezone" description="Used to resolve each context's quiet hours to your local time.">
      <div className="flex items-center gap-2">
        <Input
          value={timezone}
          onChange={(e) => setTimezone(e.target.value)}
          placeholder="America/Los_Angeles"
          className="max-w-[240px]"
        />
        <Button size="sm" disabled={pending || timezone.trim() === initialTimezone} onClick={save}>
          Save
        </Button>
      </div>
      <p className="mt-1.5 text-[12px] text-text-2">IANA timezone name, e.g. America/New_York, Europe/London.</p>
    </Section>
  );
}

function QuietHoursSection({ contexts }: { contexts: SettingsContext[] }) {
  return (
    <Section title="Quiet hours" description="Reminders due in this window are delivered at the end time instead.">
      <div className="flex flex-col gap-3">
        {contexts.map((c) => (
          <QuietHoursRow key={c.id} context={c} />
        ))}
      </div>
    </Section>
  );
}

function QuietHoursRow({ context }: { context: SettingsContext }) {
  const [start, setStart] = useState(context.quiet_hours.start ?? "");
  const [end, setEnd] = useState(context.quiet_hours.end ?? "");
  const [pending, startTransition] = useTransition();

  const dirty = start !== (context.quiet_hours.start ?? "") || end !== (context.quiet_hours.end ?? "");

  function save() {
    startTransition(async () => {
      const res = await updateQuietHours(context.id, start, end);
      if (res.ok) toast.success(`${context.name} quiet hours saved`);
      else toast.error("Couldn't save", { description: res.error });
    });
  }

  return (
    <div className="flex items-center gap-3">
      <span className="flex w-24 shrink-0 items-center gap-1.5 text-[14px]">
        <span className="size-2 rounded-full" style={{ backgroundColor: context.color }} />
        {context.name}
      </span>
      <Label className="sr-only" htmlFor={`start-${context.id}`}>
        Start
      </Label>
      <Input id={`start-${context.id}`} type="time" value={start} onChange={(e) => setStart(e.target.value)} className="w-28" />
      <span className="text-text-2">to</span>
      <Label className="sr-only" htmlFor={`end-${context.id}`}>
        End
      </Label>
      <Input id={`end-${context.id}`} type="time" value={end} onChange={(e) => setEnd(e.target.value)} className="w-28" />
      <Button size="sm" variant="ghost" disabled={!dirty || pending} onClick={save}>
        Save
      </Button>
    </div>
  );
}

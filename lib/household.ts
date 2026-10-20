import type { Channel } from "@/lib/supabase/types";
import config from "@/design/home-templates.json";
export type HomeCategory = keyof typeof config.templates;
export type HomeSection = keyof typeof config.sections;
export type HomeTaskField = {
  key: string;
  label: string;
  placeholder: string;
  input?: string;
};
export const HOME_SECTIONS = Object.entries(config.sections).map(
  ([key, section]) => ({ key: key as HomeSection, ...section }),
);
export function homeCategory(category: string): HomeCategory {
  return category === "filter"
    ? "hvac"
    : category in config.templates
      ? (category as HomeCategory)
      : "other";
}
export const HOME_CATEGORIES = Object.entries(config.templates).map(
  ([key, template]) => ({ key: key as HomeCategory, ...template }),
);
export function homeTemplate(category: string) {
  return config.templates[homeCategory(category)];
}
export function homeSection(category: string): HomeSection {
  return homeTemplate(category).section as HomeSection;
}
export const HOME_HISTORY: Record<string, { history: string; empty: string }> =
  Object.fromEntries(
    Object.entries(config.sections)
      .filter(([, v]) => "history" in v)
      .map(([key, v]) => [key, v]),
  ) as Record<string, { history: string; empty: string }>;
export interface MaintenanceItem {
  reminder_id: string;
  category: HomeCategory | "filter";
  asset: string;
  repeat_months: number | null;
  repeat_days?: number | null;
  details?: Record<string, string>;
  title: string;
  notes: string | null;
  due_at: string | null;
  snoozed_until: string | null;
  status: string;
  channels: Channel[];
  updated_at: string;
}
export interface ServiceRecord {
  id: string;
  reminder_id: string | null;
  title: string;
  category: HomeCategory | "filter";
  asset: string;
  serviced_at: string;
  notes: string;
  details?: Record<string, string>;
}
export function repeatValue(item?: MaintenanceItem): string {
  return item?.repeat_days
    ? `d${item.repeat_days}`
    : item?.repeat_months
      ? `m${item.repeat_months}`
      : "off";
}
export function repeatLabel(value: string): string {
  if (value === "off") return "Does not repeat";
  const n = Number(value.slice(1));
  if (value === "d1") return "Every day";
  if (value === "d7") return "Every week";
  if (value === "d14") return "Every 2 weeks";
  return `Every ${n} ${value[0] === "d" ? "day" : "month"}${n === 1 ? "" : "s"}`;
}
export function validateHomeDetails(
  category: string,
  details: Record<string, string>,
): Record<string, string> {
  const errors: Record<string, string> = {};
  if (category === "bill") {
    if (details.amount && !/^\d{1,9}(\.\d{1,2})?$/.test(details.amount))
      errors.amount = "Enter an amount such as 85.50";
    if (details.currency && !/^[A-Z]{3}$/.test(details.currency))
      errors.currency = "Use a three-letter currency, such as USD";
    if (details.amount && !details.currency)
      errors.currency = "Choose the currency for this amount";
  }
  return errors;
}
export function taskSummary(
  item: Pick<MaintenanceItem, "asset" | "details" | "category">,
): string {
  return [
    item.asset,
    ...(homeCategory(item.category) === "car"
      ? [item.details?.make, item.details?.model]
      : []),
  ]
    .filter(Boolean)
    .join(" · ");
}
export function localDateValue(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

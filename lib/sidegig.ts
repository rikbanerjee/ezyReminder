import type { HomeReminder } from "../components/home/types.ts";
import type { FocusAssignment } from "./supabase/types.ts";

export type GigSection = "overview" | "work" | "orders" | "followups" | "payments";
export const GIG_SECTIONS: [GigSection, string][] = [["overview","Overview"],["work","Work"],["orders","Ship Queue"],["followups","Follow-ups"],["payments","Payments"]];
export type GigKind = "work" | "order" | "followup" | "payment";
export type GigItem = {
  id: string; reminder_id: string | null; kind: GigKind; title: string; notes: string | null;
  due_at: string | null; status: string; person: string | null; context_slug: string;
  initiative?: string | null; next_step?: string | null; next_step_source?: "current" | "session";
  last_worked_at?: string | null; waiting?: boolean; minutes?: number; channels?: string[];
  reference: string | null; ship_by?: string | null; carrier?: string | null; tracking?: string | null; shipped_at?: string | null;
  related_id?: string | null; related_payment_id?: string | null; amount?: string | null; currency?: string | null;
  last_contact_at?: string | null; received_on?: string | null; updated_at: string;
  activity?: { action: string; notes: string | null; happened_at: string }[];
};
export type GigDashboard = { timezone: string; local_date: string; items: GigItem[]; api: number };
export type GigPayload = Record<string, string | number | boolean | string[] | null>;
export const gigOpen = (r: GigItem) => ["open","snoozed"].includes(r.status);
export const gigWork = (r: GigItem) => r.kind === "work" || r.kind === "order";
export const gigEligible = (r: GigItem) => gigWork(r) && gigOpen(r) && !r.waiting && ["work","sidegig"].includes(r.context_slug);
export const gigDate = (iso: string, zone: string) => new Intl.DateTimeFormat("en-CA",{timeZone:zone,year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date(iso));
export const gigDue = (r: GigItem, zone: string) => r.kind === "order" ? r.ship_by ?? null : r.due_at ? gigDate(r.due_at,zone) : null;
export const gigSort = (a: GigItem,b: GigItem,zone: string) => (gigDue(a,zone) ?? "9999").localeCompare(gigDue(b,zone) ?? "9999") || a.id.localeCompare(b.id);
export function gigAttention(d: GigDashboard): GigItem[] {
  const tomorrow=new Date(`${d.local_date}T12:00:00Z`);tomorrow.setUTCDate(tomorrow.getUTCDate()+1);
  const next=tomorrow.toISOString().slice(0,10);
  const collectionFollowups=new Set(d.items.filter(r=>r.kind==="followup"&&gigOpen(r)&&r.related_payment_id).map(r=>r.related_payment_id));
  return d.items.filter(r=>{
    if(!gigOpen(r)||r.waiting||(r.kind==="order"&&r.shipped_at))return false;
    if(r.kind==="payment"&&collectionFollowups.has(r.id))return false;
    const date=gigDue(r,d.timezone);return !!date&&date<=(r.kind==="order"?next:d.local_date);
  }).sort((a,b)=>gigSort(a,b,d.timezone));
}
export function gigResume(d: GigDashboard,assignments: FocusAssignment[],highlightId?: string|null): GigItem|undefined {
  const rows=d.items.filter(gigEligible);
  const recent=rows.filter(r=>r.last_worked_at).sort((a,b)=>b.last_worked_at!.localeCompare(a.last_worked_at!))[0];
  return recent ?? rows.find(r=>r.id===highlightId) ?? rows.find(r=>assignments.some(a=>a.reminder_id===r.id&&a.state==="planned")) ?? [...rows].sort((a,b)=>gigSort(a,b,d.timezone))[0];
}
/** Exact decimal sums, grouped by currency. Never mix money or treat unknown amounts as zero. */
export function gigMoney(rows: GigItem[]): { totals: string[]; unknown: number } {
  const sums: Record<string,bigint>={};let unknown=0;
  for(const r of rows){if(!r.amount||!r.currency){unknown++;continue;}const [whole,frac=""]=r.amount.split(".");const cents=BigInt(whole)*BigInt(100)+BigInt((frac+"00").slice(0,2));sums[r.currency]=(sums[r.currency]??BigInt(0))+cents;}
  return {totals:Object.entries(sums).sort().map(([currency,n])=>`${currency} ${(n/BigInt(100)).toLocaleString("en-US")}.${String(n%BigInt(100)).padStart(2,"0")}`),unknown};
}
export function gigHome(r: GigItem): HomeReminder {
  return {id:r.reminder_id??r.id,title:r.title,notes:r.notes,due_at:r.due_at,snoozed_until:null,status:r.status as HomeReminder["status"],channels:(r.channels??["email"]) as HomeReminder["channels"],is_order:r.kind==="order",tags:[],
    context:{id:"",slug:r.context_slug,name:r.context_slug==="sidegig"?"Side Gig":"Work",color:"#F5A623",default_channel:"email"},
    order:r.kind==="order"?{orderRef:r.reference,recipientName:r.person,shipBy:r.ship_by??null,carrier:r.carrier??null,trackingNumber:r.tracking??null,shippedAt:r.shipped_at??null}:null,
    workDetails:null,sidegigDetails:{initiativeName:r.initiative??null,clientName:r.person},shoppingItems:[],failedNotificationId:null};
}

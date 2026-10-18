"use client";

import type { ButtonHTMLAttributes, CSSProperties, ReactNode } from "react";
import { cn } from "@/lib/utils";

// Small primitives that mirror the prototype's .fb / .fchip2 / .f-choice / .f-inset classes (DESIGN.md §9).
// Context color shows up only as dots, selected chips/rows and the session accent - never a filled button.

export const ctxName = (slug: string) => (slug === "sidegig" ? "Side Gig" : "Work");
export const ctxColor = (slug: string) => (slug === "sidegig" ? "var(--sidegig)" : "var(--work)");
const fc = (slug?: string | null): CSSProperties | undefined => (slug ? ({ "--fc": ctxColor(slug) } as CSSProperties) : undefined);

export function Dot({ slug, className }: { slug: string; className?: string }) {
  return <span aria-hidden className={cn("inline-block size-2 shrink-0 rounded-full", className)} style={{ backgroundColor: ctxColor(slug) }} />;
}

export function CtxLine({ slug, children, className }: { slug: string; children?: ReactNode; className?: string }) {
  return <div className={cn("flex flex-wrap items-center gap-1.5 text-[13px] font-semibold text-text-2", className)}><Dot slug={slug} />{children ?? ctxName(slug)}</div>;
}

type Variant = "primary" | "outline" | "ghost" | "dur";
const variants: Record<Variant, string> = {
  primary: "bg-foreground text-background",
  outline: "border-hairline bg-surface text-foreground",
  ghost: "px-2.5 text-text-2",
  dur: "border-hairline bg-surface px-3.5 text-[13px] text-text-2 shadow-card",
};
export function FBtn({ variant = "outline", block, grow, danger, className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; block?: boolean; grow?: boolean; danger?: boolean }) {
  return <button type="button" {...props} className={cn(
    "inline-flex min-h-11 min-w-11 items-center justify-center gap-1.5 rounded-xl border-[1.5px] border-transparent px-4 text-center text-[15px] font-semibold leading-tight focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-work disabled:cursor-default disabled:opacity-45",
    variants[variant], block && "w-full", grow && "flex-1 basis-[150px]", danger && "text-danger", className)} />;
}

export function Chip({ on, slug, className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { on?: boolean; slug?: string | null }) {
  return <button type="button" aria-pressed={on} {...props} style={fc(slug)} className={cn(
    "inline-flex min-h-11 min-w-11 items-center justify-center gap-1.5 rounded-full border-[1.5px] border-hairline bg-surface px-3.5 text-[13px] font-semibold text-text-2 shadow-card focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-work",
    on && "border-[var(--fc,var(--foreground))] bg-[color-mix(in_srgb,var(--fc,var(--foreground))_10%,var(--surface))] text-foreground", className)} />;
}

/** One radio-style row (used for "When", outcomes, Work/Side Gig). */
export function Choice({ on, slug, children, className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { on: boolean; slug: string | null; children: ReactNode }) {
  return <button type="button" role="radio" aria-checked={on} {...props} style={fc(slug)} className={cn(
    "mt-2 flex min-h-[52px] w-full items-center gap-3 rounded-xl border-[1.5px] border-hairline bg-surface px-3.5 py-2.5 text-left text-[15px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-work",
    on && "border-[var(--fc,var(--foreground))] bg-[color-mix(in_srgb,var(--fc,var(--foreground))_8%,var(--surface))]", className)}>
    <span aria-hidden className={cn("size-5 shrink-0 rounded-full border-2 border-text-2", on && "border-[var(--fc,var(--foreground))] bg-[radial-gradient(var(--fc,var(--foreground))_45%,transparent_50%)]")} />
    {children}
  </button>;
}
export const ChoiceText = ({ title, sub }: { title: string; sub?: string }) => (
  <span className="min-w-0"><b className="block font-semibold">{title}</b>{sub && <span className="mt-px block text-[13px] font-normal text-text-2">{sub}</span>}</span>
);

export const fInput = "min-h-11 w-full rounded-xl border border-hairline bg-surface px-3 py-2.5 text-[15px] text-foreground outline-none focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-work aria-[invalid=true]:border-danger";
export const fTextarea = "min-h-[72px] w-full resize-y rounded-xl border border-transparent bg-background p-3 text-[15px] text-foreground outline-none focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-work";

export const Sub = ({ children, id, htmlFor, optional }: { children: ReactNode; id?: string; htmlFor?: string; optional?: boolean }) => {
  const Tag = htmlFor ? "label" : "div";
  return <Tag id={id} htmlFor={htmlFor} className="mb-2 mt-4 block text-[13px] font-semibold text-text-2">{children}{optional && <span className="font-normal"> (optional)</span>}</Tag>;
};
export const Help = ({ children, className }: { children: ReactNode; className?: string }) => <p className={cn("mt-1.5 text-[12px] text-text-2", className)}>{children}</p>;
export const Err = ({ children }: { children: ReactNode }) => <p role="alert" className="mt-1.5 text-[13px] text-danger">{children}</p>;
export const Meta = ({ children, className }: { children: ReactNode; className?: string }) => <div className={cn("mt-[3px] break-words text-[13px] text-text-2", className)}>{children}</div>;

export function Inset({ label, children }: { label: string; children: ReactNode }) {
  return <div className="mt-2.5 rounded-[10px] bg-background px-3 py-2.5"><div className="text-[12px] font-semibold text-text-2">{label}</div><div className="mt-0.5 whitespace-pre-wrap break-words text-[14px]">{children}</div></div>;
}
/** The session's "Your focus" / "Next step" block: 3px context accent on the left. */
export function FocusBlock({ slug, label, children }: { slug: string; label: string; children: ReactNode }) {
  return <div className="mt-3.5 rounded-[4px_12px_12px_4px] border-l-[3px] bg-background px-3.5 py-3" style={{ borderLeftColor: ctxColor(slug) }}>
    <div className="text-[12px] font-semibold text-text-2">{label}</div><div className="mt-[3px] whitespace-pre-wrap break-words text-[17px] font-semibold">{children}</div>
  </div>;
}
export function Warn({ title, children, actions }: { title: string; children?: ReactNode; actions?: ReactNode }) {
  return <div role="alert" className="mt-3.5 rounded-[4px_12px_12px_4px] border border-l-[3px] border-hairline border-l-danger bg-background px-3.5 py-3">
    <b className="text-[14px] text-danger">{title}</b>{children && <p className="mt-1 text-[13px]">{children}</p>}
    {actions && <div className="mt-2 flex flex-wrap gap-2">{actions}</div>}
  </div>;
}

export const ListCard = ({ children, className }: { children: ReactNode; className?: string }) => (
  <div className={cn("divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface leading-[1.2]", className)}>{children}</div>
);
export function ListRow({ slug, title, sub, hint, right, compact, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { slug: string; title: ReactNode; sub?: ReactNode; hint?: ReactNode; right?: ReactNode; compact?: boolean }) {
  return <button type="button" {...props} className="flex min-h-[52px] w-full items-center gap-3 px-3.5 py-3 text-left focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-work disabled:opacity-50">
    <Dot slug={slug} />
    <span className="min-w-0 flex-1"><span className={cn("block break-words font-semibold", compact ? "text-[15px]" : "text-[16px]")}>{title}</span>
      {sub && <span className="mt-0.5 block break-words text-[13px] text-text-2">{sub}</span>}
      {hint && <span className="mt-0.5 block text-[12px] text-text-2">{hint}</span>}</span>
    <span className="shrink-0 whitespace-nowrap text-[13px] text-text-2">{right ?? "›"}</span>
  </button>;
}

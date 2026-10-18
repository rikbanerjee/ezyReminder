"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

/** The prototype's bottom sheet, with a keyboard trap and focus restoration. */
export function FocusSheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const sheet = useRef<HTMLDivElement>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const close = useRef(onClose);
  close.current = onClose;

  function requestClose() {
    if (closeTimer.current) return;
    setOpen(false);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    closeTimer.current = setTimeout(() => close.current(), reduced ? 0 : 300);
  }
  const requestCloseRef = useRef(requestClose);
  requestCloseRef.current = requestClose;

  useEffect(() => {
    const prior = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const frame = requestAnimationFrame(() => {
      setOpen(true);
      sheet.current?.focus();
    });
    const focusables = () => Array.from(sheet.current?.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href], [tabindex="0"]',
    ) ?? []).filter((element) => element.getClientRects().length > 0);
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); requestCloseRef.current(); }
      if (event.key !== "Tab") return;
      const targets = focusables();
      const first = targets[0];
      const last = targets[targets.length - 1];
      if (!first) { event.preventDefault(); sheet.current?.focus(); return; }
      if (event.shiftKey && (document.activeElement === first || document.activeElement === sheet.current)) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || document.activeElement === sheet.current)) {
        event.preventDefault(); first.focus();
      }
    };
    const containFocus = (event: FocusEvent) => {
      if (event.target instanceof Node && !sheet.current?.contains(event.target)) sheet.current?.focus();
    };
    document.addEventListener("keydown", keyboard, true);
    document.addEventListener("focusin", containFocus);
    return () => {
      cancelAnimationFrame(frame);
      if (closeTimer.current) clearTimeout(closeTimer.current);
      document.removeEventListener("keydown", keyboard, true);
      document.removeEventListener("focusin", containFocus);
      if (prior?.isConnected) prior.focus();
    };
  }, []);

  return (
    <div className="absolute inset-0 z-[60] flex items-end justify-center">
      <div aria-hidden onClick={requestClose} className={cn("absolute inset-0 bg-black/40 transition-opacity duration-[250ms] motion-reduce:transition-none", open ? "opacity-100" : "opacity-0")} />
      <div ref={sheet} role="dialog" aria-modal="true" aria-labelledby="focus-sheet-title" tabIndex={-1}
        className={cn("relative max-h-[86%] w-full max-w-md overflow-y-auto overscroll-contain rounded-t-[20px] bg-surface px-5 pb-[calc(20px+env(safe-area-inset-bottom))] pt-2 shadow-sheet outline-none transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] motion-reduce:transition-none", open ? "translate-y-0" : "translate-y-full")}>
        <div className="mx-auto mb-3 mt-1.5 h-[5px] w-9 rounded-full bg-hairline" />
        <div className="mb-4 flex items-center justify-between gap-2">
          <h2 id="focus-sheet-title" className="text-[20px] font-semibold">{title}</h2>
          <button type="button" aria-label="Close focus" onClick={requestClose} className="grid size-11 shrink-0 place-items-center rounded-lg text-text-2 focus-visible:outline-2 focus-visible:outline-work"><X className="size-5" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

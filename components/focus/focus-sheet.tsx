"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { ChevronLeft, X } from "lucide-react";
import { cn } from "@/lib/utils";

/** The prototype's bottom sheet, with a keyboard trap and focus restoration. */
export function FocusSheet({ title, scrollKey, onClose, onBack, children }: { title: string; scrollKey?: string; onClose: () => void; onBack?: () => void; children: ReactNode }) {
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

  // Drag the handle zone down to dismiss (prototype: > 100px closes, otherwise springs back).
  const drag = useRef<{ y0: number; dy: number } | null>(null);
  function dragStart(event: React.PointerEvent) {
    drag.current = { y0: event.clientY, dy: 0 };
    event.currentTarget.setPointerCapture(event.pointerId);
    if (sheet.current) sheet.current.style.transition = "none";
  }
  function dragMove(event: React.PointerEvent) {
    if (!drag.current || !sheet.current) return;
    drag.current.dy = Math.max(0, event.clientY - drag.current.y0);
    sheet.current.style.transform = `translateY(${drag.current.dy}px)`;
  }
  function dragEnd() {
    if (!drag.current || !sheet.current) return;
    const { dy } = drag.current;
    drag.current = null;
    sheet.current.style.transition = "";
    sheet.current.style.transform = "";
    if (dy > 100) requestCloseRef.current();
  }

  // Switching modes inside the open sheet starts at the top, like a fresh screen.
  useEffect(() => { sheet.current?.scrollTo({ top: 0 }); }, [scrollKey]);

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
      <div ref={sheet} id="focus-sheet" role="dialog" aria-modal="true" aria-labelledby="focus-sheet-title" tabIndex={-1}
        className={cn("relative max-h-[86%] w-full max-w-md overflow-y-auto leading-[1.2] overflow-x-hidden overscroll-contain rounded-t-[20px] bg-surface px-5 pb-[calc(20px+env(safe-area-inset-bottom))] pt-0 shadow-sheet outline-none transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] motion-reduce:transition-none", open ? "translate-y-0" : "translate-y-full")}>
        <div className="cursor-grab touch-none pb-3.5 pt-4" onPointerDown={dragStart} onPointerMove={dragMove} onPointerUp={dragEnd} onPointerCancel={dragEnd}>
          <div className="mx-auto h-[5px] w-9 rounded-full bg-hairline" />
        </div>
        <div className="mb-1.5 flex items-center gap-0.5">
          {onBack && <button type="button" aria-label="Back" onClick={onBack} className="-ml-2.5 grid size-11 shrink-0 place-items-center rounded-xl text-text-2 focus-visible:outline-2 focus-visible:outline-work"><ChevronLeft className="size-6" /></button>}
          <h2 id="focus-sheet-title" className="min-w-0 flex-1 break-words text-[20px] font-semibold">{title}</h2>
          <button type="button" aria-label="Close" onClick={requestClose} className="-mr-2.5 grid size-11 shrink-0 place-items-center rounded-xl text-text-2 focus-visible:outline-2 focus-visible:outline-work"><X className="size-5" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

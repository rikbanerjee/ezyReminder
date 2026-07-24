"use client";

import { useEffect, useState } from "react";
import { X, Share } from "lucide-react";

const DISMISSED_KEY = "easyreminder:install-nudge-dismissed";

function isIosSafari(): boolean {
  const ua = window.navigator.userAgent;
  const isIos = /iPad|iPhone|iPod/.test(ua);
  const isSafari = /Safari/.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua);
  return isIos && isSafari;
}

function isStandalone(): boolean {
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    (window.navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

/**
 * iOS Safari has no install-prompt API (MOBILE.md Stage 1) — a small
 * dismissible banner is the only way to surface "Add to Home Screen".
 */
export function InstallNudge() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (localStorage.getItem(DISMISSED_KEY)) return;
    if (isIosSafari() && !isStandalone()) setShow(true);
  }, []);

  function dismiss() {
    localStorage.setItem(DISMISSED_KEY, "1");
    setShow(false);
  }

  if (!show) return null;

  return (
    <div className="fixed inset-x-0 bottom-0 z-40 flex items-center gap-3 border-t border-hairline bg-surface px-4 py-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] shadow-lg">
      <p className="flex-1 text-[13px] text-foreground">
        Install easyReminder: tap <Share className="mx-0.5 inline size-3.5 align-text-bottom" /> then{" "}
        <span className="font-medium">Add to Home Screen</span>.
      </p>
      <button type="button" onClick={dismiss} aria-label="Dismiss" className="shrink-0 rounded-md p-1 text-text-2 hover:bg-muted">
        <X className="size-4" />
      </button>
    </div>
  );
}

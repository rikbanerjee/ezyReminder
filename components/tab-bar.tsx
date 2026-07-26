"use client";

import Link from "next/link";
import { LayoutGrid, Truck, List } from "lucide-react";
import { cn } from "@/lib/utils";

type TabKey = "today" | "ship" | "all";

const TABS: { key: TabKey; href: string; label: string; icon: typeof LayoutGrid }[] = [
  { key: "today", href: "/", label: "Today", icon: LayoutGrid },
  { key: "ship", href: "/ship-queue", label: "Ship", icon: Truck },
  { key: "all", href: "/all", label: "All", icon: List },
];

/** Persistent 3-tab bottom bar (DESIGN.md §3). Settings stays in the header gear icon. */
export function TabBar({ activeTab, shipSoonCount }: { activeTab: TabKey; shipSoonCount: number }) {
  return (
    <nav className="flex items-center border-t border-hairline bg-surface px-2 pb-[calc(0.5rem+env(safe-area-inset-bottom))] pt-2">
      {TABS.map(({ key, href, label, icon: Icon }) => {
        const active = key === activeTab;
        return (
          <Link
            key={key}
            href={href}
            className={cn(
              "relative flex flex-1 flex-col items-center gap-0.5 py-1 text-[11px] font-semibold",
              active ? "text-work" : "text-text-2",
            )}
          >
            {/* Ship keeps its amber (sidegig) tint whether active or not —
                matches the prototype's 🚚 emoji, which renders in its own
                colors regardless of tab state, unlike the other glyph icons. */}
            <Icon className={cn("size-5", key === "ship" && "text-sidegig")} />
            {label}
            {key === "ship" && shipSoonCount > 0 && (
              <span className="absolute -top-0.5 right-[calc(50%-22px)] grid min-w-[16px] place-items-center rounded-full bg-danger px-1 text-[10px] font-bold leading-[16px] text-white">
                {shipSoonCount}
              </span>
            )}
          </Link>
        );
      })}
    </nav>
  );
}

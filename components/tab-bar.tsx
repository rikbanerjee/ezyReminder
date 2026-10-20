"use client";

import Link from "next/link";
import { LayoutGrid, BriefcaseBusiness, List, House } from "lucide-react";
import { cn } from "@/lib/utils";

type TabKey = "today" | "ship" | "sidegig" | "all" | "home";

const TABS: { key: TabKey; href: string; label: string; icon: typeof LayoutGrid }[] = [
  { key: "today", href: "/", label: "Today", icon: LayoutGrid },
  { key: "sidegig", href: "/side-gig", label: "Side Gig", icon: BriefcaseBusiness },
  { key: "home", href: "/home", label: "Home", icon: House },
  { key: "all", href: "/all", label: "All", icon: List },
];

/** Persistent 4-tab bottom bar (DESIGN.md §3). Settings stays in the header gear icon. */
export function TabBar({ activeTab }: { activeTab: TabKey; shipSoonCount: number }) {
  return (
    <nav className="flex items-center border-t border-hairline bg-surface px-2 pb-[calc(0.5rem+env(safe-area-inset-bottom))] pt-2">
      {TABS.map(({ key, href, label, icon: Icon }) => {
        const active = key === activeTab || (key === "sidegig" && activeTab === "ship");
        return (
          <Link
            key={key}
            href={href}
            className={cn(
              "relative flex min-h-11 flex-1 flex-col items-center gap-0.5 py-1 text-[11px] font-semibold",
              active ? key === "sidegig" ? "text-sidegig" : "text-work" : "text-text-2",
            )}
          >
            {/* Ship keeps its amber (sidegig) tint whether active or not —
                matches the prototype's 🚚 emoji, which renders in its own
                colors regardless of tab state, unlike the other glyph icons. */}
            <Icon className="size-5" />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}

import { TabBar } from "@/components/tab-bar";

/**
 * Docks the quick-add bar (when provided) directly above the tab bar
 * (DESIGN.md §3) — the app's center of gravity. This is a plain, non-scrolling
 * flex sibling rendered after the scrollable content area (see
 * components/home/home-view.tsx and each page.tsx under app/) — the parent flex
 * column + fixed-height frame (app/layout.tsx) is what pins it to the
 * bottom while the sibling above it scrolls independently. No
 * fixed/sticky/absolute positioning needed or wanted here.
 */
export function BottomDock({
  activeTab,
  shipSoonCount,
  children,
}: {
  activeTab: "today" | "ship" | "all";
  shipSoonCount: number;
  children?: React.ReactNode;
}) {
  return (
    <div className="z-30 mx-auto w-full max-w-md shrink-0">
      {children && (
        <div className="bg-gradient-to-t from-background via-background/95 to-transparent px-4 pb-2 pt-6">
          {children}
        </div>
      )}
      <TabBar activeTab={activeTab} shipSoonCount={shipSoonCount} />
    </div>
  );
}

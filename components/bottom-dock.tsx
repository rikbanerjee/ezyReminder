import { TabBar } from "@/components/tab-bar";

/**
 * Docks the quick-add bar (when provided) directly above the tab bar,
 * fixed to the viewport bottom (DESIGN.md §3) — the app's center of gravity.
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
    <div className="fixed inset-x-0 bottom-0 z-30 mx-auto max-w-md">
      {children && (
        <div className="bg-gradient-to-t from-background via-background/95 to-transparent px-4 pb-2 pt-6">
          {children}
        </div>
      )}
      <TabBar activeTab={activeTab} shipSoonCount={shipSoonCount} />
    </div>
  );
}

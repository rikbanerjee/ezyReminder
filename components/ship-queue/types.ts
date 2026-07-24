export interface ShipQueueContext {
  name: string;
  color: string;
}

export interface ShipQueueRow {
  reminderId: string;
  title: string;
  context: ShipQueueContext | null;
  orderRef: string | null;
  recipientName: string | null;
  shipBy: string | null; // "YYYY-MM-DD"
  carrier: string | null;
  trackingNumber: string | null;
  shippedAt: string | null;
}

/** Days until ship_by (negative = overdue-to-ship). Null if no ship_by set. */
export function daysUntilShipBy(row: ShipQueueRow): number | null {
  if (!row.shipBy) return null;
  const target = new Date(`${row.shipBy}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

export function formatShipBy(row: ShipQueueRow): string {
  const days = daysUntilShipBy(row);
  if (days === null) return "No ship-by date";
  if (days < 0) return `${Math.abs(days)}d overdue to ship`;
  if (days === 0) return "Ship by today";
  if (days === 1) return "Ship by tomorrow";
  const date = new Date(`${row.shipBy}T00:00:00`);
  return `Ship by ${date.toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
}

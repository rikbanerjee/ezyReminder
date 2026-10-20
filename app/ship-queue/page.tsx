import { redirect } from "next/navigation";

/** Preserve old links and PWA shortcuts; Side Gig labels orders from other contexts. */
export default function ShipQueuePage() { redirect("/side-gig?section=orders"); }

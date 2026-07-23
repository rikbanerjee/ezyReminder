/**
 * Shipping provider seam (CLAUDE.md, PLAN.md §4.2). v1 ships `ManualProvider`
 * (no API dependency — order fields are entered by hand). `ShippoProvider`
 * lands later behind this same interface; never hardcode a carrier API
 * outside an implementation of this interface.
 */

export interface ShippingRate {
  carrier: string;
  service: string;
  amountCents: number;
  currency: string;
  estimatedDays: number | null;
}

export interface ShippingLabel {
  transactionId: string;
  trackingNumber: string;
  trackingUrl: string;
  labelUrl: string;
  carrier: string;
}

export interface TrackingStatus {
  status: "unknown" | "pre_transit" | "in_transit" | "out_for_delivery" | "delivered" | "failure";
  lastUpdatedAt: string | null;
  eta: string | null;
}

export interface ShippingProvider {
  name: string;
  getRates(params: { toAddress: unknown; parcel: unknown }): Promise<ShippingRate[]>;
  createLabel(params: { rate: ShippingRate; toAddress: unknown; parcel: unknown }): Promise<ShippingLabel>;
  trackShipment(trackingNumber: string, carrier: string): Promise<TrackingStatus>;
}

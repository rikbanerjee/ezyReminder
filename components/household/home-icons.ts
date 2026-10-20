import { BatteryCharging, Car, GraduationCap, House, ReceiptText, ShoppingBasket, WashingMachine, Wind, Wrench } from "lucide-react";

/** Home category and section icons, shared by the Home tab and Today's Add flow. */
export const homeCategoryIcons = {
  car: Car,
  hvac: Wind,
  dryer: WashingMachine,
  battery: BatteryCharging,
  other: Wrench,
  bill: ReceiptText,
  study: GraduationCap,
};
export const homeSectionIcons = {
  care: House,
  groceries: ShoppingBasket,
  bills: ReceiptText,
  study: GraduationCap,
};

export type Diet = "veg" | "egg" | "non_veg";

export type Brand = {
  id: string;
  slug: string;
  name: string;
  tagline: string | null;
  theme: { accent?: string; accentInk?: string; logoUrl?: string };
};

export type Collection = {
  id: string;
  brandId: string;
  slug: string;
  name: string;
  orderCutoffAt: string | null;
  pickupDates: string[] | null;
  isPreorder: boolean;
};

export type StoreSettings = {
  timezone: string;
  currency: string;
  taxRateBps: number;
  leadTimeMinutes: number;
  slotMinutes: number;
  pickupHours: Record<string, [string, string] | null>;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  pickupInstructions: string | null;
  payAtPickup: boolean;
};

export type StoreConfig = {
  tenant: { id: string; slug: string; name: string };
  settings: StoreSettings;
  brands: Brand[];
  collections: Collection[];
};

export type Variant = {
  id: string;
  label: string;
  pack_qty: number | null;
  pack_unit: string | null;
  price_cents: number;
  sort: number;
  deleted_at: string | null;
};

export type MenuItem = {
  id: string;
  name: string;
  description: string | null;
  diet: Diet;
  protein: string | null;
  spice: number;
  allergens: string[];
  is_vegan: boolean;
  is_jain: boolean;
  image_url: string | null;
  is_available: boolean;
  is_catering_only: boolean;
  is_sample: boolean;
  sort: number;
  collection_id: string | null;
  category: { id: string; name: string; sort: number } | null;
  variants: Variant[];
};

export type OrderStatus = "pending_payment" | "confirmed" | "preparing" | "ready" | "completed" | "cancelled" | "refunded";

export type BoardOrder = {
  id: string;
  orderNumber: string;
  status: OrderStatus;
  channel: string;
  brand: string;
  brandSlug: string;
  pickupAt: string;
  createdAt: string;
  paidAt: string | null;
  firstName: string;
  notes: string | null;
  items: { name: string; variant: string | null; quantity: number; diet: Diet; station: string | null }[];
};

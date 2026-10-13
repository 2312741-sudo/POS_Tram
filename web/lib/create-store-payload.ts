/**
 * Chuẩn bị dữ liệu gửi Cloud Function `createStore` (functions/src/createStore.ts).
 * Logic thuần — không đụng Firebase. Máy chủ vẫn chuẩn hóa/kiểm tra lại mọi trường.
 */

export interface CreateStoreInput {
  storeCode?: string;
  storeName?: string;
  address?: string;
  phone?: string;
  wifiName?: string;
  bankId?: string;
  bankAccount?: string;
  accountName?: string;
  defaultVatRate?: number;
  allowStackPromotions?: boolean;
}

export interface CreateStorePayload {
  storeCode: string;
  storeName: string;
  address: string;
  phone: string;
  wifiName: string;
  bankId: string;
  bankAccount: string;
  accountName: string;
  defaultVatRate: number;
  allowStackPromotions: boolean;
}

/** Mã chi nhánh giống máy chủ: in hoa, chỉ A-Z 0-9 _ */
export function cleanStoreCode(raw: string | undefined): string {
  return (raw || "").toUpperCase().trim().replace(/[^A-Z0-9_]/g, "");
}

export function buildCreateStorePayload(input: CreateStoreInput): CreateStorePayload {
  const text = (v: string | undefined) => (v || "").trim();
  const vat = typeof input.defaultVatRate === "number" && Number.isFinite(input.defaultVatRate) ? input.defaultVatRate : 0;
  return {
    storeCode: cleanStoreCode(input.storeCode),
    storeName: text(input.storeName),
    address: text(input.address),
    phone: text(input.phone),
    wifiName: text(input.wifiName) || "Tram_FnB_WiFi",
    bankId: text(input.bankId),
    bankAccount: text(input.bankAccount),
    accountName: text(input.accountName) || "CHU CUA HANG",
    defaultVatRate: vat,
    allowStackPromotions: typeof input.allowStackPromotions === "boolean" ? input.allowStackPromotions : true,
  };
}

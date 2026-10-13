import { describe, it, expect } from "vitest";
import { buildCreateStorePayload, cleanStoreCode } from "../lib/create-store-payload";

describe("create-store-payload", () => {
  it("chuẩn hóa mã chi nhánh giống máy chủ", () => {
    expect(cleanStoreCode(" tram-02 ")).toBe("TRAM02");
    expect(cleanStoreCode(undefined)).toBe("");
  });

  it("ánh xạ đầy đủ trường và điền mặc định như trước đây", () => {
    const p = buildCreateStorePayload({
      storeCode: "q1",
      storeName: "  Quận 1 ",
      address: "",
      phone: "0900",
      wifiName: "",
      bankId: "VCB",
      bankAccount: "123",
      accountName: "",
      defaultVatRate: 8,
      allowStackPromotions: false,
    });
    expect(p).toEqual({
      storeCode: "Q1",
      storeName: "Quận 1",
      address: "",
      phone: "0900",
      wifiName: "Tram_FnB_WiFi",
      bankId: "VCB",
      bankAccount: "123",
      accountName: "CHU CUA HANG",
      defaultVatRate: 8,
      allowStackPromotions: false,
    });
  });

  it("VAT không phải số → 0; khuyến mãi mặc định bật", () => {
    const p = buildCreateStorePayload({ storeCode: "A1", storeName: "X", defaultVatRate: NaN });
    expect(p.defaultVatRate).toBe(0);
    expect(p.allowStackPromotions).toBe(true);
  });

  it("không đưa trường ngoài hợp đồng (ví dụ copyMenuFrom, id, createdAt) vào payload", () => {
    const input = { storeCode: "A1", storeName: "X", id: "A1", createdAt: 1, copyMenuFrom: "B2" };
    const p = buildCreateStorePayload(input);
    expect(Object.keys(p).sort()).toEqual([
      "accountName", "address", "allowStackPromotions", "bankAccount", "bankId",
      "defaultVatRate", "phone", "storeCode", "storeName", "wifiName",
    ]);
  });
});

import { describe, it, expect } from "vitest";
import { SAMPLE_BILL_LABELS, buildSampleBill, buildSampleDataUpdates, buildSampleRemovalUpdates, sampleCampaignForms } from "../lib/sample-data";
import type { HistoryOrder } from "../lib/data-context";
import { validateCampaignForm } from "../lib/campaign-form";
import { billItemDiscount, billLevelDiscount, billOtherOrderDiscount, billPointsDiscount, billSubTotal } from "../lib/reports";

const actor = { username: "chu", fullName: "Chủ" };

describe("dữ liệu mẫu", () => {
  it("có đủ 4 loại khuyến mãi và đều hợp lệ theo form", () => {
    const forms = sampleCampaignForms();
    expect(forms.map((f) => f.form.campaignType).sort()).toEqual(["BILLDISCOUNT", "BUYXGETY", "ITEMPRICERULE", "ORDERVALUEITEMBENEFIT"]);
    for (const f of forms) expect(validateCampaignForm(f.form)).toBeNull();
  });

  it("các dạng đơn: số liệu giảm giá khớp nhau", () => {
    const updates = buildSampleDataUpdates({ storeCode: "T1", storeName: "Trạm 1", actor, now: 1_000_000 });
    const bills = Object.entries(updates).filter(([k]) => k.startsWith("stores/T1/bills/")).map(([, v]) => v as ReturnType<typeof buildSampleBill>);
    expect(bills).toHaveLength(SAMPLE_BILL_LABELS.length);
    for (const b of bills) {
      expect(b.isSample).toBe(true);
      expect(b.status).toBe("PAID");
      expect(b.finalAmount).toBe(b.subTotal - b.totalDiscount);
      expect(b.totalDiscount).toBe(b.itemDiscounts + b.billDiscounts);
      expect(billSubTotal(b as unknown as HistoryOrder)).toBe(b.subTotal);
      expect(billItemDiscount(b as unknown as HistoryOrder)).toBe(b.itemDiscounts);
      expect(billLevelDiscount(b as unknown as HistoryOrder)).toBe(b.billDiscounts);
    }
    const kinds = new Set(bills.map((b) => b.sampleKind));
    for (const k of ["PLAIN", "ITEM_DISCOUNT", "ORDER_DISCOUNT", "PROMO_BILLDISCOUNT", "PROMO_ORDERITEM", "PROMO_BUYXGETY", "PROMO_ITEMPRICE", "VOUCHER", "POINTS", "COMBO"]) expect(kinds.has(k)).toBe(true);
    const points = bills.find((b) => b.sampleKind === "POINTS")!;
    expect(billPointsDiscount(points as unknown as HistoryOrder)).toBe(20000);
    expect(billOtherOrderDiscount(points as unknown as HistoryOrder)).toBe(0);
    expect(bills.find((b) => b.sampleKind === "PLAIN")!.totalDiscount).toBe(0);
    // history là bản sao của bills
    expect(updates["stores/T1/history/SAMPLE_BILL_1000000_0"]).toEqual(updates["stores/T1/bills/SAMPLE_BILL_1000000_0"]);
  });

  it("xóa mẫu chỉ động vào bản ghi isSample", () => {
    const rm = buildSampleRemovalUpdates("T1", {
      bills: { a: { isSample: true }, b: { id: "real" } },
      history: { a: { isSample: true } },
      campaigns: { c1: { isSample: true }, c2: {} },
    });
    expect(rm).toEqual({ "stores/T1/bills/a": null, "stores/T1/history/a": null, "stores/T1/campaigns/c1": null });
  });
});

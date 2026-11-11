import { describe, it, expect } from "vitest";
import { parseTableDiscounts, serializeTableDiscounts, splitTableDiscounts } from "../lib/table-discounts";

// Đúng dạng app ghi (BillDiscountModel.toMap): 1 combo + 1 giảm tay 10%
const appJson = JSON.stringify([
  { promoId: "CAM_1", description: "Combo bánh và nước giảm 10K", amount: 30000, campaignId: "CAM_1", campaignName: "Combo bánh và nước giảm 10K", programCode: "KM/HD0001", campaignType: "BUYXGETY", comboCount: 3 },
  { description: "Giảm giá thủ công (10%)", amount: 17000, manualPercent: 10 },
]);

describe("khuyến mãi trên bàn dùng chung app ↔ web", () => {
  it("web đọc được combo app đã áp và giảm tay của app", () => {
    const { campaigns, extras } = splitTableDiscounts(parseTableDiscounts(appJson));
    expect(campaigns.map((d) => [d.campaignId, d.amount])).toEqual([["CAM_1", 30000]]);
    expect(extras.map((d) => [d.description, d.amount])).toEqual([["Giảm giá thủ công (10%)", 17000]]);
  });

  it("ghi lại giữ đúng dạng app đọc được (không mất giảm tay, combo)", () => {
    const { campaigns, extras } = splitTableDiscounts(parseTableDiscounts(appJson));
    const out = JSON.parse(serializeTableDiscounts([...campaigns, ...extras])!);
    expect(out).toEqual(JSON.parse(appJson));
  });

  it("không còn khuyến mãi → null; dữ liệu hỏng → rỗng", () => {
    expect(serializeTableDiscounts([])).toBeNull();
    expect(parseTableDiscounts("không phải json")).toEqual([]);
    expect(parseTableDiscounts(null)).toEqual([]);
    expect(parseTableDiscounts(JSON.parse(appJson)).length).toBe(2);
  });
});

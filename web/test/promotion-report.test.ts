import { describe, it, expect } from "vitest";
import { calculateCampaignReport, campaignIdentity, campaignTypeLabel } from "../lib/promotion-report";
import type { HistoryOrder } from "../lib/reports";

const bill = (over: Partial<HistoryOrder>): HistoryOrder => ({ id: "b", status: "PAID", closedAt: 1000, finalAmount: 100000, ...over });

describe("calculateCampaignReport", () => {
  const bills: HistoryOrder[] = [
    bill({
      id: "1",
      billCode: "HD-1",
      tableName: "A1",
      cashierName: "Lan",
      discounts: [
        { campaignId: "C1", campaignName: "Giảm 10%", programCode: "KM10", campaignType: "BILL_DISCOUNT", voucherCode: "V1", amount: 10000 },
        { campaignId: "C2", campaignName: "Mua 1 tặng 1", programCode: "B1G1", campaignType: "BUYXGETY", amount: 30000 },
      ],
    }),
    bill({ id: "2", finalAmount: 50000, closedAt: 2000, discounts: [{ campaignId: "C1", campaignName: "Giảm 10%", voucherCode: "V2", amount: 5000 }] }),
    bill({ id: "3", discounts: [{ promoId: "OLD", promoCode: "TRIAN10K", description: "Tri ân", amount: 10000 }] }),
    bill({ id: "4", discounts: [{ description: "Thủ công", amount: 2000 }, { description: "Thủ công", amount: 3000 }] }),
    bill({ id: "5", status: "CANCELLED", discounts: [{ campaignId: "C1", amount: 99999 }] }),
    bill({ id: "6" }),
  ];
  const r = calculateCampaignReport(bills);

  it("nhóm theo campaignId, fallback promoId / tên", () => {
    expect(r.campaigns.map((c) => c.key).sort()).toEqual(["id:C1", "id:C2", "id:OLD", "name:Thủ công"]);
  });

  it("tổng hợp từng chiến dịch (bỏ đơn hủy)", () => {
    const c1 = r.campaigns.find((c) => c.campaignId === "C1")!;
    expect(c1).toMatchObject({ name: "Giảm 10%", code: "KM10", typeLabel: "Giảm giá đơn hàng", billCount: 2, totalDiscount: 15000, revenue: 150000, vouchersUsed: 2 });
    expect(c1.voucherCodes).toEqual(["V1", "V2"]);
    expect(c1.bills.map((b) => b.billId)).toEqual(["2", "1"]);
    expect(c1.bills[1]).toMatchObject({ billCode: "HD-1", tableName: "A1", voucherCode: "V1", discount: 10000, staff: "Lan" });
  });

  it("nhiều dòng cùng chiến dịch trên 1 hóa đơn → 1 hóa đơn, cộng tiền giảm", () => {
    const m = r.campaigns.find((c) => c.key === "name:Thủ công")!;
    expect(m.billCount).toBe(1);
    expect(m.totalDiscount).toBe(5000);
    expect(m.revenue).toBe(100000);
  });

  it("tổng: hóa đơn không trùng, doanh thu không trùng", () => {
    expect(r.billCount).toBe(4);
    expect(r.totalDiscount).toBe(60000);
    expect(r.revenue).toBe(350000);
    expect(r.vouchersUsed).toBe(2);
  });

  it("nhãn loại & định danh", () => {
    expect(campaignTypeLabel("ITEM_PRICE_RULE")).toBe("Đồng giá / đồng giảm");
    expect(campaignTypeLabel("")).toBe("Khuyến mãi (dữ liệu cũ)");
    expect(campaignIdentity({ promoCode: "X" })).toMatchObject({ key: "code:X", name: "X" });
  });
});

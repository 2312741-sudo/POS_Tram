import { describe, it, expect } from "vitest";
import {
  DEFAULT_LOYALTY_TIERS,
  SUGGESTED_LOYALTY_TIERS,
  buildNewCustomerNode,
  LEDGER_TYPE_LABEL,
  effectiveConfig,
  memberKeyOf,
  parseChainConfig,
  parseLedgerEntries,
  totalsByMember,
  validateAdjustInput,
  hasCustomTiers,
  normalizePhone,
  normalizeTiers,
  parseLoyaltyLedger,
  parsePointHistory,
  pointsToNextTier,
  sortHistoryDesc,
  summarizeHistory,
  tierForTotalPoints,
  validateNewCustomer,
  validateTiers,
} from "../lib/loyalty";


describe("cấu hình hạng", () => {
  it("mặc định khi chưa cấu hình / sai định dạng", () => {
    expect(normalizeTiers(undefined)).toEqual(DEFAULT_LOYALTY_TIERS);
    expect(normalizeTiers([{ name: "", minPoints: 5 }, "x"])).toEqual(DEFAULT_LOYALTY_TIERS);
  });

  it("đọc mảng hoặc object, sắp xếp và ép hạng thấp nhất về 0", () => {
    const t = normalizeTiers({ a: { name: "Vàng", minPoints: 300 }, b: { name: "Bạc", minPoints: 100 } });
    expect(t).toEqual([{ name: "Bạc", minPoints: 0 }, { name: "Vàng", minPoints: 300 }]);
  });

  it("validate: trùng tên, trùng mức, không bắt đầu từ 0, số âm", () => {
    expect(validateTiers(DEFAULT_LOYALTY_TIERS)).toBeNull();
    expect(validateTiers(SUGGESTED_LOYALTY_TIERS)).toBeNull();
    expect(validateTiers([])).toMatch(/ít nhất/);
    expect(validateTiers([{ name: "A", minPoints: 0 }, { name: "a", minPoints: 5 }])).toMatch(/trùng/);
    expect(validateTiers([{ name: "A", minPoints: 0 }, { name: "B", minPoints: 0 }])).toMatch(/cùng mức/);
    expect(validateTiers([{ name: "A", minPoints: 10 }])).toMatch(/từ 0/);
    expect(validateTiers([{ name: "A", minPoints: -1 }])).toMatch(/≥ 0/);
    expect(validateTiers([{ name: "A", minPoints: 0.5 }])).toMatch(/số nguyên/);
  });

  it("chưa cấu hình: chỉ có hạng gốc, mọi mốc do Chủ quán tự đặt", () => {
    expect(DEFAULT_LOYALTY_TIERS).toEqual([{ name: "Thành viên", minPoints: 0 }]);
    expect(hasCustomTiers(DEFAULT_LOYALTY_TIERS)).toBe(false);
    expect(tierForTotalPoints(99999)).toBe("Thành viên");
    expect(hasCustomTiers([{ name: "A", minPoints: 0 }, { name: "B", minPoints: 10 }])).toBe(true);
  });

  it("xếp hạng và điểm còn thiếu theo mốc tự đặt", () => {
    const t = SUGGESTED_LOYALTY_TIERS;
    expect(tierForTotalPoints(499, t)).toBe("Bạc");
    expect(tierForTotalPoints(500, t)).toBe("Vàng");
    expect(pointsToNextTier(450, t)).toEqual({ name: "Vàng", missing: 50 });
    expect(pointsToNextTier(5000, t)).toBeNull();
  });
});

describe("khách hàng mới", () => {
  it("chuẩn hóa SĐT", () => {
    expect(normalizePhone("+84 912 345 678")).toBe("0912345678");
    expect(normalizePhone("0912.345.678")).toBe("0912345678");
    expect(normalizePhone("84912345678")).toBe("0912345678");
    expect(normalizePhone("123")).toBeNull();
  });

  it("từ chối tên rỗng, SĐT sai hoặc trùng", () => {
    const existing = [{ soDienThoai: "0912345678" }];
    expect(validateNewCustomer({ name: " ", phone: "0912345679" }, existing)).toHaveProperty("error");
    expect(validateNewCustomer({ name: "An", phone: "12" }, existing)).toHaveProperty("error");
    expect(validateNewCustomer({ name: "An", phone: "+84912345678" }, existing)).toHaveProperty("error");
    expect(validateNewCustomer({ name: " An ", phone: "0912345679" }, existing)).toEqual({ name: "An", phone: "0912345679" });
  });

  it("node mới có điểm 0 (rules Thu ngân chỉ cho tạo khách 0 điểm)", () => {
    const n = buildNewCustomerNode("CUST_1", { name: "An", phone: "0912345678" }, 1000);
    expect(n).toMatchObject({ diem_hien_tai: 0, currentPoints: 0, totalPoints: 0, ho_ten: "An", so_dien_thoai: "0912345678" });
    expect(n).not.toHaveProperty("lastLoyaltyOp");
  });
});

describe("chỉnh điểm (kiểm tra trước khi gọi callable)", () => {
  const base = { balance: 100 };
  it("bắt buộc lý do, số nguyên không âm, không trừ quá số dư, không để nguyên số dư", () => {
    expect(validateAdjustInput({ ...base, mode: "ADD", value: 10, reason: " " })).not.toBeNull();
    expect(validateAdjustInput({ ...base, mode: "ADD", value: -1, reason: "sinh nhật" })).not.toBeNull();
    expect(validateAdjustInput({ ...base, mode: "ADD", value: 1.5, reason: "sinh nhật" })).not.toBeNull();
    expect(validateAdjustInput({ ...base, mode: "SUB", value: 101, reason: "sửa nhầm" })).toMatch(/không thể trừ/);
    expect(validateAdjustInput({ ...base, mode: "SET", value: 100, reason: "sửa nhầm" })).toMatch(/không thay đổi/);
    expect(validateAdjustInput({ ...base, mode: "ADD", value: 200, reason: "Tặng sinh nhật" })).toBeNull();
    expect(validateAdjustInput({ ...base, mode: "SET", value: 20, reason: "Sửa nhầm" })).toBeNull();
  });
});

describe("lịch sử điểm", () => {
  it("đọc sổ cái POS (đổi = âm) và sổ chỉnh tay, sắp xếp mới nhất trước", () => {
    const ledger = parseLoyaltyLedger("T1", {
      B1: { redeem: { customerId: "C1", points: 10, before: 50, after: 40, at: 100, by: "nv" }, award: { customerId: "C1", points: 3, before: 40, after: 43, at: 200, by: "nv" } },
      B2: { bogus: { points: 1 } },
    });
    const manual = parsePointHistory("T1", { adj1: { customerId: "C1", delta: -5, before: 43, after: 38, at: 300, byName: "QL", reason: "sai" } });
    const all = sortHistoryDesc([...ledger, ...manual]);
    expect(all.map((r) => r.type)).toEqual(["ADJUST", "AWARD", "REDEEM"]);
    expect(all.find((r) => r.type === "REDEEM")!.delta).toBe(-10);
    expect(summarizeHistory(all)).toEqual({ earned: 3, redeemed: 10, adjusted: -5 });
  });
});

describe("điểm dùng chung toàn chuỗi", () => {
  const mk = (storeCode: string, id: string, phone: string, pts: number, total = pts) =>
    ({ id, storeCode, soDienThoai: phone, diemHienTai: pts, tongDiem: total });

  it("khóa bản ghi: SĐT chuẩn hóa, không SĐT thì riêng theo chi nhánh/khách", () => {
    expect(memberKeyOf("+84 912 345 678", "A", "1")).toBe("0912345678");
    expect(memberKeyOf("", "A", "x.y")).toBe("L_A_x_y");
  });

  it("tổng toàn chuỗi không đếm trùng khách cùng SĐT ở nhiều chi nhánh (các node mang cùng bản sao số dư)", () => {
    const t = totalsByMember([mk("A", "1", "0912345678", 110, 600), mk("B", "2", "+84912345678", 110, 600), mk("A", "3", "", 5), mk("B", "4", "", 7)]);
    expect(t).toEqual({ members: 3, points: 122, totalPoints: 612, duplicateNodes: 1 });
  });

  it("cấu hình chuỗi ưu tiên hơn chi nhánh; thiếu thì dùng của chi nhánh; mốc hạng không có mặc định ngầm", () => {
    const chain = parseChainConfig({ pointEarnRate: 2, loyaltyTiers: [{ name: "Vàng", minPoints: 500 }] });
    expect(chain.pointRedeemRate).toBeUndefined();
    const eff = effectiveConfig({ pointEarnRate: 1, pointRedeemRate: 500, loyaltyTiers: [{ name: "Bạc", minPoints: 0 }] }, chain);
    expect(eff.pointEarnRate).toBe(2);
    expect(eff.pointRedeemRate).toBe(500);
    expect(eff.loyaltyTiers[0].name).toBe("Vàng"); // hạng thấp nhất luôn về 0 điểm
    expect(effectiveConfig(undefined, {}).loyaltyTiers).toEqual(DEFAULT_LOYALTY_TIERS);
    expect(parseChainConfig(null)).toEqual({});
  });

  it("đọc sổ cái dùng chung: bỏ dòng sai, mới nhất trước, có cột chi nhánh", () => {
    const rows = parseLedgerEntries([
      { id: "b1_earn", type: "earn", points: 20, balanceAfter: 120, storeCode: "A", billId: "b1", staff: "nv", at: 100 },
      { id: "b2_redeem", type: "redeem", points: -50, balanceAfter: 70, storeCode: "B", billId: "b2", staff: "nv", at: 200 },
      { id: "x", type: "bogus", points: 1, at: 300 },
      "rác",
    ]);
    expect(rows.map((r) => [r.id, r.storeCode, r.points])).toEqual([["b2_redeem", "B", -50], ["b1_earn", "A", 20]]);
    expect(LEDGER_TYPE_LABEL[rows[0].type]).toContain("Đổi điểm");
    expect(parseLedgerEntries(undefined)).toEqual([]);
  });
});

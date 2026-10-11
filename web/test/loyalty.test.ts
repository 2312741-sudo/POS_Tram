import { describe, it, expect } from "vitest";
import {
  DEFAULT_LOYALTY_TIERS,
  SUGGESTED_LOYALTY_TIERS,
  buildNewCustomerNode,
  buildPooledRedeemUpdates,
  hasCustomTiers,
  planPooledRedeem,
  buildPointAdjustment,
  buildSharedLoyaltyUpdates,
  normalizePhone,
  normalizeTiers,
  parseLoyaltyLedger,
  parsePointHistory,
  pointsToNextTier,
  poolCustomersByPhone,
  sortHistoryDesc,
  summarizeHistory,
  tierForTotalPoints,
  validateNewCustomer,
  validateTiers,
} from "../lib/loyalty";

const actor = { username: "ql1", fullName: "Quản lý 1", role: "ROLE_MANAGER_1" };
const cust = { id: "C1", hoTen: "An", diemHienTai: 100, tongDiem: 300 };

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

describe("chỉnh điểm", () => {
  const base = { storeCode: "T1", customer: cust, actor, tiers: SUGGESTED_LOYALTY_TIERS, now: 5000, nonce: "n" };

  it("bắt buộc lý do, số nguyên không âm, không trừ quá số dư", () => {
    expect(buildPointAdjustment({ ...base, mode: "ADD", value: 10, reason: " " })).toMatchObject({ ok: false });
    expect(buildPointAdjustment({ ...base, mode: "ADD", value: -1, reason: "x" })).toMatchObject({ ok: false });
    expect(buildPointAdjustment({ ...base, mode: "ADD", value: 1.5, reason: "x" })).toMatchObject({ ok: false });
    expect(buildPointAdjustment({ ...base, mode: "SUB", value: 101, reason: "x" })).toMatchObject({ ok: false });
    expect(buildPointAdjustment({ ...base, mode: "SET", value: 100, reason: "x" })).toMatchObject({ ok: false });
  });

  it("cộng điểm tăng cả tổng lịch sử và lên hạng", () => {
    const r = buildPointAdjustment({ ...base, mode: "ADD", value: 200, reason: "Tặng sinh nhật" });
    if (!r.ok) throw new Error(r.error);
    expect(r.after).toBe(300);
    expect(r.updates["stores/T1/customers/C1/diem_hien_tai"]).toBe(300);
    expect(r.updates["stores/T1/customers/C1/currentPoints"]).toBe(300);
    expect(r.updates["stores/T1/customers/C1/totalPoints"]).toBe(500);
    expect(r.updates["stores/T1/customers/C1/hang_thanh_vien"]).toBe("Vàng");
    expect(r.updates["stores/T1/point_history/adj_5000_n"]).toMatchObject({ delta: 200, before: 100, after: 300, reason: "Tặng sinh nhật" });
    expect(r.updates["stores/T1/audit_logs/log_5000_pt_n"]).toMatchObject({ action: "ADJUST_POINTS", username: "ql1" });
  });

  it("trừ / đặt lại điểm không làm giảm tổng lịch sử", () => {
    const r = buildPointAdjustment({ ...base, mode: "SET", value: 20, reason: "Sửa nhầm" });
    if (!r.ok) throw new Error(r.error);
    expect(r.delta).toBe(-80);
    expect(r.updates["stores/T1/customers/C1/totalPoints"]).toBe(300);
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

describe("điểm dùng chung toàn hệ thống", () => {
  it("ghi cấu hình + audit cho từng chi nhánh", () => {
    const u = buildSharedLoyaltyUpdates({ storeCodes: ["A", "B"], enabled: true, actor: { username: "chu" }, now: 9 });
    expect(u["stores/A/storeInfo/sharedLoyalty"]).toEqual({ enabled: true, deductOrder: "HOME_FIRST", confirmedBy: "chu", confirmedAt: 9 });
    expect(Object.keys(u)).toHaveLength(4);
  });

  it("gộp khách theo SĐT chuẩn hóa", () => {
    const mk = (storeCode: string, id: string, phone: string, pts: number) =>
      ({ id, storeCode, soDienThoai: phone, hoTen: "An", maKhachHang: id, diemHienTai: pts, tongDiem: pts, hangThanhVien: "" });
    const pooled = poolCustomersByPhone([mk("A", "1", "0912345678", 10), mk("B", "2", "+84912345678", 5), mk("A", "3", "xx", 99)]);
    expect(pooled).toHaveLength(1);
    expect(pooled[0]).toMatchObject({ phone: "0912345678", totalCurrent: 15 });
  });
});

describe("trừ điểm dùng chung", () => {
  const holdings = [
    { storeCode: "A", customerId: "a1", points: 30 },
    { storeCode: "B", customerId: "b1", points: 80 },
    { storeCode: "C", customerId: "c1", points: 0 },
  ];

  it("HOME_FIRST: trừ chi nhánh đang thao tác trước rồi tới chi nhánh nhiều điểm nhất", () => {
    const r = planPooledRedeem({ holdings, points: 50, homeStore: "A", order: "HOME_FIRST" });
    if ("error" in r) throw new Error(r.error);
    expect(r.allocations.map((a) => [a.storeCode, a.take, a.after])).toEqual([["A", 30, 0], ["B", 20, 60]]);
  });

  it("LARGEST_FIRST: chi nhánh nhiều điểm nhất trước", () => {
    const r = planPooledRedeem({ holdings, points: 100, homeStore: "A", order: "LARGEST_FIRST" });
    if ("error" in r) throw new Error(r.error);
    expect(r.allocations.map((a) => [a.storeCode, a.take])).toEqual([["B", 80], ["A", 20]]);
  });

  it("từ chối khi không đủ điểm hoặc số điểm sai", () => {
    expect(planPooledRedeem({ holdings, points: 111, order: "HOME_FIRST" })).toHaveProperty("error");
    expect(planPooledRedeem({ holdings, points: 0, order: "HOME_FIRST" })).toHaveProperty("error");
    expect(planPooledRedeem({ holdings, points: 1.5, order: "HOME_FIRST" })).toHaveProperty("error");
  });

  it("ghi từng chi nhánh: giảm điểm, giữ tổng lịch sử, có lịch sử + nhật ký; bắt buộc lý do", () => {
    const plan = planPooledRedeem({ holdings, points: 50, homeStore: "A", order: "HOME_FIRST" });
    if ("error" in plan) throw new Error(plan.error);
    const base = { allocations: plan.allocations, customerName: "An", phone: "0912345678", actor, now: 7, nonce: "n" };
    expect(buildPooledRedeemUpdates({ ...base, reason: " " })).toHaveProperty("error");
    const r = buildPooledRedeemUpdates({ ...base, reason: "HD-1" });
    if ("error" in r) throw new Error(r.error);
    expect(r.updates["stores/A/customers/a1/diem_hien_tai"]).toBe(0);
    expect(r.updates["stores/B/customers/b1/currentPoints"]).toBe(60);
    expect(Object.keys(r.updates).some((k) => k.endsWith("/totalPoints"))).toBe(false);
    expect(r.updates["stores/B/point_history/pool_7_n_B"]).toMatchObject({ type: "POOL_REDEEM", delta: -20, before: 80, after: 60 });
    expect(r.updates["stores/A/audit_logs/log_7_pool_n_A"]).toMatchObject({ action: "LOYALTY_POOL_REDEEM" });
  });
});

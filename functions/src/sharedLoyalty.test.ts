import { describe, it, expect } from "vitest";
import {
  applyOp,
  billOpId,
  buildLedgerEntry,
  buildLedgerHistory,
  computeEarnPoints,
  memberKeyFor,
  newMember,
  planBranchCacheUpdates,
  planMigration,
  pruneOps,
  resolveRates,
  type Member,
  type OpRequest,
} from "./sharedLoyalty";

const NOW = 1_700_000_000_000;
const req = (o: Partial<OpRequest> & Pick<OpRequest, "type" | "points" | "opId">): OpRequest => ({ storeCode: "A", now: NOW, ...o });
const withPts = (points: number, totalPoints = points): Member => ({ ...newMember("An", "0912345678", "A", NOW), points, totalPoints });

describe("khóa bản ghi điểm", () => {
  it("SĐT hợp lệ (mọi định dạng) → cùng một khóa cho mọi chi nhánh", () => {
    expect(memberKeyFor("+84 912 345 678", "A", "c1")).toBe("0912345678");
    expect(memberKeyFor("0912.345.678", "B", "c9")).toBe("0912345678");
  });
  it("không có SĐT hợp lệ → bản ghi riêng theo chi nhánh/khách", () => {
    expect(memberKeyFor("", "A", "c1")).toBe("L_A_c1");
    expect(memberKeyFor("123", "B", "x.y")).toBe("L_B_x_y");
  });
  it("opId theo hóa đơn bỏ ký tự cấm", () => {
    expect(billOpId("B/1.2", "redeem")).toBe("B_1_2_redeem");
  });
});

describe("tính điểm tích", () => {
  it("khớp công thức Flutter: số tiền × rate% / đ-mỗi-điểm", () => {
    expect(computeEarnPoints(2_000_000, 1, 1000)).toBe(20);
    expect(computeEarnPoints(0, 1, 1000)).toBe(0);
    expect(computeEarnPoints(500, 1, 1000)).toBe(0);
    expect(computeEarnPoints(10_000, 0, 1000)).toBe(0);
  });
  it("ưu tiên cấu hình chuỗi, thiếu thì storeInfo, thiếu nữa thì mặc định 1% / 1000đ", () => {
    expect(resolveRates({ pointEarnRate: 2, pointRedeemRate: 500 }, { pointEarnRate: 9, pointRedeemRate: 9 })).toEqual({ earnRate: 2, redeemRate: 500, source: "chain" });
    expect(resolveRates(null, { pointEarnRate: 3, pointRedeemRate: 2000 })).toEqual({ earnRate: 3, redeemRate: 2000, source: "store" });
    expect(resolveRates({ pointEarnRate: 4 }, { pointRedeemRate: 700 })).toEqual({ earnRate: 4, redeemRate: 700, source: "chain" });
    expect(resolveRates(null, null)).toEqual({ earnRate: 1, redeemRate: 1000, source: "default" });
  });
});

describe("applyOp", () => {
  it("earn tạo bản ghi mới và cộng cả điểm hiện tại lẫn tổng", () => {
    const r = applyOp(null, req({ type: "earn", points: 20, opId: "b1_earn", name: "An", phone: "0912345678" }));
    expect(r.status).toBe("applied");
    expect(r.member).toMatchObject({ points: 20, totalPoints: 20, name: "An", phone: "0912345678", lastStoreCode: "A" });
  });
  it("idempotent: cùng opId không áp dụng lần 2", () => {
    const first = applyOp(withPts(10), req({ type: "earn", points: 5, opId: "b1_earn" }));
    const again = applyOp(first.member!, req({ type: "earn", points: 5, opId: "b1_earn" }));
    expect(again.status).toBe("alreadyApplied");
    expect(first.member!.points).toBe(15);
  });
  it("redeem không đủ điểm → insufficient, không đổi gì", () => {
    const r = applyOp(withPts(10), req({ type: "redeem", points: 11, opId: "b2_redeem" }));
    expect(r).toMatchObject({ status: "insufficient", before: 10, after: 10 });
    expect(r.member).toBeUndefined();
  });
  it("redeem giữ nguyên totalPoints (không tụt hạng) và dùng được điểm tích ở chi nhánh khác", () => {
    const r = applyOp(withPts(100, 300), req({ type: "redeem", points: 40, opId: "b3_redeem", storeCode: "B" }));
    expect(r.member).toMatchObject({ points: 60, totalPoints: 300, lastStoreCode: "B" });
  });
  it("refund chỉ hoàn đúng số điểm đã đổi, đúng 1 lần", () => {
    const red = applyOp(withPts(50), req({ type: "redeem", points: 30, opId: "b4_redeem" }));
    const ref1 = applyOp(red.member!, req({ type: "refund", points: 999, opId: "b4_refund" }));
    expect(ref1).toMatchObject({ status: "applied", applied: 30, after: 50 });
    const ref2 = applyOp(ref1.member!, req({ type: "refund", points: 30, opId: "b4_refund" }));
    expect(ref2.status).toBe("alreadyApplied");
  });
  it("refund không có redeem tương ứng → nothingToRefund", () => {
    expect(applyOp(withPts(50), req({ type: "refund", points: 5, opId: "zz_refund" })).status).toBe("nothingToRefund");
  });
  it("adjust: cộng làm tăng cả tổng; trừ chỉ giảm điểm hiện tại; không cho âm", () => {
    const add = applyOp(withPts(10, 10), req({ type: "adjust", points: 5, opId: "adj_1" }));
    expect(add.member).toMatchObject({ points: 15, totalPoints: 15 });
    const sub = applyOp(add.member!, req({ type: "adjust", points: -4, opId: "adj_2" }));
    expect(sub.member).toMatchObject({ points: 11, totalPoints: 15 });
    expect(applyOp(sub.member!, req({ type: "adjust", points: -12, opId: "adj_3" })).status).toBe("insufficient");
  });
  it("adjust SET đặt số dư; không đổi → invalid", () => {
    const up = applyOp(withPts(10, 10), req({ type: "adjust", points: 1, setTo: 25, opId: "adj_s1" }));
    expect(up.member).toMatchObject({ points: 25, totalPoints: 25 });
    const down = applyOp(up.member!, req({ type: "adjust", points: 1, setTo: 5, opId: "adj_s2" }));
    expect(down.member).toMatchObject({ points: 5, totalPoints: 25 });
    expect(applyOp(down.member!, req({ type: "adjust", points: 1, setTo: 5, opId: "adj_s3" })).status).toBe("invalid");
  });
  it("từ chối số điểm không nguyên / bằng 0 / quá lớn", () => {
    expect(applyOp(withPts(1), req({ type: "earn", points: 1.5, opId: "x" })).status).toBe("invalid");
    expect(applyOp(withPts(1), req({ type: "earn", points: 0, opId: "x" })).status).toBe("invalid");
    expect(applyOp(withPts(1), req({ type: "earn", points: 99_000_000, opId: "x" })).status).toBe("invalid");
    expect(applyOp(withPts(1), req({ type: "redeem", points: -1, opId: "x" })).status).toBe("invalid");
  });
  it("vòng khóa được cắt để không phình bản ghi", () => {
    const ops: Record<string, { p: number; t: "earn"; at: number }> = {};
    for (let i = 0; i < 12; i++) ops[`k${i}`] = { p: 1, t: "earn", at: i };
    const kept = pruneOps(ops, 5);
    expect(Object.keys(kept).sort()).toEqual(["k10", "k11", "k7", "k8", "k9"]);
  });
  it("sổ cái ghi dấu theo loại thao tác và số dư sau", () => {
    const r = applyOp(withPts(50), req({ type: "redeem", points: 20, opId: "b5_redeem" }));
    const e = buildLedgerEntry(req({ type: "redeem", points: 20, opId: "b5_redeem" }), r, { billId: "b5", staff: "thu" });
    expect(e).toMatchObject({ type: "redeem", points: -20, balanceAfter: 30, storeCode: "A", billId: "b5", staff: "thu" });
    const h = buildLedgerHistory("0912345678", "b5_redeem", { ...e, customerId: "c1" });
    expect(h).toMatchObject({ data: { ma_khach_hang: "c1", diem_truoc: 50, diem_thay_doi: -20, diem_sau: 30, nguon: "fnb_pos_redeem" } });
  });
});

describe("cache điểm trên node khách chi nhánh", () => {
  it("chỉ cập nhật node còn tồn tại và đang lệch", () => {
    const m = withPts(70, 200);
    const u = planBranchCacheUpdates(m, [
      { storeCode: "A", customerId: "a1", node: { diem_hien_tai: 10, currentPoints: 10, totalPoints: 10 } },
      { storeCode: "B", customerId: "b1", node: { diem_hien_tai: 70, currentPoints: 70, totalPoints: 200 } },
      { storeCode: "C", customerId: "c1", node: null },
    ]);
    expect(u).toEqual({
      "stores/A/customers/a1/diem_hien_tai": 70,
      "stores/A/customers/a1/currentPoints": 70,
      "stores/A/customers/a1/totalPoints": 200,
    });
  });
});

describe("planMigration (gom theo SĐT)", () => {
  const c = (storeCode: string, customerId: string, phone: string, points: number, totalPoints: number, extra: object = {}) => ({ storeCode, customerId, name: `${storeCode}-${customerId}`, phone, points, totalPoints, ...extra });
  it("cộng điểm và tổng điểm của mọi chi nhánh cùng SĐT; tổng toàn chuỗi không đổi", () => {
    const plan = planMigration([
      c("A", "a1", "0912345678", 30, 100, { createdAt: 5 }),
      c("B", "b1", "+84912345678", 80, 500, { createdAt: 3 }),
      c("C", "c1", "0987654321", 7, 7),
      c("C", "c2", "", 11, 20),
      c("A", "a2", "abc", 4, 4),
    ]);
    expect(plan.groups).toHaveLength(2);
    const g = plan.groups.find((x) => x.memberKey === "0912345678")!;
    expect(g).toMatchObject({ points: 110, totalPoints: 600, joinedAt: 3, lastStoreCode: "B", duplicate: true, name: "B-b1" });
    expect(plan.localOnly.map((x) => x.memberKey).sort()).toEqual(["L_A_a2", "L_C_c2"]);
    expect(plan.totals.sharedPoints).toBe(plan.totals.branchPoints);
    expect(plan.totals.sharedTotalPoints).toBe(plan.totals.branchTotalPoints);
    expect(plan.totals.sharedPoints).toBe(30 + 80 + 7 + 11 + 4);
  });
  it("trùng SĐT trong cùng chi nhánh cũng được gom", () => {
    const plan = planMigration([c("A", "a1", "0900000001", 5, 5), c("A", "a2", "0900000001", 6, 9)]);
    expect(plan.groups[0]).toMatchObject({ points: 11, totalPoints: 14, duplicate: true });
  });
});

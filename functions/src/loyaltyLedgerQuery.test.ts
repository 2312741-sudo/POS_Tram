import { describe, it, expect } from "vitest";
import {
  clampLimit, computeTotals, filterIndex, filterRows, fold, monthKey, monthsBetween, paginate, sortRows, toRow, indexPath,
  type LedgerRow,
} from "./loyaltyLedgerQuery";

const row = (o: Partial<LedgerRow>): LedgerRow => ({
  opId: "o", memberKey: "0912345678", memberName: "Nguyễn Đức", memberPhone: "0912345678", type: "earn", points: 10, balanceAfter: 10,
  billId: "", billCode: "", storeCode: "A", customerId: "", staff: "", note: "", at: 1000, ...o,
});

describe("loyaltyLedgerQuery", () => {
  it("monthKey theo giờ VN và monthsBetween", () => {
    // 2026-01-31 18:00 UTC = 01:00 ngày 1/2 giờ VN
    expect(monthKey(Date.UTC(2026, 0, 31, 18))).toBe("202602");
    expect(monthsBetween(Date.UTC(2025, 10, 15), Date.UTC(2026, 1, 2))).toEqual(["202511", "202512", "202601", "202602"]);
    expect(monthsBetween(5, 1)).toEqual([]);
    expect(indexPath("0912", "x_earn", Date.UTC(2026, 0, 10))).toBe("loyalty_ledger_index/202601/0912~x_earn");
  });

  it("fold bỏ dấu, đ -> d", () => {
    expect(fold("  Nguyễn Đức  ")).toBe("nguyen duc");
  });

  it("lọc theo khoảng thời gian, loại, chi nhánh", () => {
    const rows = [row({ opId: "1", at: 100 }), row({ opId: "2", at: 200, type: "redeem", points: -5 }), row({ opId: "3", at: 300, storeCode: "B" })];
    expect(filterRows(rows, { stores: null, from: 150, to: 250 }).map((r) => r.opId)).toEqual(["2"]);
    expect(filterRows(rows, { stores: null, types: ["redeem"] }).map((r) => r.opId)).toEqual(["2"]);
    expect(filterRows(rows, { stores: new Set(["B"]) }).map((r) => r.opId)).toEqual(["3"]);
    expect(filterRows(rows, { stores: new Set() })).toEqual([]);
    expect(filterRows([row({ opId: "c", customerId: "KH1" }), row({ opId: "d", customerId: "KH2" })], { stores: null, customerId: "KH1" }).map((r) => r.opId)).toEqual(["c"]);
    expect(filterRows(rows, { stores: null, types: [] })).toHaveLength(3);
  });

  it("tìm kiếm không phân biệt dấu: tên, SĐT, mã HĐ, ghi chú", () => {
    const rows = [
      row({ opId: "1" }),
      row({ opId: "2", memberName: "Trần Thị", memberKey: "0900000001", memberPhone: "0900000001", billCode: "HD-0042" }),
      row({ opId: "3", memberKey: "0900000002", memberName: "Lê", memberPhone: "0900000002", note: "Tặng sinh nhật" }),
    ];
    const f = (search: string) => filterRows(rows, { stores: null, search }).map((r) => r.opId);
    expect(f("nguyen duc")).toEqual(["1"]);
    expect(f("0900000001")).toEqual(["2"]);
    expect(f("hd-0042")).toEqual(["2"]);
    expect(f("SINH NHAT")).toEqual(["3"]);
    expect(f("zzz")).toEqual([]);
  });

  it("filterIndex dùng chi nhánh/thời gian/loại", () => {
    const e = [
      { memberKey: "m", opId: "1", at: 10, storeCode: "A", type: "earn" },
      { memberKey: "m", opId: "2", at: 20, storeCode: "B", type: "redeem" },
    ];
    expect(filterIndex(e, { stores: new Set(["A"]) })).toHaveLength(1);
    expect(filterIndex(e, { stores: null, from: 15 })).toHaveLength(1);
    expect(filterIndex(e, { stores: null, types: ["redeem"] })[0].opId).toBe("2");
  });

  it("totals: tích/hoàn, đổi, chỉnh tay ròng, đếm", () => {
    const t = computeTotals([
      row({ type: "earn", points: 50 }), row({ type: "refund", points: 10 }), row({ type: "redeem", points: -30 }),
      row({ type: "adjust", points: -5 }), row({ type: "opening", points: 100 }),
    ]);
    expect(t).toEqual({ earned: 60, redeemed: 30, manual: 95, count: 5 });
  });

  it("phân trang bằng cursor, kể cả trùng thời điểm", () => {
    const rows = sortRows([1, 2, 3, 4, 5].map((i) => row({ opId: `o${i}`, at: i <= 3 ? 500 : 100 * i })));
    const p1 = paginate(rows, undefined, 2)!;
    expect(p1.page).toHaveLength(2);
    expect(p1.nextCursor).toBeTruthy();
    const p2 = paginate(rows, p1.nextCursor, 2)!;
    const p3 = paginate(rows, p2.nextCursor, 2)!;
    expect(p3.nextCursor).toBeUndefined();
    const ids = [...p1.page, ...p2.page, ...p3.page].map((r) => r.opId);
    expect(new Set(ids).size).toBe(5);
    expect(ids).toEqual(rows.map((r) => r.opId));
    expect(paginate(rows, "bad", 2)).toBeNull();
  });

  it("clampLimit", () => {
    expect(clampLimit(undefined)).toBe(200);
    expect(clampLimit(9999)).toBe(500);
    expect(clampLimit(0)).toBe(1);
  });

  it("toRow chịu dữ liệu thiếu", () => {
    expect(toRow("m", "o", null, null)).toBeNull();
    expect(toRow("m", "o", { type: "earn" }, null)).toBeNull();
    const r = toRow("L_A_1", "o", { type: "earn", points: 3, at: 5, storeCode: "A" }, { name: "X" })!;
    expect(r.memberPhone).toBe("");
    expect(r.memberName).toBe("X");
    expect(r.points).toBe(3);
  });
});

import { describe, it, expect, vi } from "vitest";

vi.mock("../lib/firebase", () => ({ functions: {} }));
vi.mock("firebase/functions", () => ({ httpsCallable: vi.fn() }));

import { buildLedgerCsv, dayEndMs, dayStartMs, ledgerErrorMessage, ledgerKindLabel, parseLedgerPage } from "../lib/loyalty-ledger-client";

describe("loyalty-ledger-client", () => {
  it("nhãn loại tiếng Việt", () => {
    expect(ledgerKindLabel("earn")).toBe("Tích điểm");
    expect(ledgerKindLabel("opening")).toBe("Số dư đầu kỳ");
    expect(ledgerKindLabel("zzz")).toBe("zzz");
  });

  it("parseLedgerPage chịu dữ liệu thiếu", () => {
    const p = parseLedgerPage({ entries: [null, { opId: "a", points: 5, at: 1, type: "earn" }], totals: { earned: 5, count: 1 }, nextCursor: "" });
    expect(p.entries).toHaveLength(1);
    expect(p.entries[0].memberName).toBe("");
    expect(p.totals).toEqual({ earned: 5, redeemed: 0, manual: 0, count: 1 });
    expect(p.nextCursor).toBeUndefined();
    expect(parseLedgerPage(null).entries).toEqual([]);
  });

  it("thông báo lỗi lấy message của máy chủ", () => {
    expect(ledgerErrorMessage({ code: "functions/permission-denied", message: "Chỉ Quản lý/Chủ quán được chỉnh điểm." })).toContain("Quản lý");
    expect(ledgerErrorMessage({ code: "functions/permission-denied", message: "internal" })).toContain("Quản lý/Chủ");
    expect(ledgerErrorMessage(null)).toContain("thử lại");
  });

  it("khoảng ngày", () => {
    expect(dayStartMs("")).toBeUndefined();
    expect(dayEndMs("2026-01-02")! - dayStartMs("2026-01-02")!).toBe(86_399_999);
  });

  it("CSV có chi nhánh, BOM và escape dấu nháy", () => {
    const csv = buildLedgerCsv(
      [{ opId: "o", memberKey: "m", memberName: 'An "Bo"', memberPhone: "0912", type: "redeem", points: -10, balanceAfter: 5, billId: "b", billCode: "HD1", storeCode: "TRAM01", customerId: "", staff: "q", note: "", at: 1 }],
      () => "T"
    );
    const [head, line] = csv.replace("﻿", "").split("\n");
    expect(csv.startsWith("﻿")).toBe(true);
    expect(head).toContain('"Chi nhánh"');
    expect(line).toBe('"T","TRAM01","An ""Bo""","0912","Đổi điểm","-10","5","HD1","","q"'.replace('"-10","5"', '"-10","5"'));
  });
});

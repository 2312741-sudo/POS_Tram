import { describe, it, expect } from "vitest";
import {
  buildVoucherCancelUpdate,
  buildVoucherCreateUpdates,
  canCancelVoucher,
  checkVoucher,
  filterVouchers,
  generateRandomCodes,
  parseVoucherCodes,
  toVoucherView,
  voucherStats,
  voucherStatusText,
} from "../lib/campaign-vouchers";

const NOW = 1_800_000_000_000;

describe("parseVoucherCodes", () => {
  it("splits by newline/comma, uppercases, dedupes, rejects existing & invalid", () => {
    const r = parseVoucherCodes(" chaoban20\nGIAM10K, giam10k ;TRAMVIP\n\nOLD1\nbad.code\nmã", ["old1"]);
    expect(r.codes).toEqual(["CHAOBAN20", "GIAM10K", "TRAMVIP"]);
    expect(r.duplicateInInput).toEqual(["GIAM10K"]);
    expect(r.existing).toEqual(["OLD1"]);
    expect(r.invalid).toEqual(["BAD.CODE", "MÃ"]);
  });
  it("empty input", () => {
    expect(parseVoucherCodes("  \n , ").codes).toEqual([]);
  });
});

describe("generateRandomCodes", () => {
  it("produces unique prefixed codes avoiding existing", () => {
    let i = 0;
    const seq = [0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9];
    const rng = () => seq[i++ % seq.length];
    const codes = generateRandomCodes(2, "tram", ["TRAMAAAAAA"], rng);
    expect(codes).toHaveLength(2);
    expect(codes.every((c) => c.startsWith("TRAM") && c.length === 10)).toBe(true);
    expect(codes).not.toContain("TRAMAAAAAA");
    expect(new Set(codes).size).toBe(2);
  });
});

describe("toVoucherView / status", () => {
  it("maps Flutter voucher incl. bill code fallback", () => {
    const v = toVoucherView("V1", "C1", { normalizedCode: "abc", state: "REDEEMED", redeemedBillId: "BILL_1", redeemedBy: "thu ngân", redeemedAt: NOW, tableName: "Bàn 5" });
    expect(v).toMatchObject({ code: "ABC", state: "REDEEMED", billRef: "BILL_1", redeemedBy: "thu ngân", tableName: "Bàn 5" });
    expect(toVoucherView("V1", "C1", { code: "X", state: "REDEEMED", redeemedBillId: "BILL_1", redeemedBillCode: "HD0001" }).billRef).toBe("HD0001");
    expect(toVoucherView("V1", "C1", { code: "X", state: "REDEEMED", redeemedBy: "lan01", redeemedByName: "Nguyễn Lan" }).redeemedBy).toBe("Nguyễn Lan");
  });
  it("falls back from legacy status field", () => {
    expect(toVoucherView("V", "C", { code: "A", status: "USED", usedBy: "u", usedAt: 5 })).toMatchObject({ state: "REDEEMED", redeemedBy: "u", redeemedAt: 5 });
    expect(toVoucherView("V", "C", { code: "A", status: "ISSUED" }).state).toBe("RELEASED");
  });
  it("status text & cancellable", () => {
    expect(voucherStatusText({ state: "RELEASED" }, NOW)).toBe("Chưa dùng");
    expect(voucherStatusText({ state: "REDEEMED" }, NOW)).toBe("Đã dùng");
    expect(voucherStatusText({ state: "CANCELLED" }, NOW)).toBe("Đã hủy");
    expect(voucherStatusText({ state: "RESERVED", holdExpiresAt: NOW + 1000 }, NOW)).toBe("Đang giữ chỗ");
    expect(voucherStatusText({ state: "RESERVED", holdExpiresAt: NOW - 1000 }, NOW)).toBe("Chưa dùng");
    expect(canCancelVoucher({ state: "RELEASED" }, NOW)).toBe(true);
    expect(canCancelVoucher({ state: "REDEEMED" }, NOW)).toBe(false);
    expect(canCancelVoucher({ state: "CANCELLED" }, NOW)).toBe(false);
    expect(canCancelVoucher({ state: "RESERVED", holdExpiresAt: NOW + 1000 }, NOW)).toBe(false);
  });
  it("stats and search", () => {
    const list = [
      toVoucherView("1", "C", { code: "AAA1", state: "RELEASED" }),
      toVoucherView("2", "C", { code: "BBB2", state: "REDEEMED", redeemedBillCode: "HD77" }),
      toVoucherView("3", "C", { code: "CCC3", state: "CANCELLED" }),
    ];
    expect(voucherStats(list)).toEqual({ total: 3, unused: 1, used: 1, cancelled: 1 });
    expect(filterVouchers(list, "bbb").map((v) => v.code)).toEqual(["BBB2"]);
    expect(filterVouchers(list, "hd77").map((v) => v.code)).toEqual(["BBB2"]);
    expect(filterVouchers(list, "")).toHaveLength(3);
  });
});

describe("writes", () => {
  it("create updates match Flutter VoucherModel + lookup", () => {
    const u = buildVoucherCreateUpdates("C1", ["AAA", "BBB"], NOW, (i) => `V${i}`);
    expect(u["vouchers/C1/V0"]).toMatchObject({ voucherId: "V0", campaignId: "C1", code: "AAA", normalizedCode: "AAA", state: "RELEASED", status: "ISSUED", tombstone: false, createdAt: NOW, version: 1 });
    expect(u["voucher_lookup/BBB"]).toEqual({ campaignId: "C1", voucherId: "V1" });
    expect(u["campaigns/C1/hasCodes"]).toBe(true);
    expect(buildVoucherCreateUpdates("C1", [], NOW, () => "x")).toEqual({});
  });
  it("cancel sets state (POS reads state) and status", () => {
    expect(buildVoucherCancelUpdate(NOW)).toEqual({ state: "CANCELLED", status: "CANCELLED", cancelledAt: NOW });
  });
});

describe("checkVoucher", () => {
  const cam = { name: "Giờ vàng", programCode: "KM0001", active: true, schedule: {} };
  const released = toVoucherView("V", "C", { code: "ABC", state: "RELEASED" });
  it("invalid / not found / valid", () => {
    expect(checkVoucher("a.b", null, null, NOW).kind).toBe("INVALID_FORMAT");
    const nf = checkVoucher("xyz1", null, null, NOW);
    expect(nf.kind).toBe("NOT_FOUND");
    expect(nf.message).toBe("Mã XYZ1 không tồn tại");
    const ok = checkVoucher("abc", released, cam, NOW);
    expect(ok.ok).toBe(true);
    expect(ok.message).toMatch(/hợp lệ/);
  });
  it("used shows bill, table, staff", () => {
    const used = toVoucherView("V", "C", { code: "ABC", state: "REDEEMED", redeemedBillCode: "HD0012", tableName: "Bàn 3", redeemedBy: "lan", redeemedAt: NOW });
    const r = checkVoucher("ABC", used, cam, NOW);
    expect(r.kind).toBe("USED");
    expect(r.message).toMatch(/đã sử dụng ở đơn HD0012, bàn Bàn 3, lúc .+, bởi lan/);
  });
  it("cancelled / expired / not started / paused", () => {
    expect(checkVoucher("ABC", toVoucherView("V", "C", { code: "ABC", state: "CANCELLED" }), cam, NOW).message).toMatch(/đã hủy/);
    expect(checkVoucher("ABC", released, { ...cam, schedule: { absoluteEnd: NOW - 1 } }, NOW).kind).toBe("CAMPAIGN_EXPIRED");
    expect(checkVoucher("ABC", released, { ...cam, schedule: { absoluteEnd: NOW - 1 } }, NOW).message).toMatch(/hết hạn/);
    expect(checkVoucher("ABC", released, { ...cam, schedule: { absoluteStart: NOW + 1 } }, NOW).kind).toBe("CAMPAIGN_NOT_STARTED");
    expect(checkVoucher("ABC", released, { ...cam, active: false }, NOW).kind).toBe("CAMPAIGN_PAUSED");
    expect(checkVoucher("ABC", released, null, NOW).kind).toBe("CAMPAIGN_MISSING");
  });
});

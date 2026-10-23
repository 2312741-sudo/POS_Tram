import { describe, it, expect, beforeEach } from "vitest";
import { businessDateOf, businessDayRange, businessDayStartFor, businessTimestamp, formatMinutesAsTime, normalizeBusinessDayStart, parseTimeToMinutes, setBusinessDayConfig } from "../lib/business-day";

const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);

describe("ngày kinh doanh", () => {
  it("mặc định 00:00: 01:30 sáng thuộc ngày mới", () => {
    expect(businessDateOf(vn(2026, 10, 23, 1, 30), 0)).toBe("2026-10-23");
  });
  it("mốc 04:00: 01:30 sáng 23/10 vẫn là ngày 22/10; 04:00 trở đi là 23/10", () => {
    expect(businessDateOf(vn(2026, 10, 23, 1, 30), 240)).toBe("2026-10-22");
    expect(businessDateOf(vn(2026, 10, 23, 3, 59), 240)).toBe("2026-10-22");
    expect(businessDateOf(vn(2026, 10, 23, 4, 0), 240)).toBe("2026-10-23");
    expect(businessDateOf(vn(2026, 10, 22, 23, 0), 240)).toBe("2026-10-22");
  });
  it("khoảng của ngày kinh doanh 22/10 với mốc 04:00 = 22/10 04:00 → 23/10 04:00", () => {
    const r = businessDayRange("2026-10-22", 240);
    expect(r.start).toBe(vn(2026, 10, 22, 4));
    expect(r.end).toBe(vn(2026, 10, 23, 4));
  });
  it("businessTimestamp lùi đúng số phút", () => {
    expect(businessTimestamp(vn(2026, 10, 23, 1, 0), 120)).toBe(vn(2026, 10, 22, 23, 0));
  });
  it("chuẩn hóa & định dạng", () => {
    expect(normalizeBusinessDayStart("abc")).toBe(0);
    expect(normalizeBusinessDayStart(-5)).toBe(0);
    expect(normalizeBusinessDayStart(99999)).toBe(720);
    expect(normalizeBusinessDayStart(240.7)).toBe(240);
    expect(parseTimeToMinutes("04:30")).toBe(270);
    expect(parseTimeToMinutes("24:00")).toBeNull();
    expect(parseTimeToMinutes("")).toBeNull();
    expect(formatMinutesAsTime(270)).toBe("04:30");
  });
  describe("cấu hình theo cửa hàng", () => {
    beforeEach(() => setBusinessDayConfig({ A: 180, B: 0 }, 180));
    it("tra theo cửa hàng, ALL/không rõ dùng mặc định", () => {
      expect(businessDayStartFor("A")).toBe(180);
      expect(businessDayStartFor("B")).toBe(0);
      expect(businessDayStartFor("ALL")).toBe(180);
      expect(businessDayStartFor(undefined)).toBe(180);
      expect(businessDayStartFor("C")).toBe(180);
    });
  });
});

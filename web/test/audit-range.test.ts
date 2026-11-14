import { describe, it, expect } from "vitest";
import { auditRange } from "../lib/audit-range";

// 14/11/2026 01:16 giờ VN = 13/11 18:16 UTC
const now = Date.UTC(2026, 10, 13, 18, 16);
const vn = (y: number, m: number, d: number, h = 0) => Date.UTC(y, m - 1, d, h) - 7 * 3600_000;

describe("Khoảng ngày nhật ký thao tác (giờ VN)", () => {
  it("hôm nay / hôm qua theo giờ Việt Nam", () => {
    expect(auditRange("TODAY", now)).toEqual({ from: vn(2026, 11, 14), to: vn(2026, 11, 15) - 1 });
    expect(auditRange("YESTERDAY", now)).toEqual({ from: vn(2026, 11, 13), to: vn(2026, 11, 14) - 1 });
  });
  it("tháng này từ ngày 1, tháng trước trọn tháng", () => {
    expect(auditRange("THIS_MONTH", now)!.from).toBe(vn(2026, 11, 1));
    expect(auditRange("LAST_MONTH", now)).toEqual({ from: vn(2026, 10, 1), to: vn(2026, 11, 1) - 1 });
  });
  it("tùy chọn; sai thứ tự / trống → null; chế độ gần nhất → null", () => {
    expect(auditRange("CUSTOM", now, "2026-11-01", "2026-11-03")).toEqual({ from: vn(2026, 11, 1), to: vn(2026, 11, 4) - 1 });
    expect(auditRange("CUSTOM", now, "2026-11-05", "2026-11-03")).toBeNull();
    expect(auditRange("CUSTOM", now)).toBeNull();
    expect(auditRange("RECENT", now)).toBeNull();
  });
});

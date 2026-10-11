import { describe, it, expect } from "vitest";
import { resolveStaffUid } from "../lib/staff-key";

describe("resolveStaffUid", () => {
  it("ưu tiên trường uid trong hồ sơ (nút khóa theo uid)", () => {
    expect(resolveStaffUid("RI8JGsSpmXTjo8OkXzdon6oWfCk1", { uid: "RI8JGsSpmXTjo8OkXzdon6oWfCk1" })).toBe("RI8JGsSpmXTjo8OkXzdon6oWfCk1");
  });
  it("nút cũ khóa theo tên đăng nhập không có uid -> dùng khóa nút", () => {
    expect(resolveStaffUid("ta", { uid: undefined })).toBe("ta");
    expect(resolveStaffUid("ti", {})).toBe("ti");
    expect(resolveStaffUid("v", null)).toBe("v");
  });
  it("bỏ qua uid rỗng hoặc sai kiểu", () => {
    expect(resolveStaffUid("abc", { uid: "  " })).toBe("abc");
    expect(resolveStaffUid("abc", { uid: 123 })).toBe("abc");
  });
  it("hồ sơ legacy khóa theo username nhưng có uid thật -> trả uid thật", () => {
    expect(resolveStaffUid("admin", { uid: "Lz5QAU2YC7PicahgI2THLsTDfG62" })).toBe("Lz5QAU2YC7PicahgI2THLsTDfG62");
  });
});

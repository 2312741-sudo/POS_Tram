import { describe, it, expect } from "vitest";
import { kvBirthday, kvGender, kvPhone, parseKvSheet, planKvImport } from "../lib/kiotviet-customers";

// Dữ liệu GIẢ theo đúng mẫu file "DanhSachKhachHang_KV...xlsx" của KiotViet (dòng 2 là dòng tổng cộng)
const HEADER = ["Loại khách", "Chi nhánh", "Mã khách hàng", "Tên khách hàng", "Điện thoại", "Địa chỉ", "Ngày sinh", "Giới tính", "Điểm hiện tại", "Tổng điểm", "Trạng thái"];
const sheetA = [
  HEADER,
  ["Cá nhân", null, null, null, null, null, null, null, 120, 150, 0],
  ["Cá nhân", null, "KH000001", "nguyễn văn a", "0912345678", null, new Date("2000-12-21T00:00:00+07:00"), "Nam", 77, 90, 1],
  ["Cá nhân", null, "KH000002", "Trần Thị B", "0912 000 002", null, "03/01/2006", "Nữ", null, 0, 1],
  ["Cá nhân", null, "KH000003", "Lê C", "091234567", null, null, null, 5, 5, 1],
  ["Cá nhân", null, "KH000004", "Phạm D", "01652223333", null, null, "Nam", 3, 3, 1],
];
const sheetB = [
  HEADER,
  ["Cá nhân", null, null, null, null, null, null, null, 0, 0, 0],
  ["Cá nhân", null, "KH000009", "Nguyễn Văn A", "+84912345678", null, null, "Nam", 100, 100, 1],
  ["Cá nhân", null, "KH000010", "Võ E", "0987654321", null, 36526, "Khác", 8, 8, 1],
];

describe("Nhập khách hàng từ Excel KiotViet", () => {
  it("chuẩn hóa SĐT: khoảng trắng, +84, mất số 0, đầu số 11 số cũ", () => {
    expect(kvPhone("0912 000 002")).toBe("0912000002");
    expect(kvPhone("+84912345678")).toBe("0912345678");
    expect(kvPhone("912345678")).toBe("0912345678");
    expect(kvPhone("01652223333")).toBe("0352223333");
    expect(kvPhone("091234567")).toBeNull();
    expect(kvPhone(null)).toBeNull();
  });

  it("ngày sinh / giới tính", () => {
    expect(kvBirthday(new Date("2000-12-21T00:00:00+07:00"))).toBe("2000-12-21");
    expect(kvBirthday("03/01/2006")).toBe("2006-01-03");
    expect(kvBirthday("2006-01-03T00:00:00")).toBe("2006-01-03");
    expect(kvBirthday(36526)).toBe("2000-01-01");
    expect(kvBirthday(null)).toBe("");
    expect([kvGender("Nam"), kvGender("Nữ"), kvGender(""), kvGender("Khác")]).toEqual(["Nam", "Nữ", "Khác", "Khác"]);
  });

  it("bỏ dòng tổng cộng, báo dòng SĐT sai, tên viết hoa, điểm hiện tại", () => {
    const a = parseKvSheet(sheetA, "a.xlsx");
    expect(a.customers.map((c) => [c.name, c.phone, c.points])).toEqual([
      ["NGUYỄN VĂN A", "0912345678", 77],
      ["TRẦN THỊ B", "0912000002", 0],
      ["PHẠM D", "0352223333", 3],
    ]);
    expect(a.invalid).toEqual([{ file: "a.xlsx", row: 5, name: "Lê C", reason: "SĐT không hợp lệ (091234567)" }]);
  });

  it("gộp nhiều file: trùng SĐT giữ dòng điểm cao hơn; SĐT đã có trong POS → bỏ qua", () => {
    const plan = planKvImport([parseKvSheet(sheetA, "a"), parseKvSheet(sheetB, "b")], ["0987 654 321"]);
    expect(plan.toCreate.map((c) => [c.phone, c.points])).toEqual([
      ["0912345678", 100],
      ["0912000002", 0],
      ["0352223333", 3],
    ]);
    expect(plan.duplicates.map((c) => c.points)).toEqual([77]);
    expect(plan.existing.map((c) => c.phone)).toEqual(["0987654321"]);
    expect(plan.invalid).toHaveLength(1);
  });

  it("file không phải danh sách khách hàng", () => {
    expect(parseKvSheet([["Mã hàng", "Tên hàng"]], "x").invalid[0].reason).toContain("Tên khách hàng");
  });
});

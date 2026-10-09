import { describe, it, expect } from "vitest";
import { canEditPointConfig, canReadCustomers, parseStoreCustomers, tierForPoints } from "../lib/customers";

describe("parseStoreCustomers", () => {
  it("đọc trường giống app POS (snake_case ưu tiên, fallback camelCase)", () => {
    const list = parseStoreCustomers("TRAM01", {
      c1: { ma_khach_hang: "KH1", ho_ten: "An", so_dien_thoai: "0901", diem_hien_tai: 250, currentPoints: 1, totalPoints: 300, ngay_tao: 1_700_000_000_000 },
      c2: { name: "Bình", phone: "0902", currentPoints: 10 },
      bad: "x",
    });
    expect(list).toHaveLength(2);
    const [a, b] = list;
    expect(a).toMatchObject({ id: "c1", storeCode: "TRAM01", maKhachHang: "KH1", hoTen: "An", soDienThoai: "0901", diemHienTai: 250, tongDiem: 300, hangThanhVien: "Vàng", createdAt: 1_700_000_000_000 });
    expect(b).toMatchObject({ id: "c2", maKhachHang: "c2", hoTen: "Bình", soDienThoai: "0902", diemHienTai: 10, tongDiem: 10, hangThanhVien: "Thành viên" });
  });

  it("nút rỗng / không hợp lệ trả về mảng rỗng", () => {
    expect(parseStoreCustomers("TRAM01", null)).toEqual([]);
    expect(parseStoreCustomers("TRAM01", 5)).toEqual([]);
  });

  it("hạng theo điểm", () => {
    expect(tierForPoints(0)).toBe("Thành viên");
    expect(tierForPoints(50)).toBe("Bạc");
    expect(tierForPoints(200)).toBe("Vàng");
    expect(tierForPoints(500)).toBe("Kim Cương");
  });
});

describe("quyền khách hàng (khớp database.rules.json)", () => {
  it("đọc: Chủ quán / Quản lý / Thu ngân; Phục vụ, Bếp bị chặn", () => {
    for (const r of ["owner", "ROLE_OWNER", "manager", "manager_2", "ROLE_MANAGER_1", "cashier", "ROLE_CASHIER", "employee"]) {
      expect(canReadCustomers(r)).toBe(true);
    }
    for (const r of ["waiter", "ROLE_WAITER", "ROLE_KITCHEN", ""]) expect(canReadCustomers(r)).toBe(false);
    expect(canReadCustomers("waiter", true)).toBe(true);
  });

  it("sửa tỷ lệ điểm (storeInfo): chỉ Chủ quán", () => {
    expect(canEditPointConfig("owner")).toBe(true);
    expect(canEditPointConfig("manager")).toBe(false);
    expect(canEditPointConfig("manager", true)).toBe(true);
  });
});

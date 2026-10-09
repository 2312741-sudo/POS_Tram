import { describe, it, expect } from "vitest";
import { canCallerImportCustomer, isCashierRole } from "./permissions";
import {
  isValidCustomerKey,
  isValidStoreCode,
  buildRtdbCustomerFromFirestore,
  decideImport,
  buildFirestoreMirror,
  shouldMirror,
  buildPointHistoryEntry,
  readCurrentPoints,
} from "./customerSync";

describe("importCustomerToStore - quyền gọi", () => {
  const owner = { username: "admin", roleId: "owner", isRootOwner: true, isActive: true };
  const manager = { username: "ql1", roleId: "manager_1", isActive: true };
  const cashier = { username: "thungan", roleId: "cashier", isActive: true };
  const legacyCashier = { username: "nv", roleId: "ROLE_CASHIER", isActive: true };
  const waiter = { username: "phucvu", roleId: "waiter", isActive: true };
  const kitchen = { username: "bep", roleId: "kitchen", isActive: true };
  const lockedCashier = { username: "tn_khoa", roleId: "cashier", isActive: false };

  it("1. Thu ngân trở lên, đang hoạt động, thuộc quán mới được nhập khách", () => {
    expect(canCallerImportCustomer(owner, true)).toBe(true);
    expect(canCallerImportCustomer(manager, true)).toBe(true);
    expect(canCallerImportCustomer(cashier, true)).toBe(true);
    expect(canCallerImportCustomer(legacyCashier, true)).toBe(true);
    expect(isCashierRole("employee")).toBe(true);
  });

  it("2. Phục vụ, bếp, tài khoản bị khóa, không thuộc quán bị từ chối", () => {
    expect(canCallerImportCustomer(waiter, true)).toBe(false);
    expect(canCallerImportCustomer(kitchen, true)).toBe(false);
    expect(canCallerImportCustomer(lockedCashier, true)).toBe(false);
    expect(canCallerImportCustomer(cashier, false)).toBe(false); // không có userIndex
    expect(canCallerImportCustomer(null, true)).toBe(false);
  });

  it("3. Kiểm tra mã quán / mã khách", () => {
    expect(isValidStoreCode("TRAM01")).toBe(true);
    expect(isValidStoreCode("x")).toBe(false);
    expect(isValidStoreCode(42)).toBe(false);
    expect(isValidCustomerKey("KH000001")).toBe(true);
    expect(isValidCustomerKey("CUST_1700000000000")).toBe(true);
    for (const bad of ["", " KH1", "a/b", "a.b", "a#b", "a$b", "a[b]", "__x__", null, 12]) {
      expect(isValidCustomerKey(bad)).toBe(false);
    }
  });
});

describe("importCustomerToStore - chuẩn hóa & idempotent", () => {
  const fsDoc = { ma_khach_hang: "KH000001", ho_ten: "Nguyễn Văn A", so_dien_thoai: "0900000001", diem_hien_tai: 120, tongDiem: 300, ngay_tao: 1700000000000 };

  it("4. Chép số dư thật từ Firestore, trường giống KmtCustomerModel.toMap", () => {
    const v = buildRtdbCustomerFromFirestore(fsDoc, "KH000001", 1800000000000);
    expect(v.id).toBe("KH000001");
    expect(v.code).toBe("KH000001");
    expect(v.diem_hien_tai).toBe(120);
    expect(v.currentPoints).toBe(120);
    expect(v.totalPoints).toBe(300);
    expect(v.ho_ten_upper).toBe("NGUYỄN VĂN A");
    expect(v.createdAt).toBe(1700000000000);
    expect(v.importedFrom).toBe("kmt_customers");
    expect(v).not.toHaveProperty("loyaltyOps");
    expect(v).not.toHaveProperty("lastLoyaltyOp");
  });

  it("5. Điểm âm / thiếu / sai kiểu → 0; tổng điểm không nhỏ hơn điểm hiện tại", () => {
    expect(buildRtdbCustomerFromFirestore({ diem_hien_tai: -5 }, "K", 1).currentPoints).toBe(0);
    expect(buildRtdbCustomerFromFirestore({ diem_hien_tai: "999" }, "K", 1).currentPoints).toBe(0);
    expect(buildRtdbCustomerFromFirestore({ currentPoints: 40, totalPoints: 10 }, "K", 1).totalPoints).toBe(40);
  });

  it("6. Đã có node RTDB → không ghi đè (gọi lại nhiều lần an toàn)", () => {
    const seed = buildRtdbCustomerFromFirestore(fsDoc, "KH000001", 1);
    expect(decideImport(null, seed)).toEqual({ action: "create", value: seed });
    expect(decideImport(undefined, seed).action).toBe("create");
    expect(decideImport({ currentPoints: 5 }, seed)).toEqual({ action: "exists" });
    expect(decideImport({ currentPoints: 0 }, seed)).toEqual({ action: "exists" });
  });
});

describe("mirrorCustomerToFirestore - RTDB là nguồn chuẩn", () => {
  const before = { id: "KH1", code: "KH1", ho_ten: "A", diem_hien_tai: 50, currentPoints: 50, totalPoints: 80 };

  it("7. Bản sao Firestore lấy điểm từ RTDB, không mang theo loyaltyOps", () => {
    const after = { ...before, diem_hien_tai: 70, currentPoints: 70, totalPoints: 100, loyaltyOps: { "b1:award": 1 } };
    const m = buildFirestoreMirror(after, "TRAM01", 9);
    expect(m.diem_hien_tai).toBe(70);
    expect(m.currentPoints).toBe(70);
    expect(m.totalPoints).toBe(100);
    expect(m).not.toHaveProperty("loyaltyOps");
    expect(m.pointsSource).toBe("rtdb:stores/TRAM01/customers");
  });

  it("8. Chỉ đồng bộ khi điểm / thông tin đổi", () => {
    expect(shouldMirror(null, before)).toBe(true);
    expect(shouldMirror(before, null)).toBe(false);
    expect(shouldMirror(before, { ...before, ngay_cap_nhat: 123, loyaltyOps: {} })).toBe(false);
    expect(shouldMirror(before, { ...before, currentPoints: 60, diem_hien_tai: 60 })).toBe(true);
    expect(shouldMirror(before, { ...before, ho_ten: "B" })).toBe(true);
  });

  it("9. Lịch sử điểm có doc id cố định theo thao tác hóa đơn", () => {
    const after = { ...before, diem_hien_tai: 70, currentPoints: 70, lastLoyaltyOp: "b1:award", lastLoyaltyBillId: "b1", lastLoyaltyType: "award" };
    const h1 = buildPointHistoryEntry(before, after, "TRAM01", "KH1", "evt-1");
    const h2 = buildPointHistoryEntry(before, after, "TRAM01", "KH1", "evt-2");
    expect(h1?.docId).toBe("POS_TRAM01_KH1_b1:award");
    expect(h2?.docId).toBe(h1?.docId);
    expect(h1?.data).toMatchObject({ diem_truoc: 50, diem_thay_doi: 20, diem_sau: 70, nguon: "fnb_pos", bill_code: "b1" });

    const redeem = { ...before, diem_hien_tai: 30, currentPoints: 30, lastLoyaltyOp: "b2:redeem", lastLoyaltyBillId: "b2", lastLoyaltyType: "redeem" };
    expect(buildPointHistoryEntry(before, redeem, "TRAM01", "KH1", "e")?.data).toMatchObject({ diem_thay_doi: -20, nguon: "fnb_pos_redeem" });
  });

  it("10. Quản lý chỉnh tay → nguồn fnb_pos_adjust; không đổi điểm / tạo mới → không ghi lịch sử", () => {
    const adj = buildPointHistoryEntry(before, { ...before, diem_hien_tai: 10, currentPoints: 10 }, "TRAM01", "KH1", "evt-9");
    expect(adj?.docId).toBe("POS_EVT_evt-9");
    expect(adj?.data.nguon).toBe("fnb_pos_adjust");
    expect(buildPointHistoryEntry(before, { ...before, ho_ten: "B" }, "TRAM01", "KH1", "e")).toBeNull();
    expect(buildPointHistoryEntry(null, before, "TRAM01", "KH1", "e")).toBeNull();
    expect(readCurrentPoints({ diemHienTai: 7 })).toBe(7);
  });
});

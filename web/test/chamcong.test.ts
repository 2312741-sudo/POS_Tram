import { describe, it, expect } from "vitest";
import {
  hasChamCongConfig,
  parseChamCongSignInResponse,
  parseLinkChamCongResponse,
  parseChamCongLinkStatus,
  mapChamCongError,
  chamCongNotAdminMessage,
  roleLabelVi,
} from "../lib/chamcong";

describe("hasChamCongConfig", () => {
  it("cần đủ 4 biến không rỗng", () => {
    expect(hasChamCongConfig({ apiKey: "k", authDomain: "d", projectId: "p", appId: "a" })).toBe(true);
    expect(hasChamCongConfig({ apiKey: "k", authDomain: "d", projectId: "p", appId: "" })).toBe(false);
    expect(hasChamCongConfig({ apiKey: " ", authDomain: "d", projectId: "p", appId: "a" })).toBe(false);
    expect(hasChamCongConfig({})).toBe(false);
  });
});

describe("parseChamCongSignInResponse", () => {
  it("phân tích OK và chuẩn hóa storeCode", () => {
    const r = parseChamCongSignInResponse({
      status: "OK",
      customToken: "tok",
      storeCode: "tram01",
      uid: "u1",
      roleId: "ROLE_WAITER",
      isNewAccount: true,
    });
    expect(r).toEqual({
      status: "OK",
      customToken: "tok",
      storeCode: "TRAM01",
      uid: "u1",
      roleId: "ROLE_WAITER",
      isNewAccount: true,
    });
  });

  it("OK thiếu token hoặc storeCode → null", () => {
    expect(parseChamCongSignInResponse({ status: "OK", storeCode: "TRAM01" })).toBeNull();
    expect(parseChamCongSignInResponse({ status: "OK", customToken: "t" })).toBeNull();
  });

  it("roleId mặc định ROLE_WAITER, isNewAccount mặc định false", () => {
    const r = parseChamCongSignInResponse({ status: "OK", customToken: "t", storeCode: "A" });
    expect(r && r.status === "OK" && r.roleId).toBe("ROLE_WAITER");
    expect(r && r.status === "OK" && r.isNewAccount).toBe(false);
  });

  it("CHOOSE_STORE lọc mục không hợp lệ và dùng mã làm tên dự phòng", () => {
    const r = parseChamCongSignInResponse({
      status: "CHOOSE_STORE",
      stores: [{ storeCode: "tram01", storeName: "Trạm Q1" }, { storeCode: "TRAM02" }, { storeName: "x" }, null],
    });
    expect(r).toEqual({
      status: "CHOOSE_STORE",
      stores: [
        { storeCode: "TRAM01", storeName: "Trạm Q1" },
        { storeCode: "TRAM02", storeName: "TRAM02" },
      ],
    });
  });

  it("CHOOSE_STORE rỗng hoặc dữ liệu rác → null", () => {
    expect(parseChamCongSignInResponse({ status: "CHOOSE_STORE", stores: [] })).toBeNull();
    expect(parseChamCongSignInResponse(null)).toBeNull();
    expect(parseChamCongSignInResponse("OK")).toBeNull();
    expect(parseChamCongSignInResponse({ status: "WHAT" })).toBeNull();
  });
});

describe("parseLinkChamCongResponse", () => {
  it("LINKED", () => {
    expect(parseLinkChamCongResponse({ status: "LINKED", chamCongStoreId: "s1", chamCongStoreName: "Trạm" })).toEqual({
      status: "LINKED",
      chamCongStoreId: "s1",
      chamCongStoreName: "Trạm",
    });
    expect(parseLinkChamCongResponse({ status: "LINKED" })).toBeNull();
  });

  it("CHOOSE_CHAMCONG_STORE", () => {
    expect(
      parseLinkChamCongResponse({
        status: "CHOOSE_CHAMCONG_STORE",
        stores: [{ chamCongStoreId: "a", name: "A", code: "C1" }, { name: "no id" }, { chamCongStoreId: "b" }],
      })
    ).toEqual({
      status: "CHOOSE_CHAMCONG_STORE",
      stores: [
        { chamCongStoreId: "a", name: "A", code: "C1" },
        { chamCongStoreId: "b", name: "b", code: "" },
      ],
    });
  });
});

describe("parseChamCongLinkStatus", () => {
  it("mặc định chưa liên kết", () => {
    expect(parseChamCongLinkStatus(undefined)).toEqual({ linked: false, provisionedCount: 0 });
  });

  it("đọc đủ trường, chấp nhận linkedAt dạng số hoặc ISO", () => {
    expect(
      parseChamCongLinkStatus({ linked: true, chamCongStoreId: "s1", chamCongStoreName: "Trạm", linkedAt: 1000, provisionedCount: 3 })
    ).toEqual({ linked: true, chamCongStoreId: "s1", chamCongStoreName: "Trạm", linkedAt: 1000, provisionedCount: 3 });
    const iso = parseChamCongLinkStatus({ linked: true, linkedAt: "2026-01-01T00:00:00Z", provisionedCount: "2" });
    expect(iso.linkedAt).toBe(Date.parse("2026-01-01T00:00:00Z"));
    expect(iso.provisionedCount).toBe(2);
  });

  it("provisionedCount không hợp lệ → 0", () => {
    expect(parseChamCongLinkStatus({ linked: false, provisionedCount: -4 }).provisionedCount).toBe(0);
    expect(parseChamCongLinkStatus({ linked: false, provisionedCount: "abc" }).provisionedCount).toBe(0);
  });
});

describe("mapChamCongError", () => {
  it("ưu tiên details.code từ máy chủ", () => {
    expect(mapChamCongError({ code: "functions/failed-precondition", message: "x", details: { code: "NOT_LINKED" } })).toBe(
      "Cửa hàng chấm công của bạn chưa được liên kết với POS. Nhờ chủ quán liên kết trong Cài đặt."
    );
    expect(mapChamCongError({ code: "functions/unauthenticated", details: { code: "INVALID_TOKEN" } })).toContain("không hợp lệ");
    expect(mapChamCongError({ code: "functions/permission-denied", details: { code: "NOT_ACTIVE_MEMBER" } })).toContain(
      "nhân viên đang hoạt động"
    );
    expect(mapChamCongError({ code: "functions/permission-denied", details: { code: "POS_ACCOUNT_DISABLED" } })).toContain("tạm khóa");
    expect(mapChamCongError({ code: "functions/already-exists", details: { code: "ALREADY_LINKED" } })).toContain("đã được liên kết");
  });

  it("lỗi popup", () => {
    expect(mapChamCongError({ code: "auth/popup-blocked" })).toContain("chặn cửa sổ");
    expect(mapChamCongError({ code: "auth/popup-closed-by-user" })).toContain("đã đóng");
    expect(mapChamCongError({ code: "auth/cancelled-popup-request" })).toContain("đã đóng");
  });

  it("unauthorized-domain nêu tên miền và chamcongtram Authorized domains", () => {
    const msg = mapChamCongError({ code: "auth/unauthorized-domain" }, "pos.example.com");
    expect(msg).toContain("pos.example.com");
    expect(msg).toContain("chamcongtram");
    expect(msg).toContain("Authorized domains");
  });

  it("sai email/mật khẩu & mạng", () => {
    expect(mapChamCongError({ code: "auth/invalid-credential" })).toContain("không đúng");
    expect(mapChamCongError({ code: "auth/network-request-failed" })).toContain("kết nối");
  });

  it("không rò rỉ thông báo lạ ở nhánh mặc định", () => {
    expect(mapChamCongError(new Error("internal stack"))).toBe("Không thể đăng nhập bằng Chấm Công Trạm. Vui lòng thử lại sau.");
    expect(mapChamCongError(null)).toBe("Không thể đăng nhập bằng Chấm Công Trạm. Vui lòng thử lại sau.");
  });
});

describe("Vai trò", () => {
  it("roleLabelVi", () => {
    expect(roleLabelVi("ROLE_WAITER")).toBe("Phục vụ");
    expect(roleLabelVi("role_cashier")).toBe("Thu ngân");
    expect(roleLabelVi("CUSTOM")).toBe("CUSTOM");
  });

  it("chamCongNotAdminMessage phân biệt tài khoản mới", () => {
    expect(chamCongNotAdminMessage("ROLE_WAITER", true)).toContain("Đã tạo tài khoản POS cho bạn với vai trò Phục vụ");
    expect(chamCongNotAdminMessage("ROLE_CASHIER", false)).toContain("đang ở vai trò Thu ngân");
    expect(chamCongNotAdminMessage("ROLE_WAITER", false)).toContain("Nhân viên");
  });
});

describe("mapChamCongError — mã lỗi bổ sung của máy chủ", () => {
  it("POS_ACCOUNT_CONFLICT, NOT_STORE_OWNER và internal", () => {
    expect(mapChamCongError({ code: "functions/permission-denied", details: { code: "POS_ACCOUNT_CONFLICT" } })).toContain("trùng");
    expect(mapChamCongError({ code: "functions/permission-denied", details: { code: "NOT_STORE_OWNER" } })).toContain("chủ cửa hàng");
    expect(mapChamCongError({ code: "functions/internal", message: "internal" })).toContain("chưa được cấu hình");
  });
});

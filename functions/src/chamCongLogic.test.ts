import { describe, it, expect } from "vitest";
import {
  normalizeChamCongRole,
  posRoleForChamCongRole,
  decidePosRole,
  slugifyUsername,
  buildUsernameBase,
  pickUniqueUsername,
  buildMemberships,
  decideSignIn,
  decideProfile,
  buildRevokePatch,
  isChamCongStoreOwner,
  decideLink,
  buildOkResponse,
  buildChooseStoreResponse,
  posUidForChamCong,
  isValidChamCongUid,
  ChamCongMembership,
} from "./chamCongLogic";

const mem = (over: Partial<ChamCongMembership> = {}): ChamCongMembership => ({
  chamCongStoreId: "S1",
  status: "active",
  roleKind: "employee",
  name: "Nguyễn Văn An",
  phone: "0900000000",
  avatarUrl: "",
  employeeCode: "",
  ...over,
});

describe("Ánh xạ vai trò Chấm Công → POS", () => {
  it("chuẩn hóa mọi biến thể vai trò", () => {
    expect(normalizeChamCongRole("owner")).toBe("owner");
    expect(normalizeChamCongRole("chu")).toBe("owner");
    for (const r of ["manager1", "manager_1", "manager", "legacyManager", "Manager-1"]) expect(normalizeChamCongRole(r)).toBe("manager1");
    for (const r of ["manager2", "manager_2"]) expect(normalizeChamCongRole(r)).toBe("manager2");
    for (const r of ["employee", "", undefined, "xyz"]) expect(normalizeChamCongRole(r)).toBe("employee");
  });

  it("vai trò POS dùng đúng id hệ thống", () => {
    expect(posRoleForChamCongRole("owner")).toBe("owner");
    expect(posRoleForChamCongRole("manager1")).toBe("manager_1");
    expect(posRoleForChamCongRole("manager2")).toBe("manager_2");
    expect(posRoleForChamCongRole("employee")).toBe("ROLE_WAITER");
  });

  it("chính sách đồng bộ / hạ quyền", () => {
    expect(decidePosRole("employee", null)).toBe("ROLE_WAITER");
    expect(decidePosRole("manager1", "ROLE_WAITER")).toBe("manager_1");
    expect(decidePosRole("owner", "manager_2")).toBe("owner");
    // Nhân viên: giữ vai trò chủ quán chọn trong POS
    expect(decidePosRole("employee", "ROLE_CASHIER")).toBe("ROLE_CASHIER");
    expect(decidePosRole("employee", "ROLE_KITCHEN")).toBe("ROLE_KITCHEN");
    // Bị hạ xuống nhân viên bên chấm công → hạ quyền POS
    expect(decidePosRole("employee", "manager_1")).toBe("ROLE_WAITER");
    expect(decidePosRole("employee", "owner")).toBe("ROLE_WAITER");
    expect(decidePosRole("employee", "ROLE_MANAGER")).toBe("ROLE_WAITER");
  });
});

describe("Username", () => {
  it("slug tiếng Việt an toàn", () => {
    expect(slugifyUsername("Nguyễn Văn Đức")).toBe("nguyenvanduc");
    expect(slugifyUsername("NV.001")).toBe("nv001");
  });
  it("ưu tiên mã nhân viên, rồi tên, rồi uid", () => {
    expect(buildUsernameBase("NV001", "An", "abc")).toBe("nv001");
    expect(buildUsernameBase("", "Trần Bình", "abc")).toBe("tranbinh");
    expect(buildUsernameBase("", "", "AbCdEf123")).toBe("nvabcdef");
  });
  it("khử trùng lặp bằng hậu tố", () => {
    expect(pickUniqueUsername("an", [])).toBe("an");
    expect(pickUniqueUsername("an", ["AN", "an-2"])).toBe("an-3");
    const long = "a".repeat(24);
    const r = pickUniqueUsername(long, [long]);
    expect(r.length).toBeLessThanOrEqual(24);
    expect(r.endsWith("-2")).toBe(true);
  });
});

describe("Quyết định đăng nhập", () => {
  const links = { TRAM01: "S1", TRAM02: "S2", TRAM03: "S3" };

  it("buildMemberships: ownerId luôn là chủ đang hoạt động", () => {
    const m = buildMemberships([{ storeId: "S1", data: { status: "pending", role: "employee", name: "X" } }], ["S1", "S9"]);
    expect(m.get("S1")).toMatchObject({ status: "active", roleKind: "owner", name: "X" });
    expect(m.get("S9")).toMatchObject({ status: "active", roleKind: "owner" });
  });

  it("không có cửa hàng liên kết → NOT_LINKED", () => {
    const m = buildMemberships([{ storeId: "SX", data: { status: "active" } }], []);
    expect(decideSignIn(links, m, [])).toMatchObject({ kind: "DENY", code: "NOT_LINKED" });
  });

  it("1 cửa hàng active → PROCEED", () => {
    const m = buildMemberships([{ storeId: "S1", data: { status: "active", role: "manager1" } }], []);
    expect(decideSignIn(links, m, [])).toMatchObject({ kind: "PROCEED", storeCode: "TRAM01" });
  });

  it(">1 cửa hàng active → CHOOSE, có storeCode → PROCEED", () => {
    const m = buildMemberships(
      [
        { storeId: "S1", data: { status: "active" } },
        { storeId: "S2", data: { status: "active" } },
      ],
      []
    );
    expect(decideSignIn(links, m, [])).toMatchObject({ kind: "CHOOSE", storeCodes: ["TRAM01", "TRAM02"] });
    expect(decideSignIn(links, m, [], "TRAM02")).toMatchObject({ kind: "PROCEED", storeCode: "TRAM02" });
    expect(decideSignIn(links, m, [], "TRAM03")).toMatchObject({ kind: "DENY", code: "NOT_LINKED" });
  });

  it("kicked / pending / bị xóa → NOT_ACTIVE_MEMBER + khóa", () => {
    const m = buildMemberships(
      [
        { storeId: "S1", data: { status: "kicked" } },
        { storeId: "S2", data: { status: "pending" } },
      ],
      []
    );
    expect(decideSignIn(links, m, ["TRAM03"])).toEqual({
      kind: "DENY",
      code: "NOT_ACTIVE_MEMBER",
      revokeStoreCodes: ["TRAM01", "TRAM02", "TRAM03"],
    });
    expect(decideSignIn(links, m, [], "TRAM01")).toEqual({ kind: "DENY", code: "NOT_ACTIVE_MEMBER", revokeStoreCodes: ["TRAM01"] });
  });

  it("active 1 nơi, bị kick nơi khác → vẫn vào nhưng khóa nơi bị kick", () => {
    const m = buildMemberships(
      [
        { storeId: "S1", data: { status: "active" } },
        { storeId: "S2", data: { status: "kicked" } },
      ],
      []
    );
    expect(decideSignIn(links, m, [])).toMatchObject({ kind: "PROCEED", storeCode: "TRAM01", revokeStoreCodes: ["TRAM02"] });
  });
});

describe("Hồ sơ POS", () => {
  const base = { posUid: "cc_u1", chamCongUid: "u1", now: 1000 };

  it("tạo mới: đủ trường, username duy nhất, vai trò thấp nhất", () => {
    const d = decideProfile({ ...base, existing: null, membership: mem(), takenUsernames: ["nguyenvanan"] });
    expect(d.kind).toBe("WRITE");
    if (d.kind !== "WRITE") return;
    expect(d.isNew).toBe(true);
    expect(d.values).toMatchObject({
      uid: "cc_u1",
      username: "nguyenvanan-2",
      fullName: "Nguyễn Văn An",
      roleId: "ROLE_WAITER",
      isRootOwner: false,
      isActive: true,
      authProvider: "chamcong",
      chamCongUid: "u1",
      chamCongStoreId: "S1",
      mustChangePassword: false,
      createdAt: 1000,
    });
  });

  it("tài khoản gốc (không phải chamcong) → CONFLICT", () => {
    const d = decideProfile({ ...base, existing: { username: "x", roleId: "owner" }, membership: mem(), takenUsernames: [] });
    expect(d.kind).toBe("CONFLICT");
  });

  it("POS khóa thủ công → DISABLED; khóa do chấm công → mở lại", () => {
    const locked = { authProvider: "chamcong", isActive: false, roleId: "ROLE_WAITER", username: "an" };
    expect(decideProfile({ ...base, existing: locked, membership: mem(), takenUsernames: [] }).kind).toBe("DISABLED");
    const d = decideProfile({
      ...base,
      existing: { ...locked, deactivatedBy: "chamcong" },
      membership: mem(),
      takenUsernames: [],
    });
    expect(d.kind).toBe("WRITE");
    if (d.kind === "WRITE") {
      expect(d.reactivated).toBe(true);
      expect(d.values).toMatchObject({ isActive: true, deactivatedBy: null, chamCongRevokedAt: null });
    }
  });

  it("đồng bộ tên/sđt và vai trò, giữ username", () => {
    const existing = { authProvider: "chamcong", isActive: true, roleId: "ROLE_CASHIER", username: "an", fullName: "Cũ", phone: "", chamCongStoreId: "S1" };
    const d = decideProfile({ ...base, existing, membership: mem(), takenUsernames: [] });
    if (d.kind !== "WRITE") throw new Error("expected WRITE");
    expect(d.values).toEqual({ fullName: "Nguyễn Văn An", phone: "0900000000" });
    expect(d.roleId).toBe("ROLE_CASHIER");
    expect(d.roleChange).toBeNull();

    const d2 = decideProfile({ ...base, existing, membership: mem({ roleKind: "manager2" }), takenUsernames: [] });
    if (d2.kind !== "WRITE") throw new Error("expected WRITE");
    expect(d2.roleChange).toEqual({ from: "ROLE_CASHIER", to: "manager_2" });
  });

  it("không đụng hồ sơ isRootOwner", () => {
    const d = decideProfile({
      ...base,
      existing: { authProvider: "chamcong", isRootOwner: true, roleId: "owner" },
      membership: mem(),
      takenUsernames: [],
    });
    expect(d).toMatchObject({ kind: "WRITE", values: {}, roleChange: null, roleId: "owner" });
  });

  it("patch khóa khi bị kick", () => {
    expect(buildRevokePatch(null, 1)).toBeNull();
    expect(buildRevokePatch({ roleId: "owner" }, 1)).toBeNull();
    expect(buildRevokePatch({ authProvider: "chamcong", isRootOwner: true }, 1)).toBeNull();
    expect(buildRevokePatch({ authProvider: "chamcong", isActive: false }, 1)).toBeNull();
    expect(buildRevokePatch({ authProvider: "chamcong", isActive: true }, 5)).toEqual({
      isActive: false,
      deactivatedBy: "chamcong",
      chamCongRevokedAt: 5,
    });
  });
});

describe("Liên kết & phản hồi", () => {
  it("chủ store chấm công", () => {
    expect(isChamCongStoreOwner({ ownerId: "u1" }, null, "u1")).toBe(true);
    expect(isChamCongStoreOwner(null, { role: "chu", status: "active" }, "u1")).toBe(true);
    expect(isChamCongStoreOwner(null, { role: "owner", status: "kicked" }, "u1")).toBe(false);
    expect(isChamCongStoreOwner({ ownerId: "x" }, { role: "manager1", status: "active" }, "u1")).toBe(false);
  });
  it("ALREADY_LINKED", () => {
    expect(decideLink(null, "TRAM01")).toBe("OK");
    expect(decideLink("TRAM01", "TRAM01")).toBe("OK");
    expect(decideLink("TRAM02", "TRAM01")).toBe("ALREADY_LINKED");
  });
  it("định dạng phản hồi", () => {
    expect(buildOkResponse({ customToken: "t", storeCode: "TRAM01", uid: "cc_u", roleId: "owner", isNewAccount: true })).toEqual({
      status: "OK",
      customToken: "t",
      storeCode: "TRAM01",
      uid: "cc_u",
      roleId: "owner",
      isNewAccount: true,
    });
    expect(buildChooseStoreResponse(["A1", "B1"], { A1: "Trạm A" })).toEqual({
      status: "CHOOSE_STORE",
      stores: [
        { storeCode: "A1", storeName: "Trạm A" },
        { storeCode: "B1", storeName: "B1" },
      ],
    });
  });
  it("uid POS", () => {
    expect(posUidForChamCong("abc")).toBe("cc_abc");
    expect(isValidChamCongUid("a".repeat(125))).toBe(true);
    expect(isValidChamCongUid("a".repeat(126))).toBe(false);
    expect(isValidChamCongUid("a/b")).toBe(false);
  });
});

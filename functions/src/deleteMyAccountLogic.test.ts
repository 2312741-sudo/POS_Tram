import { describe, it, expect } from "vitest";
import {
  DELETE_CONFIRM_WORD,
  ROOT_OWNER_MESSAGE,
  ProfileLike,
  isConfirmed,
  storeCodesFromIndex,
  placeholderUsername,
  findRootOwnerStores,
  decideStoreAction,
  planAccountDeletion,
  chamCongUidOf,
  buildAnonymisedProfile,
  buildSelfDeleteAudit,
  KEPT_PROFILE_KEYS,
} from "./deleteMyAccountLogic";

const UID = "abcdefgh12345678";
const NOW = 1_770_000_000_000;

const staff = (over: ProfileLike = {}): ProfileLike => ({
  uid: UID,
  username: "nguyenvana",
  fullName: "Nguyễn Văn A",
  phone: "0901234567",
  email: "a@example.com",
  avatarUrl: "https://example.com/a.png",
  roleId: "ROLE_STAFF",
  isRootOwner: false,
  isActive: true,
  customPermissions: ["sell"],
  chamCongUid: "ccUid123",
  chamCongStoreId: "CC_STORE_1",
  createdAt: 1_700_000_000_000,
  lastLoginAt: 1_760_000_000_000,
  mustChangePassword: false,
  ...over,
});

describe("Xác nhận từ khóa", () => {
  it("chỉ chấp nhận đúng XOA", () => {
    expect(DELETE_CONFIRM_WORD).toBe("XOA");
    expect(isConfirmed("XOA")).toBe(true);
    expect(isConfirmed("xoa")).toBe(false);
    expect(isConfirmed(" XOA ")).toBe(false);
    expect(isConfirmed(undefined)).toBe(false);
    expect(isConfirmed(null)).toBe(false);
  });
});

describe("Đọc userIndex", () => {
  it("lấy mã chi nhánh từ map, bỏ qua dữ liệu lạ", () => {
    expect(storeCodesFromIndex({ S1: true, S2: true })).toEqual(["S1", "S2"]);
    expect(storeCodesFromIndex(null)).toEqual([]);
    expect(storeCodesFromIndex("S1")).toEqual([]);
    expect(storeCodesFromIndex([true])).toEqual([]);
  });
});

describe("Chặn chủ quán gốc (ROOT_OWNER)", () => {
  it("chặn khi là chủ quán gốc ở chi nhánh đơn", () => {
    const plan = planAccountDeletion(["S1"], { S1: staff({ isRootOwner: true, roleId: "ROLE_OWNER" }) });
    expect(plan).toEqual({ kind: "ROOT_OWNER", rootStores: ["S1"] });
  });

  it("chặn khi chỉ là chủ quán gốc ở MỘT trong nhiều chi nhánh", () => {
    const plan = planAccountDeletion(["S1", "S2", "S3"], {
      S1: staff({ roleId: "ROLE_STAFF" }),
      S2: staff({ isRootOwner: true }),
      S3: staff({ roleId: "ROLE_MANAGER" }),
    });
    expect(plan.kind).toBe("ROOT_OWNER");
    if (plan.kind === "ROOT_OWNER") expect(plan.rootStores).toEqual(["S2"]);
  });

  it("chủ quán thường (không root) vẫn được phép xóa", () => {
    const plan = planAccountDeletion(["S1"], { S1: staff({ roleId: "ROLE_OWNER", isRootOwner: false }) });
    expect(plan.kind).toBe("OK");
  });

  it("thông điệp lỗi đúng nội dung yêu cầu", () => {
    expect(ROOT_OWNER_MESSAGE).toBe(
      "Chủ quán gốc không thể tự xóa tài khoản. Vui lòng liên hệ đơn vị vận hành để chuyển quyền trước khi xóa."
    );
    expect(findRootOwnerStores({ S1: null, S2: undefined })).toEqual([]);
  });
});

describe("Nhiều chi nhánh", () => {
  it("ẩn danh từng chi nhánh có hồ sơ, bỏ qua index mồ côi, gỡ mọi index", () => {
    const plan = planAccountDeletion(["S1", "S2", "S3"], {
      S1: staff(),
      S2: staff({ roleId: "ROLE_MANAGER" }),
      S3: null,
    });
    expect(plan).toEqual({
      kind: "OK",
      anonymiseStores: ["S1", "S2"],
      skippedStores: ["S3"],
      indexStores: ["S1", "S2", "S3"],
    });
    expect(decideStoreAction(null)).toBe("SKIP");
    expect(decideStoreAction(staff())).toBe("ANONYMISE");
  });
});

describe("Ẩn danh hóa hồ sơ", () => {
  const anon = buildAnonymisedProfile(staff(), UID, NOW);

  it("loại toàn bộ khóa cá nhân", () => {
    for (const k of ["fullName", "phone", "email", "avatarUrl", "customPermissions", "chamCongUid", "chamCongStoreId", "mustChangePassword"]) {
      expect(anon).not.toHaveProperty(k);
    }
    expect(anon.fullName).toBeUndefined();
    expect(anon.phone).toBeUndefined();
    expect(anon.email).toBeUndefined();
  });

  it("giữ uid, roleId, mốc thời gian", () => {
    expect(anon.uid).toBe(UID);
    expect(anon.roleId).toBe("ROLE_STAFF");
    expect(anon.createdAt).toBe(1_700_000_000_000);
    expect(anon.lastLoginAt).toBe(1_760_000_000_000);
  });

  it("đặt trạng thái khóa, người khóa, thời điểm xóa và username placeholder", () => {
    expect(anon.isActive).toBe(false);
    expect(anon.deactivatedBy).toBe("self");
    expect(anon.deletedAt).toBe(NOW);
    expect(anon.username).toBe("deleted_abcdefgh");
    expect(placeholderUsername(UID)).toBe("deleted_abcdefgh");
  });

  it("mọi khóa còn lại đều nằm trong danh sách được giữ hoặc là trường trạng thái", () => {
    const allowed = new Set<string>([...KEPT_PROFILE_KEYS, "username", "isActive", "deactivatedBy", "deletedAt"]);
    for (const k of Object.keys(anon)) expect(allowed.has(k)).toBe(true);
  });

  it("khóa không có trong hồ sơ gốc không được tạo mới ngoài trạng thái", () => {
    const sparse = buildAnonymisedProfile({ roleId: "ROLE_STAFF" }, UID, NOW);
    expect(sparse).not.toHaveProperty("lastLoginAt");
    expect(sparse.roleId).toBe("ROLE_STAFF");
  });
});

describe("Liên kết Chấm Công", () => {
  it("lấy chamCongUid từ hồ sơ, hoặc suy ra từ uid cc_", () => {
    expect(chamCongUidOf(staff(), "cc_ccUid123")).toBe("ccUid123");
    expect(chamCongUidOf({ roleId: "x" }, "cc_ccUid999")).toBe("ccUid999");
    expect(chamCongUidOf({ roleId: "x" }, "plainuid")).toBeNull();
    expect(chamCongUidOf({ chamCongUid: "   " }, "cc_")).toBeNull();
  });
});

describe("Audit và idempotency", () => {
  it("audit chỉ chứa uid và placeholder, không có họ tên/SĐT/email", () => {
    const a = buildSelfDeleteAudit(UID, "ROLE_STAFF", NOW);
    expect(a.action).toBe("DELETE_OWN_ACCOUNT");
    expect(a.targetId).toBe(UID);
    expect(a.username).toBe("deleted_abcdefgh");
    expect(JSON.stringify(a)).not.toMatch(/Nguyễn|0901234567|a@example\.com/);
  });

  it("gọi lại khi không còn hồ sơ nào: kế hoạch rỗng, không ghi gì, không lỗi", () => {
    const first = planAccountDeletion(["S1"], { S1: staff() });
    expect(first.kind).toBe("OK");
    // Sau lần đầu index đã được gỡ → lần 2 không còn chi nhánh nào
    const second = planAccountDeletion([], {});
    expect(second).toEqual({ kind: "OK", anonymiseStores: [], skippedStores: [], indexStores: [] });
  });

  it("hồ sơ đã ẩn danh (isActive=false) vẫn an toàn khi gọi lại", () => {
    const anon = buildAnonymisedProfile(staff(), UID, NOW);
    const plan = planAccountDeletion(["S1"], { S1: anon });
    expect(plan.kind).toBe("OK");
    expect(findRootOwnerStores({ S1: anon })).toEqual([]);
  });
});

import { describe, it, expect } from "vitest";
import {
  approvalAuditFields,
  approverOptions,
  canUserApprove,
  isApprovalValid,
  mapApprovalError,
  parseApproval,
  withApprovalMeta,
  type ManagerApproval,
} from "../lib/manager-approval";

const approval: ManagerApproval = {
  approvalId: "LOG_1",
  approverUid: "u1",
  approverName: "Lan",
  action: "DISCOUNT_ITEM",
  approvedAt: 1000,
  expiresAt: 5000,
};

describe("manager approval", () => {
  it("parseApproval kiểm tra hình dạng", () => {
    expect(parseApproval({ ...approval })).toMatchObject({ approvalId: "LOG_1", approverName: "Lan" });
    expect(parseApproval({ ...approval, action: "CANCEL_BILL" })).toBeNull();
    expect(parseApproval(null)).toBeNull();
  });

  it("hiệu lực theo hành động và thời hạn", () => {
    expect(isApprovalValid(approval, "DISCOUNT_ITEM", 4000)).toBe(true);
    expect(isApprovalValid(approval, "DISCOUNT_ITEM", 5000)).toBe(false);
    expect(isApprovalValid(approval, "CANCEL_KITCHEN_ITEM", 4000)).toBe(false);
    expect(isApprovalValid(null, "DISCOUNT_ITEM")).toBe(false);
  });

  it("gắn / gỡ metadata người duyệt trên dòng", () => {
    const line = withApprovalMeta({ name: "A", price: 1 }, approval, true);
    expect(line).toMatchObject({ discountApprovedBy: "u1", discountApprovedByName: "Lan", discountApprovalId: "LOG_1" });
    expect(withApprovalMeta(line, approval, false)).not.toHaveProperty("discountApprovedBy");
    expect(withApprovalMeta(line, null, true)).not.toHaveProperty("discountApprovalId");
    expect(approvalAuditFields(approval)).toEqual({ approvedBy: "u1", approvedByName: "Lan", approvalId: "LOG_1" });
    expect(approvalAuditFields(null)).toEqual({});
  });

  it("quyền duyệt khớp máy chủ", () => {
    expect(canUserApprove({ roleId: "ROLE_OWNER" }, "CANCEL_KITCHEN_ITEM")).toBe(true);
    expect(canUserApprove({ roleId: "ROLE_MANAGER_2" }, "DISCOUNT_ITEM")).toBe(true);
    expect(canUserApprove({ roleId: "ROLE_MANAGER_2" }, "CANCEL_KITCHEN_ITEM")).toBe(false);
    expect(canUserApprove({ roleId: "manager_1" }, "CANCEL_KITCHEN_ITEM")).toBe(true);
    expect(canUserApprove({ roleId: "ROLE_CASHIER", customPermissions: ["DISCOUNT_ITEM"] }, "DISCOUNT_ITEM")).toBe(false);
    expect(canUserApprove({ roleId: "ROLE_OWNER", isActive: false }, "DISCOUNT_ITEM")).toBe(false);
  });

  it("approverOptions: bỏ người gọi, người thiếu uid, ưu tiên người đã có PIN", () => {
    const opts = approverOptions(
      [
        { uid: "a", fullName: "An", roleId: "ROLE_MANAGER_1" },
        { uid: "b", fullName: "Bình", roleId: "ROLE_OWNER", hasApprovalPin: true },
        { uid: "me", fullName: "Tôi", roleId: "ROLE_OWNER" },
        { fullName: "Không uid", roleId: "ROLE_OWNER" },
        { uid: "c", fullName: "Cường", roleId: "ROLE_CASHIER" },
      ],
      "DISCOUNT_ITEM",
      "me"
    );
    expect(opts.map((o) => o.uid)).toEqual(["b", "a"]);
  });

  it("thông báo lỗi", () => {
    expect(mapApprovalError({ code: "functions/permission-denied", message: "PIN sai" })).toBe("PIN sai");
    expect(mapApprovalError({ code: "functions/not-found" })).toMatch(/chưa triển khai/);
  });
});

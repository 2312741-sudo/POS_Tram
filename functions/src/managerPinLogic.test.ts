import { describe, it, expect } from "vitest";
import {
  approverHasPermission,
  hashPin,
  isApprovableAction,
  isApproverEligible,
  matchApprover,
  sanitizeContext,
  validatePinFormat,
  verifyPinHash,
  type PinCandidate,
} from "./managerPinLogic";

describe("validatePinFormat", () => {
  it("chỉ nhận 4–8 chữ số, không lặp một chữ số", () => {
    expect(validatePinFormat("1357")).toBeNull();
    expect(validatePinFormat("12345678")).toBeNull();
    expect(validatePinFormat("123")).not.toBeNull();
    expect(validatePinFormat("123456789")).not.toBeNull();
    expect(validatePinFormat("12a4")).not.toBeNull();
    expect(validatePinFormat("1111")).not.toBeNull();
    expect(validatePinFormat(1234)).not.toBeNull();
  });
});

describe("hashPin / verifyPinHash", () => {
  it("băm có salt, xác minh đúng/sai", () => {
    const a = hashPin("2468");
    const b = hashPin("2468");
    expect(a.salt).not.toBe(b.salt);
    expect(a.hash).not.toBe(b.hash);
    expect(a.hash).not.toContain("2468");
    expect(verifyPinHash("2468", a)).toBe(true);
    expect(verifyPinHash("2469", a)).toBe(false);
    expect(verifyPinHash("2468", null)).toBe(false);
    expect(verifyPinHash("2468", { ...a, hash: "abcd" })).toBe(false);
  });
});

describe("quyền người duyệt", () => {
  it("chủ quán duyệt mọi thao tác; quản lý 2 chỉ giảm giá; thu ngân không được duyệt", () => {
    expect(approverHasPermission({ roleId: "ROLE_OWNER" }, "CANCEL_KITCHEN_ITEM")).toBe(true);
    expect(approverHasPermission({ roleId: "x", isRootOwner: true }, "CANCEL_KITCHEN_ITEM")).toBe(true);
    expect(approverHasPermission({ roleId: "manager_1" }, "CANCEL_KITCHEN_ITEM")).toBe(true);
    expect(approverHasPermission({ roleId: "ROLE_MANAGER_2" }, "DISCOUNT_ITEM")).toBe(true);
    expect(approverHasPermission({ roleId: "ROLE_MANAGER_2" }, "CANCEL_KITCHEN_ITEM")).toBe(false);
    expect(
      approverHasPermission({ roleId: "ROLE_MANAGER_2", customPermissions: ["CANCEL_KITCHEN_ITEM"] }, "CANCEL_KITCHEN_ITEM")
    ).toBe(true);
    expect(approverHasPermission({ roleId: "ROLE_CASHIER", customPermissions: ["DISCOUNT_ITEM"] }, "DISCOUNT_ITEM")).toBe(false);
    expect(approverHasPermission({ roleId: "ROLE_OWNER", isActive: false }, "DISCOUNT_ITEM")).toBe(false);
    expect(isApproverEligible({ roleId: "ROLE_WAITER" })).toBe(false);
  });

  it("isApprovableAction", () => {
    expect(isApprovableAction("DISCOUNT_ITEM")).toBe(true);
    expect(isApprovableAction("CANCEL_BILL")).toBe(false);
  });
});

describe("matchApprover", () => {
  const owner: PinCandidate = { uid: "o1", profile: { roleId: "ROLE_OWNER", fullName: "Chủ" }, stored: hashPin("2580") };
  const m2: PinCandidate = { uid: "m2", profile: { roleId: "ROLE_MANAGER_2" }, stored: hashPin("1357") };
  const m2b: PinCandidate = { uid: "m3", profile: { roleId: "manager_1" }, stored: hashPin("1357") };
  const cashier: PinCandidate = { uid: "c1", profile: { roleId: "ROLE_CASHIER" }, stored: hashPin("9753") };

  it("khớp đúng người duyệt", () => {
    const r = matchApprover([owner, m2, cashier], "2580", "CANCEL_KITCHEN_ITEM");
    expect(r).toMatchObject({ ok: true, uid: "o1" });
  });

  it("sai PIN / PIN của thu ngân / quản lý thiếu quyền", () => {
    expect(matchApprover([owner, m2], "0000", "DISCOUNT_ITEM")).toEqual({ ok: false, reason: "NO_MATCH" });
    expect(matchApprover([cashier], "9753", "DISCOUNT_ITEM")).toEqual({ ok: false, reason: "NO_MATCH" });
    expect(matchApprover([m2], "1357", "CANCEL_KITCHEN_ITEM")).toEqual({ ok: false, reason: "NOT_PERMITTED" });
  });

  it("trùng PIN: không chọn người duyệt → AMBIGUOUS; chọn người duyệt → khớp", () => {
    expect(matchApprover([m2, m2b], "1357", "DISCOUNT_ITEM")).toEqual({ ok: false, reason: "AMBIGUOUS" });
    expect(matchApprover([m2, m2b], "1357", "DISCOUNT_ITEM", "m2")).toMatchObject({ ok: true, uid: "m2" });
    // Chỉ một người trùng PIN có quyền → không mơ hồ
    expect(matchApprover([m2, m2b], "1357", "CANCEL_KITCHEN_ITEM")).toMatchObject({ ok: true, uid: "m3" });
    // Chọn người duyệt nhưng PIN thuộc người khác → sai
    expect(matchApprover([owner, m2], "2580", "DISCOUNT_ITEM", "m2")).toEqual({ ok: false, reason: "NO_MATCH" });
  });
});

describe("sanitizeContext", () => {
  it("cắt 200 ký tự, bỏ ký tự điều khiển", () => {
    expect(sanitizeContext("a\nb")).toBe("a b");
    expect(sanitizeContext("x".repeat(300))).toHaveLength(200);
    expect(sanitizeContext(5)).toBe("");
  });
});

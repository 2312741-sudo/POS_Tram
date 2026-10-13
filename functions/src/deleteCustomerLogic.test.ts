import { describe, it, expect } from "vitest";
import {
  buildDeleteAuditDetails,
  canCallerDeleteCustomer,
  isDeleteConfirmed,
  maskPhone,
  planDeleteCustomer,
} from "./deleteCustomerLogic";

describe("quyền & xác nhận", () => {
  it("chỉ owner/manager đang hoạt động và thuộc quán", () => {
    expect(canCallerDeleteCustomer({ roleId: "ROLE_MANAGER" }, true)).toBe(true);
    expect(canCallerDeleteCustomer({ roleId: "manager_1" }, true)).toBe(true);
    expect(canCallerDeleteCustomer({ roleId: "owner" }, true)).toBe(true);
    expect(canCallerDeleteCustomer({ roleId: "x", isRootOwner: true }, true)).toBe(true);
    expect(canCallerDeleteCustomer({ roleId: "ROLE_STAFF" }, true)).toBe(false);
    expect(canCallerDeleteCustomer({ roleId: "ROLE_KITCHEN" }, true)).toBe(false);
    expect(canCallerDeleteCustomer({ roleId: "ROLE_MANAGER", isActive: false }, true)).toBe(false);
    expect(canCallerDeleteCustomer({ roleId: "ROLE_MANAGER" }, false)).toBe(false);
    expect(canCallerDeleteCustomer(null, true)).toBe(false);
  });
  it("confirm XOA", () => {
    expect(isDeleteConfirmed("XOA")).toBe(true);
    expect(isDeleteConfirmed(" xoa ")).toBe(true);
    expect(isDeleteConfirmed("xóa")).toBe(false);
    expect(isDeleteConfirmed(undefined)).toBe(false);
  });
  it("mask SĐT & audit không chứa đủ SĐT", () => {
    expect(maskPhone("0912345678")).toBe("...678");
    expect(maskPhone("")).toBe("");
    const d = buildDeleteAuditDetails("An", "0912345678", true);
    expect(d).toContain("An");
    expect(d).toContain("...678");
    expect(d).not.toContain("0912345678");
  });
});

describe("planDeleteCustomer", () => {
  const customer = { ho_ten: "An", so_dien_thoai: "0912345678" };
  const ledger = { op1: { at: Date.UTC(2026, 4, 10) }, op2: { at: Date.UTC(2026, 5, 2) }, bad: {} };

  it("khách còn ở chi nhánh khác: chỉ gỡ liên kết, giữ member + sổ cái", () => {
    const member = { branches: { S1: { c1: true }, S2: { c9: true } } };
    const p = planDeleteCustomer({ storeCode: "S1", customerId: "c1", customer, member, ledger });
    expect(p.removedMember).toBe(false);
    expect(p.memberKey).toBe("0912345678");
    expect(p.updates).toEqual({
      "stores/S1/customers/c1": null,
      "loyalty_members/0912345678/branches/S1/c1": null,
    });
  });
  it("còn khách khác cùng chi nhánh: giữ member", () => {
    const member = { branches: { S1: { c1: true, c2: true } } };
    expect(planDeleteCustomer({ storeCode: "S1", customerId: "c1", customer, member, ledger }).removedMember).toBe(false);
  });
  it("không còn liên kết: xóa member, sổ cái và chỉ mục theo tháng", () => {
    const member = { branches: { S1: { c1: true } } };
    const p = planDeleteCustomer({ storeCode: "S1", customerId: "c1", customer, member, ledger });
    expect(p.removedMember).toBe(true);
    const keys = Object.keys(p.updates);
    expect(keys).toContain("loyalty_members/0912345678");
    expect(keys).toContain("loyalty_ledger/0912345678");
    expect(keys.filter((k) => k.startsWith("loyalty_ledger_index/"))).toHaveLength(2);
    expect(keys.some((k) => k.includes("/branches/"))).toBe(false);
    expect(Object.values(p.updates).every((v) => v === null)).toBe(true);
  });
  it("khách không SĐT dùng khóa cục bộ L_", () => {
    const p = planDeleteCustomer({ storeCode: "S1", customerId: "c1", customer: { ho_ten: "B" }, member: { branches: { S1: { c1: true } } }, ledger: null });
    expect(p.memberKey).toBe("L_S1_c1");
    expect(p.removedMember).toBe(true);
  });
  it("member chưa tồn tại: chỉ xóa node khách", () => {
    const p = planDeleteCustomer({ storeCode: "S1", customerId: "c1", customer, member: null, ledger: null });
    expect(p.removedMember).toBe(false);
    expect(p.updates).toEqual({ "stores/S1/customers/c1": null });
  });
});

import { describe, it, expect } from "vitest";
import {
  buildDeleteCustomerPayload,
  deleteSuccessMessage,
  isDeleteConfirmed,
  parseDeleteCustomerResult,
} from "../lib/customer-delete-client";

describe("customer-delete-client", () => {
  it("xác nhận XOA", () => {
    expect(isDeleteConfirmed("XOA")).toBe(true);
    expect(isDeleteConfirmed(" xoa ")).toBe(true);
    expect(isDeleteConfirmed("xóa")).toBe(false);
    expect(isDeleteConfirmed("")).toBe(false);
  });
  it("payload chuẩn hóa", () => {
    expect(buildDeleteCustomerPayload(" s1 ", "c1", "xoa")).toEqual({ storeCode: "S1", customerId: "c1", confirm: "XOA" });
  });
  it("parse kết quả", () => {
    expect(parseDeleteCustomerResult({ success: true, removedMember: true })).toEqual({ success: true, removedMember: true });
    expect(parseDeleteCustomerResult(null)).toEqual({ success: false, removedMember: false });
  });
  it("thông báo theo removedMember", () => {
    expect(deleteSuccessMessage({ success: true, removedMember: true })).toContain("toàn bộ điểm");
    expect(deleteSuccessMessage({ success: true, removedMember: false })).toContain("còn ở chi nhánh khác");
  });
});

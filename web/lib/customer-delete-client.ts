/**
 * Client xóa khách hàng: bọc Cloud Function callable `deleteCustomer` (functions/src/deleteCustomer.ts).
 * Chỉ Chủ quán / Quản lý; phải gõ XOA để xác nhận.
 */
import { httpsCallable } from "firebase/functions";
import { functions } from "./firebase";

export const DELETE_CUSTOMER_CONFIRM = "XOA";

export interface DeleteCustomerPayload {
  storeCode: string;
  customerId: string;
  confirm: string;
}

export interface DeleteCustomerResult {
  success: boolean;
  /** true nếu khách không còn ở chi nhánh nào nên đã xóa cả điểm/sổ cái dùng chung */
  removedMember: boolean;
}

/** Người dùng đã gõ đúng từ khóa xác nhận chưa (không phân biệt hoa thường, bỏ khoảng trắng đầu/cuối) */
export function isDeleteConfirmed(input: string): boolean {
  return input.trim().toUpperCase() === DELETE_CUSTOMER_CONFIRM;
}

export function buildDeleteCustomerPayload(storeCode: string, customerId: string, confirmText: string): DeleteCustomerPayload {
  return { storeCode: storeCode.trim().toUpperCase(), customerId, confirm: confirmText.trim().toUpperCase() };
}

export function parseDeleteCustomerResult(data: unknown): DeleteCustomerResult {
  const d = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
  return { success: d.success === true, removedMember: d.removedMember === true };
}

/** Thông báo cho người dùng sau khi xóa thành công */
export function deleteSuccessMessage(r: DeleteCustomerResult): string {
  return r.removedMember
    ? "Đã xóa khách hàng và toàn bộ điểm tích lũy."
    : "Đã xóa khách hàng khỏi chi nhánh này. Điểm được giữ vì khách còn ở chi nhánh khác.";
}

export async function deleteCustomer(storeCode: string, customerId: string, confirmText: string): Promise<DeleteCustomerResult> {
  const res = await httpsCallable<DeleteCustomerPayload, unknown>(functions, "deleteCustomer")(
    buildDeleteCustomerPayload(storeCode, customerId, confirmText)
  );
  return parseDeleteCustomerResult(res.data);
}

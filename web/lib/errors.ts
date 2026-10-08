/**
 * Lấy thông điệp lỗi an toàn từ giá trị bắt được trong catch (kiểu unknown).
 * Trả về fallback khi lỗi không có message.
 */
export function errorMessage(e: unknown, fallback = ""): string {
  if (e instanceof Error && e.message) return e.message;
  if (typeof e === "string" && e) return e;
  if (e && typeof e === "object" && "message" in e) {
    const msg = (e as { message?: unknown }).message;
    if (typeof msg === "string" && msg) return msg;
  }
  return fallback;
}

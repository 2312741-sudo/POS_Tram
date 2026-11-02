/**
 * App bản cũ lưu món theo khóa = TÊN món. Món có khóa khác tên (sao chép từ cửa hàng khác, tạo trên web)
 * mỗi lần bấm Lưu trên app lại sinh thêm 1 nút products/{tên} → trùng món.
 * Trigger productDedupe gộp nút vừa tạo vào món cũ cùng tên rồi xóa nút trùng (không cần build lại app).
 */
export type AnyMap = Record<string, unknown>;

const norm = (v: unknown) => String(v ?? "").trim().toLowerCase().replace(/\s+/g, " ");

/** Khóa món cũ cần gộp vào (null = món mới thật, không trùng) */
export function findDuplicateTarget(newKey: string, created: AnyMap, products: Record<string, unknown>): string | null {
  const name = norm(created.name);
  if (!name) return null;
  const matches = Object.entries(products)
    .filter(([k, v]) => k !== newKey && v && typeof v === "object" && norm((v as AnyMap).name) === name)
    .map(([k]) => k);
  // Nhiều hơn 1 món cùng tên: không đoán, để nguyên
  return matches.length === 1 ? matches[0] : null;
}

/** Nội dung ghi đè lên món cũ: dữ liệu vừa sửa, giữ mã định danh `id` của món cũ */
export function mergedProduct(target: AnyMap, created: AnyMap): AnyMap {
  const out: AnyMap = { ...target, ...created };
  if (target.id !== undefined) out.id = target.id;
  else delete out.id;
  return out;
}

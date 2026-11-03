/**
 * Topping của một dòng món là DANH SÁCH TÊN, mỗi phần tử = 1 phần: tên lặp lại = nhiều phần
 * (["Trân châu", "Thạch", "Trân châu"] = 2 trân châu + 1 thạch). Giá = tổng giá từng phần tử, nên không đổi
 * cách tính tiền / báo cáo. Bản Dart song song: app_flutter/lib/core/utils/topping_utils.dart.
 */
export function toppingCount(toppings: readonly string[], name: string): number {
  return toppings.filter((t) => t === name).length;
}

/** Gộp topping lặp, giữ thứ tự xuất hiện đầu tiên: ["A","B","A"] -> [{A,2},{B,1}] */
export function groupToppings(toppings: readonly unknown[]): { name: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const t of toppings) {
    const n = String(t ?? "");
    if (!n.trim()) continue;
    counts.set(n, (counts.get(n) ?? 0) + 1);
  }
  return [...counts.entries()].map(([name, count]) => ({ name, count }));
}

/** Nhãn hiển thị: ["A","B","A"] -> ["A x2","B"] */
export function toppingLabels(toppings: readonly unknown[]): string[] {
  return groupToppings(toppings).map((g) => (g.count > 1 ? `${g.name} x${g.count}` : g.name));
}

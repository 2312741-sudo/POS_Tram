// Topping của một dòng món là DANH SÁCH TÊN, mỗi phần tử = 1 phần: tên lặp lại = nhiều phần
// (VD ["Trân châu", "Thạch", "Trân châu"] = 2 trân châu + 1 thạch). Giá = tổng giá từng phần tử,
// nên không đổi cách tính tiền / báo cáo. Bản TypeScript song song: web/lib/topping-utils.ts.

/// Số phần của [name] trong [toppings]
int toppingCount(Iterable<String> toppings, String name) => toppings.where((t) => t == name).length;

/// Gộp topping lặp, giữ thứ tự xuất hiện đầu tiên: ["A","B","A"] -> [("A",2),("B",1)]
List<({String name, int count})> groupToppings(Iterable<String> toppings) {
  final counts = <String, int>{};
  for (final t in toppings) {
    if (t.trim().isEmpty) continue;
    counts[t] = (counts[t] ?? 0) + 1;
  }
  return [for (final e in counts.entries) (name: e.key, count: e.value)];
}

/// Nhãn hiển thị: ["A","B","A"] -> ["A x2","B"]
List<String> toppingLabels(Iterable<String> toppings) =>
    [for (final g in groupToppings(toppings)) g.count > 1 ? '${g.name} x${g.count}' : g.name];

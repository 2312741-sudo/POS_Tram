import { describe, it, expect } from "vitest";
import { buildGroupLookup } from "../lib/pricing-engine";

// Dữ liệu thật TRẠM CHANH: món tạo từ web không có id số → app lưu productId = 0 cho mọi món đó
const products = [
  { id: "-P3oQPJ8TeyxJoLJ4d1h", name: "Bánh gấu", category: "SNACK" },
  { id: "-P3oRQhglBsZh6YHCTy8", name: "Trà olong - Tắc", category: "TRÀ TRÁI CÂY" },
  { id: "1", name: "Trà Olong - Chanh tươi", category: "TRÀ TRÁI CÂY" },
];

describe("buildGroupLookup", () => {
  const groupOf = buildGroupLookup(products);
  it("productId 0 (món từ web) tra theo tên, không rơi vào món bất kỳ", () => {
    expect(groupOf({ productId: 0, name: "Trà olong - Tắc" })).toBe("TRÀ TRÁI CÂY");
    expect(groupOf({ productId: 0, name: "Bánh gấu" })).toBe("SNACK");
  });
  it("id hợp lệ và khớp tên", () => {
    expect(groupOf({ productId: 1, name: "Trà Olong - Chanh tươi" })).toBe("TRÀ TRÁI CÂY");
  });
  it("id trùng nhưng tên khác thì ưu tiên tên", () => {
    expect(groupOf({ productId: 1, name: "Bánh gấu" })).toBe("SNACK");
  });
  it("không tìm thấy thì dùng category của dòng", () => {
    expect(groupOf({ productId: 0, name: "Món lạ", category: "Khác" })).toBe("Khác");
    expect(groupOf({ productId: 0, name: "Món lạ" })).toBeNull();
  });
});

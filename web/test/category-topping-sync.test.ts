import { describe, it, expect } from "vitest";
import { syncCategoryToppingGroup } from "../lib/category-topping-sync";
import type { ToppingGroup } from "../lib/item-options";

const group: ToppingGroup = {
  id: "legacy_cat_TRÀ_TRÁI_CÂY", name: "Topping - TRÀ TRÁI CÂY", sortOrder: 2, active: true, multi: true, max: 0,
  items: [{ id: "t1", name: "Thạch chanh", price: 5000 }, { id: "t2", name: "Thạch dừa", price: 5000 }],
};
const products = [
  { id: "p1", name: "Thạch chanh", price: 5000 },
  { id: "p2", name: "Thạch dừa", price: 5000 },
  { id: "p3", name: "Tăng giá Grab 2K (tính theo hoa hồng)", price: 2000 },
];
const base = { categoryName: "TRÀ TRÁI CÂY", toppingGroupIds: [group.id], groups: [group], otherCategoryGroupIds: [], products };

describe("đồng bộ topping được phép → nhóm topping của danh mục", () => {
  it("tích thêm Grab 2K → thêm vào nhóm, giữ nguyên dòng cũ", () => {
    const g = syncCategoryToppingGroup({ ...base, allowedToppings: ["Thạch chanh", "Thạch dừa", "Tăng giá Grab 2K (tính theo hoa hồng)"] });
    expect(g?.items).toEqual([group.items[0], group.items[1], { id: "t3", name: "Tăng giá Grab 2K (tính theo hoa hồng)", price: 2000 }]);
  });
  it("bỏ tích → gỡ khỏi nhóm; không đổi → null", () => {
    expect(syncCategoryToppingGroup({ ...base, allowedToppings: ["Thạch dừa"] })?.items).toEqual([group.items[1]]);
    expect(syncCategoryToppingGroup({ ...base, allowedToppings: ["Thạch chanh", "Thạch dừa"] })).toBeNull();
  });
  it("ô cũ để trống → không đụng nhóm", () => {
    expect(syncCategoryToppingGroup({ ...base, allowedToppings: [] })).toBeNull();
  });
  it("nhóm dùng chung với danh mục khác → không sửa", () => {
    expect(syncCategoryToppingGroup({ ...base, otherCategoryGroupIds: [[group.id]], allowedToppings: ["Thạch dừa"] })).toBeNull();
  });
});

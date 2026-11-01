import { describe, it, expect } from "vitest";
import { planToppingGroupFixes, planToppingRefFixes, toppingGroupFixUpdates, toppingRefFixUpdates, toppingRefsToNames } from "../lib/topping-refs";

const products = [
  { id: "-NgrabUp5k", name: "Tăng giá Grab 5K", isTopping: true, storeCode: "TRAM01" },
  { id: "-NgrabUp10k", name: "Tăng giá Grab 10K", isTopping: true, storeCode: "TRAM01" },
  { id: "Trân châu đen", name: "Trân châu đen", isTopping: true, storeCode: "TRAM01" },
  { id: "-Nother", name: "Tăng giá Grab 5K", isTopping: true, storeCode: "TRAM02" },
];

describe("topping cho nhóm món lưu bằng TÊN (app cũ đọc được)", () => {
  it("khóa → tên; tên giữ nguyên; mã không còn món bỏ; bỏ trùng", () => {
    expect(toppingRefsToNames(["-NgrabUp5k", "-NgrabUp10k", "Trân châu đen", "-NdaXoa123", "tăng giá grab 5k"], products)).toEqual([
      "Tăng giá Grab 5K",
      "Tăng giá Grab 10K",
      "Trân châu đen",
    ]);
  });
  it("chỉ sửa nhóm đang lưu mã; tra món chi nhánh mình trước, rồi chi nhánh khác", () => {
    const fixes = planToppingRefFixes(
      [
        { id: "Món Grab", name: "Món Grab", storeCode: "TRAM01", allowedToppingIds: ["-NgrabUp5k", "-NgrabUp10k"] },
        { id: "Trà", name: "Trà", storeCode: "TRAM01", allowedToppingIds: ["Trân châu đen"] },
        { id: "Món Grab", name: "Món Grab", storeCode: "TRAM02", allowedToppingIds: ["-NgrabUp5k"] },
      ],
      products
    );
    expect(fixes.map((f) => [f.storeCode, f.categoryName, f.to])).toEqual([
      ["TRAM01", "Món Grab", ["Tăng giá Grab 5K", "Tăng giá Grab 10K"]],
      ["TRAM02", "Món Grab", ["Tăng giá Grab 5K"]], // khóa của chi nhánh khác → lấy tên từ chi nhánh đó
    ]);
    expect(toppingRefFixUpdates(fixes)).toEqual({
      "stores/TRAM01/categories/Món Grab/allowedToppingIds": ["Tăng giá Grab 5K", "Tăng giá Grab 10K"],
      "stores/TRAM02/categories/Món Grab/allowedToppingIds": ["Tăng giá Grab 5K"],
    });
  });
  it("mã không còn món ở bất kỳ chi nhánh nào → bỏ; hết topping thì xóa trường", () => {
    const fixes = planToppingRefFixes([{ id: "X", name: "X", storeCode: "TRAM01", allowedToppingIds: ["-NdaXoa123"] }], products);
    expect(toppingRefFixUpdates(fixes)).toEqual({ "stores/TRAM01/categories/X/allowedToppingIds": null });
  });
});

describe("Danh mục note & topping: dòng topping mang tên là mã", () => {
  const prods = [
    { id: "-P4Z0_f5RonFG_cqRezZ", name: "Tăng giá Grab 5K", price: 5000, isTopping: true, storeCode: "TRAM01" },
    { id: "-P4Z0iz0eL80vnzpmEl8", name: "Tăng giá Grab 10K", price: 10000, isTopping: true, storeCode: "TRAM01" },
  ];
  it("đổi mã → tên + giá thật; dòng tên thường giữ nguyên; mã mồ côi bỏ; nhóm không có mã thì không đụng", () => {
    const fixes = planToppingGroupFixes(
      [
        {
          id: "legacy_cat_TRA", name: "Topping - TRÀ TRÁI CÂY",
          items: [
            { id: "t1", name: "Thạch dừa", price: 5000 },
            { id: "t2", name: "-P4Z0_f5RonFG_cqRezZ", price: 5000 },
            { id: "t3", name: "-P4Z0iz0eL80vnzpmEl8", price: 5000 },
            { id: "t4", name: "-NdaXoaMon123", price: 5000 },
          ],
        },
        { id: "ok", name: "OK", items: [{ id: "t1", name: "Trân châu đen", price: 5000 }] },
      ],
      prods
    );
    expect(fixes).toHaveLength(1);
    expect(fixes[0].changed).toBe(3);
    expect(fixes[0].items).toEqual([
      { id: "t1", name: "Thạch dừa", price: 5000 },
      { id: "t2", name: "Tăng giá Grab 5K", price: 5000 },
      { id: "t3", name: "Tăng giá Grab 10K", price: 10000 },
    ]);
    expect(Object.keys(toppingGroupFixUpdates("TRAM01", fixes))).toEqual(["stores/TRAM01/topping_groups/legacy_cat_TRA/items"]);
  });
});

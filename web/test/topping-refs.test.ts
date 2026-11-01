import { describe, it, expect } from "vitest";
import { planToppingRefFixes, toppingRefFixUpdates, toppingRefsToNames } from "../lib/topping-refs";

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

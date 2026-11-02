import { describe, it, expect } from "vitest";
import { findDuplicateTarget, mergedProduct } from "./productDedupeLogic";

describe("productDedupe", () => {
  const products = {
    "-P3oSUAjaThmkd28gdGz": { name: "Trà Olong - Xoài", price: 32000, id: "DR3" },
    "Trà Olong - Xoài": { name: "Trà Olong - Xoài", price: 35000, id: "DR3" },
    "Trà Olong - Đào": { name: "Trà Olong - Đào", price: 32000 },
  };
  it("app lưu món sao chép → tìm đúng món cũ cùng tên", () => {
    expect(findDuplicateTarget("Trà Olong - Xoài", products["Trà Olong - Xoài"], products)).toBe("-P3oSUAjaThmkd28gdGz");
  });
  it("món mới thật / nhiều món cùng tên → không gộp", () => {
    expect(findDuplicateTarget("Trà Olong - Đào", products["Trà Olong - Đào"], products)).toBeNull();
    const three = { ...products, x: { name: "Trà Olong - Xoài" } };
    expect(findDuplicateTarget("Trà Olong - Xoài", products["Trà Olong - Xoài"], three)).toBeNull();
  });
  it("gộp: lấy dữ liệu mới, giữ id cũ", () => {
    expect(mergedProduct({ name: "A", price: 1, id: 7, code: "C" }, { name: "A", price: 2, id: 99 })).toEqual({ name: "A", price: 2, id: 7, code: "C" });
    expect(mergedProduct({ name: "A", price: 1 }, { name: "A", price: 2, id: 99 })).toEqual({ name: "A", price: 2 });
  });
});

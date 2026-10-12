import { describe, it, expect } from "vitest";
import {
  buildCopyAuditEntry,
  buildCopyPlan,
  canCopyMenu,
  chunkUpdates,
  normalizeName,
  sanitizeKey,
  summarizePlan,
  type MenuSnapshot,
} from "../lib/menu-copy";

const empty: MenuSnapshot = { products: {}, categories: {}, notes: {} };
const noteKey = (i: number) => `n${i}`;

const source: MenuSnapshot = {
  products: {
    "Cà phê sữa": { id: 1, name: "Cà phê sữa", code: "CF1", price: 25000, category: "Cà phê", sizes: { S: 0, L: 5000 }, allowedToppings: ["Trân châu"], hasIceSugarOptions: true, imageBase64: "AAA", imageResourceName: "cf.jpg" },
    "Trà đào": { id: 2, name: "Trà đào", price: 30000, category: "Trà", unit: "Ly" },
    "Trân châu": { id: 3, name: "Trân châu", price: 5000, category: "Topping", isTopping: true },
  },
  categories: { "Cà phê": { name: "Cà phê", allowedToppingIds: ["Trân châu"] }, Trà: { name: "Trà" }, Topping: "Topping" },
  notes: { a: { text: "Ít ngọt" }, b: "Nhiều đá" },
};

describe("chuẩn hóa tên", () => {
  it("bỏ dấu tiếng Việt, đ, hoa thường, khoảng trắng", () => {
    expect(normalizeName("  Cà   Phê  Sữa Đá ")).toBe("ca phe sua da");
    expect(normalizeName("TRÀ ĐÀO")).toBe(normalizeName("tra dao"));
    expect(normalizeName("Bạc-xỉu!")).toBe("bac xiu");
    expect(normalizeName(null)).toBe("");
  });
  it("khóa RTDB hợp lệ", () => {
    expect(sanitizeKey("A.B/C#D$E[F]")).toBe("A_B_C_D_E_F_");
  });
});

describe("kế hoạch sao chép: đích trống", () => {
  const plan = buildCopyPlan({ source, target: empty, options: { conflict: "skip" }, noteKey });
  it("giữ id/khóa nguồn khi đích trống và tạo đủ nhóm + ghi chú", () => {
    expect(plan.counts).toMatchObject({ create: 3, skip: 0, overwrite: 0, duplicate: 0, categories: 3, notes: 2 });
    expect(plan.idMap).toEqual({ "1": 1, "2": 2, "3": 3 });
    expect(plan.updates["products/Cà phê sữa"]).toMatchObject({ id: 1, price: 25000, imageBase64: "AAA", sizes: { S: 0, L: 5000 } });
    expect(plan.updates["categories/Cà phê"]).toEqual({ name: "Cà phê", allowedToppingIds: ["Trân châu"] });
    expect(plan.updates["categories/Topping"]).toEqual({ name: "Topping" });
    expect(plan.updates["product_notes/n0"]).toEqual({ text: "Ít ngọt" });
  });
  it("không có đường dẫn xóa (chỉ giá trị ghi)", () => {
    expect(Object.values(plan.updates).every((v) => v !== null)).toBe(true);
  });
});

describe("cấp id không va chạm", () => {
  const target: MenuSnapshot = {
    products: {
      "Bạc xỉu": { id: 1, name: "Bạc xỉu", price: 20000, category: "Cà phê" },
      "7": { id: 7, name: "Sinh tố", price: 40000, category: "Sinh tố" },
    },
    categories: { "Cà phê": { name: "Cà phê" } },
    notes: {},
  };
  const plan = buildCopyPlan({ source, target, noteKey });
  it("món mới nhận id sau id lớn nhất ở đích, không trùng", () => {
    const ids = plan.productOps.map((p) => p.targetId);
    expect(ids).toEqual([8, 9, 10]);
    expect(new Set(ids).size).toBe(3);
    expect(plan.idMap).toEqual({ "1": 8, "2": 9, "3": 10 });
    const keys = plan.productOps.map((p) => p.targetKey!);
    expect(keys.every((k) => !(k in target.products))).toBe(true);
  });
  it("khóa đích trùng khóa có sẵn thì thêm hậu tố", () => {
    const t: MenuSnapshot = { ...empty, products: { "Trà đào": { id: 50, name: "Trà đào ", price: 1, category: "Khác" } } };
    const p = buildCopyPlan({ source: { ...empty, products: { "Trà đào": { id: 2, name: "Trà đào", price: 30000, category: "Trà" } } }, target: t });
    // khác nhóm → không phải trùng món, nhưng khóa trùng → đổi khóa
    expect(p.productOps[0].action).toBe("create");
    expect(p.productOps[0].targetKey).not.toBe("Trà đào");
    expect(p.productOps[0].targetId).toBe(51);
  });
  it("khóa số của nguồn thành khóa số = id mới", () => {
    const s: MenuSnapshot = { ...empty, products: { "5": { id: 5, name: "X", price: 1, category: "A" } } };
    const t: MenuSnapshot = { ...empty, products: { "5": { id: 5, name: "Y", price: 1, category: "B" } } };
    const p = buildCopyPlan({ source: s, target: t });
    expect(p.productOps[0].targetId).toBe(6);
    expect(p.productOps[0].targetKey).toBe("6");
  });
});

describe("nhóm thiếu / khác dấu", () => {
  it("quy đổi nhóm đích có sẵn khác dấu/hoa thường, chỉ tạo nhóm thật sự thiếu", () => {
    const target: MenuSnapshot = { ...empty, categories: { TRA: { name: "TRA" } } };
    const plan = buildCopyPlan({ source, target, noteKey });
    expect(plan.updates["products/Trà đào"]).toMatchObject({ category: "TRA" });
    expect(plan.categoryOps.filter((c) => c.action === "create").map((c) => c.name).sort()).toEqual(["Cà phê", "Topping"]);
    expect(plan.updates["categories/Trà"]).toBeUndefined();
  });
  it("không bật 'sao chép nhóm' thì không tạo nhóm", () => {
    const plan = buildCopyPlan({ source, target: empty, options: { copyCategories: false } });
    expect(Object.keys(plan.updates).some((k) => k.startsWith("categories/"))).toBe(false);
    expect(plan.updates["products/Trà đào"]).toMatchObject({ category: "Trà" });
  });
});

describe("xung đột", () => {
  const target: MenuSnapshot = {
    products: { "ca phe sua": { id: 4, name: "CA PHE SUA", price: 99000, costPrice: 1234, category: "CÀ PHÊ" } },
    categories: { "CÀ PHÊ": { name: "CÀ PHÊ" } },
    notes: { x: { text: "ít ngọt" } },
  };
  it("khớp theo tên + nhóm chuẩn hóa (không phân biệt dấu)", () => {
    const skip = buildCopyPlan({ source, target, options: { conflict: "skip" }, noteKey });
    expect(skip.counts).toMatchObject({ skip: 1, create: 2 });
    expect(skip.productOps.find((p) => p.action === "skip")?.targetKey).toBe("ca phe sua");
    expect(skip.counts.notes).toBe(1); // "Ít ngọt" đã có
    expect(skip.updates["products/ca phe sua"]).toBeUndefined();
  });
  it("ghi đè giữ khóa + id đích, chỉ ghi từng trường (không xóa trường đích)", () => {
    const p = buildCopyPlan({ source, target, options: { conflict: "overwrite" } });
    expect(p.counts).toMatchObject({ overwrite: 1, create: 2, skip: 0 });
    expect(p.updates["products/ca phe sua/price"]).toBe(25000);
    expect(p.updates["products/ca phe sua/id"]).toBe(4);
    expect(p.updates["products/ca phe sua/category"]).toBe("CÀ PHÊ");
    expect(p.updates["products/ca phe sua/costPrice"]).toBeUndefined(); // nguồn không có → giữ giá vốn đích
    expect(p.idMap["1"]).toBe(4);
    expect(p.updates["products/ca phe sua"]).toBeUndefined();
  });
  it("tạo bản sao thêm hậu tố, id/khóa mới, bỏ mã SKU", () => {
    const p = buildCopyPlan({ source, target, options: { conflict: "duplicate" } });
    const dup = p.productOps.find((o) => o.action === "duplicate")!;
    expect(dup.targetId).not.toBe(4);
    expect(p.updates[`products/${dup.targetKey}`]).toMatchObject({ name: "Cà phê sữa (bản sao)", code: "", price: 25000 });
    expect(p.counts.duplicate).toBe(1);
    // Chạy lại lần 2 trên đích đã có bản sao → hậu tố 2
    const t2: MenuSnapshot = { ...target, products: { ...target.products, [dup.targetKey!]: p.updates[`products/${dup.targetKey}`] } };
    const p2 = buildCopyPlan({ source, target: t2, options: { conflict: "duplicate" } });
    const dup2 = p2.productOps.find((o) => o.action === "duplicate" && o.sourceKey === "Cà phê sữa")!;
    expect(p2.updates[`products/${dup2.targetKey}`]).toMatchObject({ name: "Cà phê sữa (bản sao 2)" });
  });
  it("hai món nguồn cùng tên+nhóm chỉ lấy một", () => {
    const s: MenuSnapshot = { ...empty, products: { a: { id: 1, name: "Trà", price: 1, category: "T" }, b: { id: 2, name: "TRA", price: 2, category: "t" } } };
    const p = buildCopyPlan({ source: s, target: empty });
    expect(p.counts).toMatchObject({ create: 1, skip: 1 });
  });
});

describe("phạm vi chọn và tùy chọn", () => {
  it("chọn theo nhóm hoặc theo khóa món", () => {
    const byCat = buildCopyPlan({ source, target: empty, selection: { categories: ["tra"] } });
    expect(byCat.productOps.map((p) => p.name)).toEqual(["Trà đào"]);
    const byKey = buildCopyPlan({ source, target: empty, selection: { productKeys: ["Trân châu"] } });
    expect(byKey.productOps.map((p) => p.name)).toEqual(["Trân châu"]);
    const both = buildCopyPlan({ source, target: empty, selection: { categories: ["Trà"], productKeys: ["Trân châu"] } });
    expect(both.productOps).toHaveLength(2);
  });
  it("tắt ảnh / tùy chọn / ghi chú", () => {
    const p = buildCopyPlan({ source, target: empty, options: { copyImages: false, copyOptions: false, copyNotes: false } });
    const cf = p.updates["products/Cà phê sữa"] as Record<string, unknown>;
    expect(cf.imageBase64).toBeUndefined();
    expect(cf.imageResourceName).toBeUndefined();
    expect(cf.sizes).toBeUndefined();
    expect(cf.allowedToppings).toBeUndefined();
    expect(cf.hasIceSugarOptions).toBeUndefined();
    expect(cf.price).toBe(25000);
    expect(p.counts.notes).toBe(0);
  });
  it("dữ liệu dạng mảng / null không làm hỏng", () => {
    const s = { products: [null, { id: 1, name: "A", price: 1, category: "C" }], categories: null, notes: undefined } as unknown as MenuSnapshot;
    const p = buildCopyPlan({ source: s, target: empty });
    expect(p.counts.create).toBe(1);
  });
});

describe("nhiều chi nhánh đích, lô và nhật ký", () => {
  it("mỗi đích có kế hoạch/id độc lập", () => {
    const t1: MenuSnapshot = { ...empty, products: { x: { id: 100, name: "X", price: 1, category: "K" } } };
    const p1 = buildCopyPlan({ source, target: t1, noteKey });
    const p2 = buildCopyPlan({ source, target: empty, noteKey });
    expect(p1.productOps.map((o) => o.targetId)).toEqual([101, 102, 103]);
    expect(p2.productOps.map((o) => o.targetId)).toEqual([1, 2, 3]);
  });
  it("chia lô ≤ giới hạn", () => {
    const u: Record<string, unknown> = {};
    for (let i = 0; i < 905; i++) u[`products/p${i}`] = { i };
    const chunks = chunkUpdates(u, 400);
    expect(chunks.map((c) => Object.keys(c).length)).toEqual([400, 400, 105]);
    expect(chunkUpdates({}, 400)).toEqual([]);
  });
  it("nhật ký COPY_MENU có trường cấu trúc và qua được validate rules", () => {
    const plan = buildCopyPlan({ source, target: empty, noteKey });
    const e = buildCopyAuditEntry({ sourceStore: "TRAM01", targetStore: "TRAM02", summary: summarizePlan(plan), actor: { username: "admin", role: "owner" }, now: 123 });
    expect(e).toMatchObject({ action: "COPY_MENU", details: "Sao chép 3 món từ TRAM01 sang TRAM02", sourceStore: "TRAM01", targetStore: "TRAM02", created: 3, overwritten: 0, skipped: 0, timestamp: 123, username: "admin" });
  });
});

describe("quyền", () => {
  const yes = () => true;
  const no = () => false;
  it("Chủ / Quản lý có quyền sửa thực đơn mới được sao chép", () => {
    expect(canCopyMenu({ roleId: "ROLE_OWNER" }, yes)).toBe(true);
    expect(canCopyMenu({ roleId: "manager_1" }, yes)).toBe(true);
    expect(canCopyMenu({ roleId: "manager_1" }, no)).toBe(false);
    expect(canCopyMenu({ roleId: "cashier" }, yes)).toBe(false);
    expect(canCopyMenu({ roleId: "x", isRootOwner: true }, no)).toBe(true);
    expect(canCopyMenu(null, yes)).toBe(false);
  });
});

describe("danh mục note & topping", () => {
  const src: MenuSnapshot = {
    products: {
      "Trà A": { id: 1, name: "Trà A", price: 1, category: "Trà", noteGroupIds: ["n1"], toppingGroupIds: ["__none__"] },
      "Bánh B": { id: 2, name: "Bánh B", price: 1, category: "Bánh", noteGroupIds: ["ghost"] },
    },
    categories: { Trà: { name: "Trà", noteGroupIds: ["n1"], toppingGroupIds: ["t1", "t2"] }, Bánh: { name: "Bánh" } },
    notes: {},
    noteGroups: { n1: { name: "Đồ uống", items: [{ id: "a", text: "Ít đá" }] } },
    toppingGroups: {
      t1: { name: "Topping trà", items: [{ id: "1", name: "Trân châu", price: 5000 }] },
      t2: { name: "Sốt", multi: false, items: [{ id: "2", name: "Dâu", price: 0 }] },
    },
  };

  it("đích trống: sao chép nhóm, giữ id nguồn, đổi id trong phần gắn", () => {
    const plan = buildCopyPlan({ source: src, target: empty, noteKey });
    expect(plan.groupsToAdd).toBe(3);
    expect((plan.updates["note_groups/n1"] as { name: string }).name).toBe("Đồ uống");
    expect(plan.updates["categories/Trà"]).toEqual({ name: "Trà", noteGroupIds: ["n1"], toppingGroupIds: ["t1", "t2"] });
    const a = plan.updates["products/Trà A"] as Record<string, unknown>;
    expect(a.noteGroupIds).toEqual(["n1"]);
    expect(a.toppingGroupIds).toEqual(["__none__"]);
    // id nhóm không còn ở nguồn → "không có" (không rơi về kế thừa)
    expect((plan.updates["products/Bánh B"] as Record<string, unknown>).noteGroupIds).toEqual(["__none__"]);
  });

  it("đích đã có nhóm trùng tên: dùng lại, không ghi đè; trùng id khác tên thì cấp id mới", () => {
    const target: MenuSnapshot = { ...empty, noteGroups: { x9: { name: "ĐỒ UỐNG", items: [] } }, toppingGroups: { t1: { name: "Khác hẳn", items: [] } } };
    const plan = buildCopyPlan({ source: src, target, noteKey });
    expect("note_groups/n1" in plan.updates).toBe(false);
    expect((plan.updates["products/Trà A"] as Record<string, unknown>).noteGroupIds).toEqual(["x9"]);
    expect("topping_groups/t1" in plan.updates).toBe(false);
    expect(plan.updates["topping_groups/t1_2"]).toBeTruthy();
    expect((plan.updates["categories/Trà"] as Record<string, unknown>).toppingGroupIds).toEqual(["t1_2", "t2"]);
  });

  it("nhóm món có sẵn ở đích chỉ bổ sung phần gắn khi đích chưa có; tắt copyCatalog thì bỏ hết", () => {
    const plan = buildCopyPlan({ source: src, target: { ...empty, categories: { Trà: { name: "Trà" } } }, noteKey });
    expect(plan.updates["categories/Trà/noteGroupIds"]).toEqual(["n1"]);
    const off = buildCopyPlan({ source: src, target: empty, options: { copyCatalog: false }, noteKey });
    expect(off.groupsToAdd).toBe(0);
    expect(Object.keys(off.updates).some((k) => k.startsWith("note_groups") || k.startsWith("topping_groups"))).toBe(false);
    expect("noteGroupIds" in (off.updates["products/Trà A"] as object)).toBe(false);
    expect("noteGroupIds" in (off.updates["categories/Trà"] as object)).toBe(false);
  });
});

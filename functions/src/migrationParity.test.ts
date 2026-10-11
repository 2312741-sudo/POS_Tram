import { describe, it, expect } from "vitest";
import { createRequire } from "module";
import { planMigration } from "./sharedLoyalty";

// scripts/migrate_shared_loyalty/plan.js là bản JS độc lập của planMigration: hai bản phải cho cùng kết quả
const req = createRequire(import.meta.url);
const js = req("../../scripts/migrate_shared_loyalty/plan.js");

describe("scripts/migrate_shared_loyalty/plan.js khớp functions/src/sharedLoyalty.ts", () => {
  const raw = {
    A: {
      a1: { ho_ten: "An", so_dien_thoai: "0912345678", diem_hien_tai: 30, totalPoints: 100, createdAt: 9 },
      a2: { ho_ten: "Không SĐT", phone: "", currentPoints: 5 },
      bad: "x",
    },
    B: {
      b1: { name: "An B", phone: "+84912345678", diemHienTai: 80, tongDiem: 500 },
      b2: { ho_ten: "Bình", so_dien_thoai: "0900000002", currentPoints: 4, totalPoints: 2 },
    },
  } as Record<string, Record<string, unknown>>;

  const sources = Object.entries(raw).flatMap(([s, cs]) => Object.entries(cs).map(([id, v]) => js.readSource(s, id, v))).filter(Boolean);

  it("cùng nhóm, cùng tổng", () => {
    const a = js.planMigration(sources);
    const b = planMigration(sources);
    expect(a.totals).toEqual(b.totals);
    expect(a.groups.map((g: { memberKey: string; points: number; totalPoints: number }) => [g.memberKey, g.points, g.totalPoints])).toEqual(
      b.groups.map((g) => [g.memberKey, g.points, g.totalPoints])
    );
    expect(a.localOnly.map((g: { memberKey: string }) => g.memberKey)).toEqual(b.localOnly.map((g) => g.memberKey));
    expect(a.totals.sharedPoints).toBe(a.totals.branchPoints);
  });

  it("totalPoints không bao giờ nhỏ hơn điểm hiện tại; bỏ node không phải object", () => {
    expect(sources).toHaveLength(4);
    const b2 = sources.find((s: { customerId: string }) => s.customerId === "b2");
    expect(b2.totalPoints).toBe(4);
  });

  it("buildWrites ghi bản ghi + sổ cái đầu kỳ cho từng nguồn + cache điểm", () => {
    const g = js.planMigration(sources).groups.find((x: { memberKey: string }) => x.memberKey === "0912345678");
    const w = js.buildWrites(g, 1000, "migration");
    expect(w["loyalty_members/0912345678"]).toMatchObject({ points: 110, totalPoints: 600, branches: { A: { a1: true }, B: { b1: true } } });
    expect(Object.keys(w).filter((k) => k.startsWith("loyalty_ledger/0912345678/opening_"))).toHaveLength(2);
    expect(w["stores/A/customers/a1/diem_hien_tai"]).toBe(110);
    expect(w["stores/B/customers/b1/totalPoints"]).toBe(600);
  });
});

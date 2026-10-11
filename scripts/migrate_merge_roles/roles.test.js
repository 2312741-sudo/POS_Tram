const test = require("node:test");
const assert = require("node:assert");
const { normalizeRoleId, planUserUpdate, planRolesMerge } = require("./roles");

test("normalizeRoleId gộp Quản lý 1/2 và Thu ngân/Phục vụ", () => {
  for (const r of ["manager", "manager_1", "manager_2", "ROLE_MANAGER_1", "ROLE_MANAGER_2", "Manager-1"]) assert.strictEqual(normalizeRoleId(r), "ROLE_MANAGER");
  for (const r of ["cashier", "ROLE_CASHIER", "employee", "waiter", "ROLE_WAITER", "staff"]) assert.strictEqual(normalizeRoleId(r), "ROLE_STAFF");
  assert.strictEqual(normalizeRoleId("owner"), "owner");
  assert.strictEqual(normalizeRoleId("ROLE_KITCHEN"), "ROLE_KITCHEN");
});

test("planUserUpdate: đổi roleId + role, bỏ qua chủ gốc / bếp / đã chuẩn", () => {
  assert.deepStrictEqual(planUserUpdate({ roleId: "manager_2", role: "manager_2" }), { roleId: "ROLE_MANAGER", role: "ROLE_MANAGER" });
  assert.deepStrictEqual(planUserUpdate({ roleId: "ROLE_WAITER" }), { roleId: "ROLE_STAFF" });
  assert.strictEqual(planUserUpdate({ roleId: "ROLE_MANAGER" }), null);
  assert.strictEqual(planUserUpdate({ roleId: "ROLE_KITCHEN" }), null);
  assert.strictEqual(planUserUpdate({ roleId: "manager_1", isRootOwner: true }), null);
  assert.strictEqual(planUserUpdate(null), null);
});

test("planRolesMerge: hợp quyền các bản ghi cũ vào bản ghi chuẩn", () => {
  const { writes, removes } = planRolesMerge({
    ROLE_MANAGER_1: { permissions: ["A", "B"] },
    ROLE_MANAGER_2: { permissions: ["B", "C"] },
    ROLE_CASHIER: { permissions: ["X"] },
    ROLE_WAITER: { permissions: { Y: true } },
    ROLE_KITCHEN: { permissions: ["K"] },
  });
  assert.deepStrictEqual(writes.ROLE_MANAGER.permissions, ["A", "B", "C"]);
  assert.deepStrictEqual(writes.ROLE_STAFF.permissions, ["X", "Y"]);
  assert.deepStrictEqual(removes.sort(), ["ROLE_CASHIER", "ROLE_MANAGER_1", "ROLE_MANAGER_2", "ROLE_WAITER"]);
  assert.ok(!("ROLE_KITCHEN" in writes));
});

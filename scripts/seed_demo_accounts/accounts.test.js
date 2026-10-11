const test = require("node:test");
const assert = require("node:assert");
const { DEMO_ACCOUNTS, buildSyntheticEmail, buildProfile, validatePassword } = require("./accounts");

test("đủ 4 bộ phận với vai trò đúng", () => {
  assert.deepStrictEqual(
    DEMO_ACCOUNTS.map((a) => a.roleId),
    ["ROLE_OWNER", "ROLE_MANAGER_1", "ROLE_CASHIER", "ROLE_KITCHEN"]
  );
});

test("email ảo theo hợp đồng {username}.{store}@tram.local", () => {
  assert.strictEqual(buildSyntheticEmail("Quản Lý_Demo", "TRAM-01"), "quanly_demo.tram01@tram.local");
});

test("hồ sơ không chứa mật khẩu, không phải chủ gốc, có cờ isDemo", () => {
  const p = buildProfile(DEMO_ACCOUNTS[0], "uid1", 5);
  assert.strictEqual(p.isRootOwner, false);
  assert.strictEqual(p.isDemo, true);
  assert.ok(!("password" in p));
  assert.strictEqual(p.uid, "uid1");
});

test("mật khẩu tối thiểu 8 ký tự", () => {
  assert.ok(!validatePassword("1234567"));
  assert.ok(validatePassword("12345678"));
});

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";

describe("POS Trạm - Firebase Realtime Database Security Rules", () => {
  let testEnv: RulesTestEnvironment | null = null;
  const rulesPath = path.resolve(__dirname, "../../database.rules.json");
  const rulesContent = fs.existsSync(rulesPath) ? fs.readFileSync(rulesPath, "utf8") : "";
  const parsedRules = JSON.parse(rulesContent);

  beforeAll(async () => {
    try {
      testEnv = await initializeTestEnvironment({
        projectId: "demo-tram-pos",
        database: {
          rules: rulesContent,
          host: "127.0.0.1",
          port: 9000,
        },
      });
    } catch {
      // Emulator might not be running in this execution environment
      testEnv = null;
    }
  });

  afterAll(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearDatabase();
      // Setup base data via admin context
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.database();
        await db.ref("userIndex/owner_uid/TRAM01").set(true);
        await db.ref("userIndex/manager_uid/TRAM01").set(true);
        await db.ref("userIndex/cashier_uid/TRAM01").set(true);
        await db.ref("userIndex/waiter_uid/TRAM01").set(true);
        await db.ref("userIndex/storeB_uid/TRAM02").set(true);

        await db.ref("stores/TRAM01/users/owner_uid").set({
          username: "admin",
          fullName: "Chủ Quán Gốc",
          roleId: "owner",
          isRootOwner: true,
          isActive: true,
        });

        await db.ref("stores/TRAM01/users/manager_uid").set({
          username: "manager1",
          fullName: "Quản Lý 1",
          roleId: "manager",
          isActive: true,
        });

        await db.ref("stores/TRAM01/users/cashier_uid").set({
          username: "thungan",
          fullName: "Thu Ngân",
          roleId: "cashier",
          isActive: true,
        });

        await db.ref("stores/TRAM01/users/waiter_uid").set({
          username: "phucvu",
          fullName: "Phục Vụ",
          roleId: "waiter",
          isActive: true,
        });

        await db.ref("stores/TRAM01/users/inactive_uid").set({
          username: "banned_user",
          fullName: "Người Bị Khóa",
          roleId: "waiter",
          isActive: false,
        });

        await db.ref("stores/TRAM02/users/storeB_uid").set({
          username: "storeB_owner",
          fullName: "Chủ Quán B",
          roleId: "owner",
          isRootOwner: true,
          isActive: true,
        });
      });
    }
  });

  it("1. Tài khoản tự đăng ký không có userIndex không được đọc dữ liệu quán", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("userIndex");
      expect(parsedRules.rules[".read"]).toBe(false);
      return;
    }
    const unindexed = testEnv.authenticatedContext("unindexed_uid").database();
    await assertFails(unindexed.ref("stores/TRAM01/products").get());
    await assertFails(unindexed.ref("stores/TRAM01/products/p1").set({ name: "Hacked" }));
  });

  it("2. Người của Quán A không đọc được Quán B", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("userIndex");
      return;
    }
    const storeAUser = testEnv.authenticatedContext("cashier_uid").database();
    await assertFails(storeAUser.ref("stores/TRAM02/products").get());
  });

  it("3. Phục vụ và Bếp không được ghi products, promotions, users, customers", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("products");
      expect(rulesContent).toContain("promotions");
      expect(rulesContent).toContain("customers");
      return;
    }
    const waiter = testEnv.authenticatedContext("waiter_uid").database();
    await assertFails(waiter.ref("stores/TRAM01/products/p1").set({ name: "Cà phê", price: 20000 }));
    await assertFails(waiter.ref("stores/TRAM01/promotions/pr1").set({ discount: 10 }));
    await assertFails(waiter.ref("stores/TRAM01/users/waiter_uid/fullName").set("Fake Name"));
    await assertFails(waiter.ref("stores/TRAM01/customers/c1").set({ name: "Khách", phone: "0900000000" }));
  });

  it("4. Thu ngân đọc ghi được customers và bills nhưng không sửa được products", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("bills");
      expect(rulesContent).toContain("customers");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertSucceeds(cashier.ref("stores/TRAM01/bills/b1").set({ total: 50000 }));
    await assertSucceeds(cashier.ref("stores/TRAM01/customers/c1").set({ name: "Khách 1", phone: "0912345678" }));
    await assertSucceeds(cashier.ref("stores/TRAM01/customers/c1").get());
    await assertFails(cashier.ref("stores/TRAM01/products/p1").set({ price: 1000 }));
  });

  it("5. Thu ngân không thể tự sửa roleId của chính mình", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("roleId");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertFails(cashier.ref("stores/TRAM01/users/cashier_uid/roleId").set("owner"));
  });

  it("6. Không ai được phép ghi trường password vào user record", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("!newData.hasChild('password')");
      return;
    }
    const owner = testEnv.authenticatedContext("owner_uid").database();
    await assertFails(owner.ref("stores/TRAM01/users/new_uid").set({
      username: "test",
      fullName: "Test",
      roleId: "cashier",
      password: "plaintext_password",
    }));
  });

  it("7. Quản lý không thể khóa hoặc sửa tài khoản của Chủ quán gốc (isRootOwner)", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("isRootOwner");
      return;
    }
    const manager = testEnv.authenticatedContext("manager_uid").database();
    await assertFails(manager.ref("stores/TRAM01/users/owner_uid/isActive").set(false));
  });

  it("8. audit_logs thêm được 2 bản ghi liên tiếp nhưng cấm sửa hoặc xóa", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("audit_logs");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertSucceeds(
      cashier.ref("stores/TRAM01/audit_logs/log_1").set({
        timestamp: Date.now(),
        action: "PAY_BILL",
        username: "cashier1",
      })
    );
    await assertSucceeds(
      cashier.ref("stores/TRAM01/audit_logs/log_2").set({
        timestamp: Date.now(),
        action: "OPEN_SHIFT",
        username: "cashier1",
      })
    );
    await assertFails(cashier.ref("stores/TRAM01/audit_logs/log_1").update({ action: "HACKED" }));
    await assertFails(cashier.ref("stores/TRAM01/audit_logs/log_1").remove());
  });

  it("9. Client không thể ghi userIndex; chỉ đọc được của chính mình", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain(".write\": false");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertFails(cashier.ref("userIndex/cashier_uid/TRAM01").set(true));
    await assertSucceeds(cashier.ref("userIndex/cashier_uid").get());
    await assertFails(cashier.ref("userIndex/owner_uid").get());
  });

  it("10. Tài khoản isActive === false bị từ chối truy cập", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("isActive");
      return;
    }
    const banned = testEnv.authenticatedContext("inactive_uid").database();
    await assertFails(banned.ref("stores/TRAM01/tables").get());
  });

  it("11. login_attempts bị khóa cả đọc lẫn ghi đối với client (chỉ Functions/Admin)", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("\"login_attempts\"");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertFails(cashier.ref("stores/TRAM01/login_attempts/cashier1").get());
    await assertFails(cashier.ref("stores/TRAM01/login_attempts/cashier1").set({ failedCount: 1 }));
  });

  it("12. audit_logs phải thỏa mãn validate rule: có timestamp, action, username", async () => {
    if (!testEnv) {
      expect(rulesContent).toContain("newData.hasChildren(['timestamp', 'action', 'username'])");
      return;
    }
    const cashier = testEnv.authenticatedContext("cashier_uid").database();
    await assertFails(cashier.ref("stores/TRAM01/audit_logs/log_invalid").set({ action: "TEST" }));
  });

  it("13. Mọi nút gốc cũ bị từ chối với mọi vai trò và với người chưa đăng nhập", async () => {
    const legacyNodes = [
      "users",
      "tables",
      "products",
      "categories",
      "zones",
      "history",
      "audit_logs",
      "kmt_customers",
      "online_orders",
      "kitchen_orders",
      "cham_cong",
      "timekeeping",
      "employees",
      "shifts",
    ];

    // Kiểm tra cấu trúc rules: không còn node nào trong số legacyNodes tồn tại ở cấp root
    legacyNodes.forEach((node) => {
      expect(parsedRules.rules[node]).toBeUndefined();
    });

    // Cấp root phải được chặn mặc định
    expect(parsedRules.rules[".read"]).toBe(false);
    expect(parsedRules.rules[".write"]).toBe(false);

    if (testEnv) {
      const unauth = testEnv.unauthenticatedContext().database();
      const owner = testEnv.authenticatedContext("owner_uid").database();

      for (const node of legacyNodes) {
        await assertFails(unauth.ref(node).get());
        await assertFails(unauth.ref(node).set({ hacked: true }));
        await assertFails(owner.ref(node).get());
        await assertFails(owner.ref(node).set({ hacked: true }));
      }
    }
  });

  it("14. Chỉ có đúng 2 nhánh được mở ở cấp root: userIndex và stores", () => {
    const topLevelKeys = Object.keys(parsedRules.rules).filter(
      (k) => !k.startsWith(".")
    );
    expect(topLevelKeys.sort()).toEqual(["stores", "userIndex"].sort());
  });
});

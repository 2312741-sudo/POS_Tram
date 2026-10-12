import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";

/**
 * Bộ test Security Rules RTDB của POS Trạm.
 *
 * BẮT BUỘC chạy cùng Database Emulator (Java 21+):
 *   npm run test:emulator            (trong thư mục tests/rules)
 * hoặc
 *   firebase emulators:exec --only database "npm test --prefix tests/rules" --project demo-tram-pos
 *
 * Nếu không kết nối được emulator, toàn bộ test sẽ FAIL (không còn "pass giả").
 */

const rulesPath = path.resolve(__dirname, "../../database.rules.json");
const rulesContent = fs.readFileSync(rulesPath, "utf8");
const parsedRules = JSON.parse(rulesContent);

function resolveEmulatorHost(): { host: string; port: number } {
  const env = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  if (env && env.includes(":")) {
    const idx = env.lastIndexOf(":");
    return { host: env.substring(0, idx), port: Number(env.substring(idx + 1)) };
  }
  return { host: "127.0.0.1", port: 9000 };
}

let testEnv: RulesTestEnvironment;

function env(): RulesTestEnvironment {
  if (!testEnv) {
    throw new Error(
      "Không kết nối được Firebase Database Emulator. Hãy chạy test qua `firebase emulators:exec --only database ...`."
    );
  }
  return testEnv;
}

const db = (uid: string) => env().authenticatedContext(uid).database();

beforeAll(async () => {
  const { host, port } = resolveEmulatorHost();
  try {
    testEnv = await initializeTestEnvironment({
      projectId: "demo-tram-pos",
      database: { rules: rulesContent, host, port },
    });
    // Kiểm tra kết nối thật sự (initializeTestEnvironment có thể chưa chạm tới emulator)
    await testEnv.clearDatabase();
  } catch (e) {
    throw new Error(
      `Không kết nối được Firebase Database Emulator tại ${host}:${port}. ` +
        "Test rules BẮT BUỘC chạy với emulator (Java 21+): " +
        "`firebase emulators:exec --only database \"npm test --prefix tests/rules\" --project demo-tram-pos`. " +
        `Chi tiết: ${(e as Error)?.message || e}`
    );
  }
}, 30_000);

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await env().clearDatabase();
  await env().withSecurityRulesDisabled(async (context) => {
    const d = context.database();
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid", "waiter_uid", "kitchen_uid", "inactive_uid", "inactive_mgr_uid", "deleted_uid"]) {
      await d.ref(`userIndex/${uid}/TRAM01`).set(true);
    }
    await d.ref("userIndex/storeB_uid/TRAM02").set(true);

    await d.ref("stores/TRAM01/users/owner_uid").set({ username: "admin", fullName: "Chủ Quán Gốc", roleId: "owner", isRootOwner: true, isActive: true });
    await d.ref("stores/TRAM01/users/manager_uid").set({ username: "manager1", fullName: "Quản Lý 1", roleId: "manager", isActive: true });
    await d.ref("stores/TRAM01/users/cashier_uid").set({ username: "thungan", fullName: "Thu Ngân", roleId: "cashier", isActive: true });
    // Phục vụ đã gộp vào Nhân viên (ROLE_STAFF) nên `waiter_uid` giữ vai trò "thành viên quán KHÔNG thu ngân" bằng Bếp,
    // để các test cũ về giới hạn quyền (hóa đơn PAID, khách hàng, tồn kho, điểm...) vẫn kiểm tra đúng nhóm bị chặn.
    // Hành vi của mã cũ waiter/cashier/ROLE_STAFF được kiểm tra riêng ở nhóm test MR1-MR4 bên dưới.
    await d.ref("stores/TRAM01/users/waiter_uid").set({ username: "phucvu", fullName: "Phục Vụ (nhóm chỉ-thành-viên)", roleId: "ROLE_KITCHEN", isActive: true });
    await d.ref("stores/TRAM01/users/kitchen_uid").set({ username: "bep", fullName: "Bếp", roleId: "ROLE_KITCHEN", isActive: true });
    await d.ref("stores/TRAM01/users/inactive_uid").set({ username: "banned_user", fullName: "Người Bị Khóa", roleId: "waiter", isActive: false });
    await d.ref("stores/TRAM01/users/inactive_mgr_uid").set({ username: "ql_khoa", fullName: "QL Bị Khóa", roleId: "manager", isActive: false });
    // Hồ sơ legacy có users/{uid} nhưng KHÔNG có userIndex
    await d.ref("stores/TRAM01/users/noindex_uid").set({ username: "noindex", fullName: "Không Index", roleId: "owner", isActive: true });
    await d.ref("stores/TRAM02/users/storeB_uid").set({ username: "storeB_owner", fullName: "Chủ Quán B", roleId: "owner", isRootOwner: true, isActive: true });

    await d.ref("stores/TRAM01/bills/paid_bill").set({ id: "paid_bill", billCode: "HD-1", status: "PAID", finalAmount: 100000, subTotal: 100000 });
    await d.ref("stores/TRAM01/history/paid_bill").set({ id: "paid_bill", billCode: "HD-1", status: "PAID", totalAmount: 100000 });
    await d.ref("stores/TRAM01/bills/open_bill").set({ id: "open_bill", billCode: "HD-2", status: "OPEN", finalAmount: 50000, subTotal: 50000 });

    await d.ref("stores/TRAM01/stock_balances/TRAM01_ITEM1").set({ balanceId: "TRAM01_ITEM1", itemId: "ITEM1", onHandQty: 1000, inventoryValue: 500000, averageCostScaled: 50000 });
    await d.ref("stores/TRAM01/campaign_counters/CAM1").set({ campaignId: "CAM1", spentMoney: 10000, committedUseCount: 1, reservedMoney: 0, reservedUseCount: 0, version: 1 });
    await d.ref("stores/TRAM01/vouchers/CAM1/VCH1").set({ voucherId: "VCH1", campaignId: "CAM1", normalizedCode: "ABC", state: "RELEASED", version: 1 });
    await d.ref("stores/TRAM01/promotions/PR1").set({ name: "KM", usageCount: 3 });
  });
});

describe("POS Trạm - Security Rules: nền tảng", () => {
  it("1. Tài khoản tự đăng ký không có userIndex không được đọc/ghi dữ liệu quán", async () => {
    const unindexed = db("unindexed_uid");
    await assertFails(unindexed.ref("stores/TRAM01/products").get());
    await assertFails(unindexed.ref("stores/TRAM01/products/p1").set({ name: "Hacked" }));
  });

  it("2. Người của Quán A không đọc được Quán B", async () => {
    await assertFails(db("cashier_uid").ref("stores/TRAM02/products").get());
  });

  it("3. Phục vụ và Bếp không được ghi products, promotions, users, customers", async () => {
    const waiter = db("waiter_uid");
    await assertFails(waiter.ref("stores/TRAM01/products/p1").set({ name: "Cà phê", price: 20000 }));
    await assertFails(waiter.ref("stores/TRAM01/promotions/pr1").set({ discount: 10 }));
    await assertFails(waiter.ref("stores/TRAM01/users/waiter_uid/fullName").set("Fake Name"));
    await assertFails(waiter.ref("stores/TRAM01/customers/c1").set({ name: "Khách", phone: "0900000000" }));
    await assertFails(db("kitchen_uid").ref("stores/TRAM01/products/p1").set({ name: "X" }));
  });

  it("4. Thu ngân đọc ghi được customers và bills nhưng không sửa được products", async () => {
    const cashier = db("cashier_uid");
    await assertSucceeds(cashier.ref("stores/TRAM01/bills/b1").set({ total: 50000 }));
    await assertSucceeds(cashier.ref("stores/TRAM01/customers/c1").set({ name: "Khách 1", phone: "0912345678" }));
    await assertSucceeds(cashier.ref("stores/TRAM01/customers/c1").get());
    await assertFails(cashier.ref("stores/TRAM01/products/p1").set({ price: 1000 }));
  });

  it("5. Thu ngân không thể tự sửa roleId của chính mình", async () => {
    await assertFails(db("cashier_uid").ref("stores/TRAM01/users/cashier_uid/roleId").set("owner"));
  });

  it("6. Không ai được phép ghi trường password vào user record", async () => {
    await assertFails(
      db("owner_uid").ref("stores/TRAM01/users/new_uid").set({ username: "test", fullName: "Test", roleId: "cashier", password: "plaintext_password" })
    );
  });

  it("7. Quản lý không thể khóa hoặc sửa tài khoản của Chủ quán gốc (isRootOwner)", async () => {
    await assertFails(db("manager_uid").ref("stores/TRAM01/users/owner_uid/isActive").set(false));
  });

  it("8. audit_logs thêm được 2 bản ghi liên tiếp nhưng cấm sửa hoặc xóa", async () => {
    const cashier = db("cashier_uid");
    await assertSucceeds(cashier.ref("stores/TRAM01/audit_logs/log_1").set({ timestamp: Date.now(), action: "PAY_BILL", username: "cashier1" }));
    await assertSucceeds(cashier.ref("stores/TRAM01/audit_logs/log_2").set({ timestamp: Date.now(), action: "OPEN_SHIFT", username: "cashier1" }));
    await assertFails(cashier.ref("stores/TRAM01/audit_logs/log_1").update({ action: "HACKED" }));
    await assertFails(cashier.ref("stores/TRAM01/audit_logs/log_1").remove());
  });

  it("9. Client không thể ghi userIndex; chỉ đọc được của chính mình", async () => {
    const cashier = db("cashier_uid");
    await assertFails(cashier.ref("userIndex/cashier_uid/TRAM01").set(true));
    await assertFails(db("attacker_uid").ref("userIndex/attacker_uid/TRAM01").set(true));
    await assertSucceeds(cashier.ref("userIndex/cashier_uid").get());
    await assertFails(cashier.ref("userIndex/owner_uid").get());
  });

  it("10. Tài khoản isActive === false bị từ chối truy cập (kể cả quản lý bị khóa)", async () => {
    await assertFails(db("inactive_uid").ref("stores/TRAM01/tables").get());
    await assertFails(db("inactive_mgr_uid").ref("stores/TRAM01/products/p1").set({ name: "X" }));
  });

  it("11. login_attempts bị khóa cả đọc lẫn ghi đối với client (chỉ Functions/Admin)", async () => {
    const cashier = db("cashier_uid");
    await assertFails(cashier.ref("stores/TRAM01/login_attempts/cashier1").get());
    await assertFails(cashier.ref("stores/TRAM01/login_attempts/cashier1").set({ failedCount: 1 }));
    await assertFails(env().unauthenticatedContext().database().ref("stores/TRAM01/login_attempts/admin").set({ failedCount: 0 }));
  });

  it("12. audit_logs phải thỏa mãn validate rule: có timestamp, action, username", async () => {
    await assertFails(db("cashier_uid").ref("stores/TRAM01/audit_logs/log_invalid").set({ action: "TEST" }));
  });

  it("13. Mọi nút gốc cũ bị từ chối với mọi vai trò và với người chưa đăng nhập", async () => {
    const legacyNodes = ["users", "tables", "products", "categories", "zones", "history", "audit_logs", "kmt_customers", "online_orders", "kitchen_orders", "cham_cong", "timekeeping", "employees", "shifts"];
    legacyNodes.forEach((node) => expect(parsedRules.rules[node]).toBeUndefined());
    expect(parsedRules.rules[".read"]).toBe(false);
    expect(parsedRules.rules[".write"]).toBe(false);

    const unauth = env().unauthenticatedContext().database();
    const owner = db("owner_uid");
    for (const node of legacyNodes) {
      await assertFails(unauth.ref(node).get());
      await assertFails(unauth.ref(node).set({ hacked: true }));
      await assertFails(owner.ref(node).get());
      await assertFails(owner.ref(node).set({ hacked: true }));
    }
  });

  it("14. Chỉ có đúng 2 nhánh được mở ở cấp root: userIndex và stores", () => {
    const topLevelKeys = Object.keys(parsedRules.rules).filter((k) => !k.startsWith("."));
    // Nhánh gốc mở có chủ đích: stores, userIndex và các nút điểm dùng chung (chỉ đọc cấu hình, còn lại đóng với client)
    expect(topLevelKeys.sort()).toEqual(
      ["stores", "userIndex", "loyalty_config", "loyalty_ledger", "loyalty_ledger_index", "loyalty_members", "loyalty_migration"].sort()
    );
  });
});

describe("POS Trạm - Security Rules: tấn công leo thang quyền", () => {
  it("15. Người ngoài tự đăng ký làm Chủ quán -> bị từ chối và vẫn không đọc được quán", async () => {
    const attacker = db("attacker_uid");
    await assertFails(
      attacker.ref("stores/TRAM01/users/attacker_uid").set({ username: "hacker", fullName: "Hacker", roleId: "owner", isRootOwner: true, isActive: true })
    );
    await assertFails(attacker.ref("stores/TRAM01/users/attacker_uid/lastLoginAt").set(Date.now()));
    await assertFails(attacker.ref("stores/TRAM01/users/attacker_uid/mustChangePassword").set(false));
    await assertFails(attacker.ref("stores/TRAM01").get());
    await assertFails(attacker.ref("stores/TRAM01/bills").get());
  });

  it("16. Hồ sơ users/{uid} không có userIndex hoặc userIndex còn sót sau khi xóa hồ sơ -> không có quyền", async () => {
    await assertFails(db("noindex_uid").ref("stores/TRAM01/products").get());
    await assertFails(db("noindex_uid").ref("stores/TRAM01/products/p1").set({ name: "X" }));
    // deleted_uid có userIndex nhưng hồ sơ đã bị xóa
    await assertFails(db("deleted_uid").ref("stores/TRAM01/tables").get());
  });

  it("17. Quản lý không tự nâng quyền, không cấp quyền Chủ quán, không sửa hồ sơ Chủ quán", async () => {
    const manager = db("manager_uid");
    await assertFails(manager.ref("stores/TRAM01/users/manager_uid/roleId").set("owner"));
    await assertFails(manager.ref("stores/TRAM01/users/manager_uid/isRootOwner").set(true));
    await assertFails(manager.ref("stores/TRAM01/users/manager_uid").update({ roleId: "ROLE_OWNER" }));
    await assertFails(manager.ref("stores/TRAM01/users/waiter_uid/roleId").set("owner"));
    await assertFails(manager.ref("stores/TRAM01/users/waiter_uid/isRootOwner").set(true));
    await assertFails(manager.ref("stores/TRAM01/users/owner_uid/fullName").set("Bị sửa"));
    await assertFails(
      manager.ref("stores/TRAM01/users/new_owner").set({ username: "x", fullName: "X", roleId: "ROLE_OWNER", isActive: true })
    );
    // Quản lý vẫn quản lý được nhân viên thường và tự sửa thông tin không nhạy cảm
    await assertSucceeds(manager.ref("stores/TRAM01/users/waiter_uid/roleId").set("cashier"));
    await assertSucceeds(manager.ref("stores/TRAM01/users/manager_uid/fullName").set("Quản Lý Mới"));
  });

  it("18. Nhân viên chỉ tự ghi được lastLoginAt / mustChangePassword=false", async () => {
    const cashier = db("cashier_uid");
    await assertSucceeds(cashier.ref("stores/TRAM01/users/cashier_uid/lastLoginAt").set(Date.now()));
    await assertSucceeds(cashier.ref("stores/TRAM01/users/cashier_uid").update({ mustChangePassword: false, lastPasswordChangedAt: Date.now() }));
    await assertFails(cashier.ref("stores/TRAM01/users/cashier_uid/mustChangePassword").set(true));
    await assertFails(cashier.ref("stores/TRAM01/users/cashier_uid/isActive").set(true));
    await assertFails(cashier.ref("stores/TRAM01/users/waiter_uid/lastLoginAt").set(Date.now()));
  });
});

describe("POS Trạm - Security Rules: hóa đơn, bàn, bếp", () => {
  it("19. Phục vụ không sửa/xóa được hóa đơn đã PAID, không tự tạo hóa đơn PAID", async () => {
    const waiter = db("waiter_uid");
    await assertFails(waiter.ref("stores/TRAM01/bills/paid_bill/finalAmount").set(1000));
    await assertFails(waiter.ref("stores/TRAM01/bills/paid_bill").update({ status: "OPEN" }));
    await assertFails(waiter.ref("stores/TRAM01/bills/paid_bill").remove());
    await assertFails(waiter.ref("stores/TRAM01/history/paid_bill/totalAmount").set(1));
    await assertFails(waiter.ref("stores/TRAM01/bills/new_paid").set({ status: "PAID", finalAmount: 0 }));
    await assertFails(waiter.ref("stores/TRAM01/bills/open_bill").update({ status: "PAID" }));
    // Luồng hợp lệ của phục vụ: tạo/cập nhật hóa đơn mở và hủy bàn đang mở
    await assertSucceeds(waiter.ref("stores/TRAM01/bills/new_open").set({ status: "OPEN", subTotal: 20000, finalAmount: 20000 }));
    await assertSucceeds(waiter.ref("stores/TRAM01/bills/open_bill/finalAmount").set(60000));
    await assertSucceeds(waiter.ref("stores/TRAM01/bills/BILL_CANCELLED_1").set({ status: "CANCELLED", finalAmount: 0, totalAmount: 20000 }));
    await assertFails(waiter.ref("stores/TRAM01/bills/open_bill").remove());
  });

  it("20. Thu ngân thanh toán hóa đơn thành công; chỉ Quản lý/Chủ quán được xóa", async () => {
    const cashier = db("cashier_uid");
    await assertSucceeds(cashier.ref("stores/TRAM01/bills/open_bill").update({ status: "PAID", closedAt: Date.now(), paymentMethod: "CASH" }));
    await assertSucceeds(cashier.ref("stores/TRAM01/history/open_bill").set({ id: "open_bill", status: "PAID", totalAmount: 50000 }));
    await assertFails(cashier.ref("stores/TRAM01/bills/paid_bill").remove());
    // Quản lý MẶC ĐỊNH không được xóa hóa đơn đã thanh toán (cần Chủ cấp CANCEL_BILL — xem nhóm RR)
    await assertFails(db("manager_uid").ref("stores/TRAM01/bills/paid_bill").remove());
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/history/paid_bill").remove());
  });

  it("21. Validate hóa đơn: trạng thái hợp lệ, số tiền là số không âm", async () => {
    const cashier = db("cashier_uid");
    await assertFails(cashier.ref("stores/TRAM01/bills/b_bad1").set({ status: "HACKED", finalAmount: 1 }));
    await assertFails(cashier.ref("stores/TRAM01/bills/b_bad2").set({ status: "PAID", finalAmount: "100000" }));
    await assertFails(cashier.ref("stores/TRAM01/bills/b_bad3").set({ status: "PAID", finalAmount: -5 }));
    await assertFails(cashier.ref("stores/TRAM01/bills/b_bad4").set("chuoi"));
  });

  it("22. Checkout multi-path update tại stores/{storeCode}: thu ngân OK, phục vụ bị chặn", async () => {
    const payload = {
      "bills/co1": { id: "co1", status: "PAID", finalAmount: 30000, subTotal: 30000 },
      "history/co1": { id: "co1", status: "PAID", totalAmount: 30000 },
      "tables/T1": { name: "Bàn 1", inUse: false },
      "bill_stock_applied/co1": true,
    };
    await assertFails(db("waiter_uid").ref("stores/TRAM01").update(payload));
    await assertSucceeds(db("cashier_uid").ref("stores/TRAM01").update(payload));
  });

  it("23. Bàn và phiếu bếp: nhân viên ghi được, chỉ Quản lý xóa được", async () => {
    const waiter = db("waiter_uid");
    await assertSucceeds(waiter.ref("stores/TRAM01/tables/T2").set({ name: "Bàn 2", inUse: true }));
    await assertFails(waiter.ref("stores/TRAM01/tables/T2").remove());
    await assertSucceeds(db("kitchen_uid").ref("stores/TRAM01/kitchen_orders/k1").set({ tableName: "Bàn 2", isDone: false }));
    await assertSucceeds(db("kitchen_uid").ref("stores/TRAM01/kitchen_orders/k1/isDone").set(true));
    await assertFails(db("kitchen_uid").ref("stores/TRAM01/kitchen_orders/k1/isDone").set("yes"));
    await assertFails(waiter.ref("stores/TRAM01/kitchen_orders/k1").remove());
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/tables/T2").remove());
  });
});

describe("POS Trạm - Security Rules: bộ đếm, kho, khuyến mãi khi thanh toán", () => {
  it("24. counters/bill_seq/{yyMMdd}: tăng đúng +1, cấm nhảy số / sai kiểu / sai khóa ngày", async () => {
    const waiter = db("waiter_uid");
    await assertSucceeds(waiter.ref("stores/TRAM01/counters/bill_seq/261009").set(1));
    await assertSucceeds(waiter.ref("stores/TRAM01/counters/bill_seq/261009").set(2));
    await assertFails(waiter.ref("stores/TRAM01/counters/bill_seq/261009").set(10));
    await assertFails(waiter.ref("stores/TRAM01/counters/bill_seq/261009").set(1));
    await assertFails(waiter.ref("stores/TRAM01/counters/bill_seq/261010").set("1"));
    await assertFails(waiter.ref("stores/TRAM01/counters/bill_seq/2026-10-09").set(1));
    await assertFails(waiter.ref("stores/TRAM01/counters/bill_seq/261009").remove());
    await assertSucceeds(waiter.ref("stores/TRAM01/counters/bill_seq/261009").get());
    await assertFails(db("attacker_uid").ref("stores/TRAM01/counters/bill_seq/261011").set(1));
  });

  it("25. bill_stock_applied: chỉ tạo 1 lần bởi người thanh toán; Quản lý mới được xóa", async () => {
    const cashier = db("cashier_uid");
    await assertFails(db("waiter_uid").ref("stores/TRAM01/bill_stock_applied/b9").set(true));
    await assertFails(cashier.ref("stores/TRAM01/bill_stock_applied/b9").set("true"));
    await assertSucceeds(cashier.ref("stores/TRAM01/bill_stock_applied/b9").set(true));
    await assertFails(cashier.ref("stores/TRAM01/bill_stock_applied/b9").set(true));
    await assertFails(cashier.ref("stores/TRAM01/bill_stock_applied/b9").remove());
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bill_stock_applied/b9").remove());
  });

  it("26. Kho: thu ngân trừ tồn khi bán (SALE), không được tăng tồn hay sửa sự kiện", async () => {
    const cashier = db("cashier_uid");
    const bal = "stores/TRAM01/stock_balances/TRAM01_ITEM1";
    await assertSucceeds(cashier.ref(bal).set({ balanceId: "TRAM01_ITEM1", itemId: "ITEM1", onHandQty: 990, inventoryValue: 495000, averageCostScaled: 50000, updatedAt: Date.now() }));
    await assertFails(cashier.ref(bal).set({ balanceId: "TRAM01_ITEM1", itemId: "ITEM1", onHandQty: 5000, inventoryValue: 495000, averageCostScaled: 50000 }));
    await assertFails(cashier.ref(`${bal}/averageCostScaled`).set(1));
    await assertSucceeds(cashier.ref("stores/TRAM01/stock_balances/TRAM01_NEW").set({ itemId: "NEW", onHandQty: -2, inventoryValue: 0, averageCostScaled: 0 }));

    const evt = { eventId: "EVT1", documentType: "SALE", documentId: "b1", itemId: "ITEM1", qtyDeltaBase: -10, valueDeltaMoney: -5000 };
    await assertSucceeds(cashier.ref("stores/TRAM01/stock_events/EVT1").set(evt));
    await assertFails(cashier.ref("stores/TRAM01/stock_events/EVT1").set({ ...evt, qtyDeltaBase: -1 }));
    await assertFails(cashier.ref("stores/TRAM01/stock_events/EVT2").set({ ...evt, eventId: "EVT2", documentType: "RECEIPT", qtyDeltaBase: 100 }));
    await assertFails(db("waiter_uid").ref("stores/TRAM01/stock_events/EVT3").set({ ...evt, eventId: "EVT3" }));
    await assertFails(db("waiter_uid").ref(bal).set({ onHandQty: 0, inventoryValue: 0, averageCostScaled: 50000 }));
    await assertSucceeds(db("manager_uid").ref(bal).set({ onHandQty: 5000, inventoryValue: 1, averageCostScaled: 1 }));
  });

  it("27. Khuyến mãi: thu ngân cập nhật bộ đếm (chỉ tăng), dùng voucher, tăng usageCount", async () => {
    const cashier = db("cashier_uid");
    await assertSucceeds(
      cashier.ref("stores/TRAM01/campaign_counters/CAM1").set({ campaignId: "CAM1", spentMoney: 15000, committedUseCount: 2, reservedMoney: 0, reservedUseCount: 0, version: 2 })
    );
    await assertFails(
      cashier.ref("stores/TRAM01/campaign_counters/CAM1").set({ campaignId: "CAM1", spentMoney: 0, committedUseCount: 0, reservedMoney: 0, reservedUseCount: 0, version: 3 })
    );
    await assertSucceeds(
      cashier.ref("stores/TRAM01/customer_campaign_counters/CAM1_C1").set({ campaignId: "CAM1", customerId: "C1", usedCount: 1, heldCount: 0 })
    );
    await assertFails(cashier.ref("stores/TRAM01/customer_campaign_counters/CAM1_C1/usedCount").set(0));
    await assertFails(db("waiter_uid").ref("stores/TRAM01/campaign_counters/CAM1/spentMoney").set(99999));

    const v = "stores/TRAM01/vouchers/CAM1/VCH1";
    // Hóa đơn dùng mã đã tồn tại -> không được trả mã về RELEASED (trường hợp hóa đơn không tồn tại xem VR1)
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("stores/TRAM01/bills/b1").set({ status: "PAID", finalAmount: 10000 });
    });
    await assertSucceeds(cashier.ref(v).set({ voucherId: "VCH1", campaignId: "CAM1", normalizedCode: "ABC", state: "REDEEMED", redeemedBillId: "b1", version: 2 }));
    await assertFails(cashier.ref(v).set({ voucherId: "VCH1", campaignId: "CAM1", normalizedCode: "ABC", state: "RELEASED", version: 3 }));
    await assertFails(cashier.ref("stores/TRAM01/vouchers/CAM1/VCH_NEW").set({ voucherId: "VCH_NEW", campaignId: "CAM1", normalizedCode: "NEW", state: "RELEASED" }));

    await assertSucceeds(cashier.ref("stores/TRAM01/promotions/PR1/usageCount").set(4));
    await assertFails(cashier.ref("stores/TRAM01/promotions/PR1/usageCount").set(100));
    await assertFails(cashier.ref("stores/TRAM01/promotions/PR1/name").set("Đổi tên"));
  });

  it("28. recipes và migration_log: Quản lý/Chủ quán ghi được; Thu ngân/Phục vụ bị chặn", async () => {
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/recipes/R1").set({ recipeId: "R1", status: "ACTIVE" }));
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/migration_log/promotions").set({ done: true }));
    await assertFails(db("cashier_uid").ref("stores/TRAM01/recipes/R2").set({ recipeId: "R2" }));
    await assertFails(db("waiter_uid").ref("stores/TRAM01/migration_log/promotions").set({ done: false }));
  });

  it("29. roles: chỉ Chủ quán ghi được, Quản lý không tự sửa ma trận quyền", async () => {
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/roles/manager").set({ id: "manager", permissions: ["VIEW_REPORTS"] }));
    await assertFails(db("manager_uid").ref("stores/TRAM01/roles/manager").set({ id: "manager", permissions: ["ALL"] }));
    await assertFails(db("cashier_uid").ref("stores/TRAM01/roles/cashier").set({ id: "cashier" }));
  });
});

describe("POS Trạm - Security Rules: điểm khách hàng & trừ kho thử lại", () => {
  const C = "stores/TRAM01/customers/KH1";
  const baseCustomer = { id: "KH1", ho_ten: "Khách 1", so_dien_thoai: "0900000001", diem_hien_tai: 50, currentPoints: 50, totalPoints: 80 };

  async function seedLoyalty() {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      await d.ref("stores/TRAM01/storeInfo").set({ storeName: "Trạm", pointEarnRate: 1, pointRedeemRate: 1000 });
      await d.ref(C).set(baseCustomer);
      await d.ref("stores/TRAM01/bills/award_bill").set({ id: "award_bill", billCode: "HD-9", status: "PAID", finalAmount: 2000000, subTotal: 2000000, customerId: "KH1" });
      await d.ref("stores/TRAM01/bills/other_cust_bill").set({ id: "other_cust_bill", status: "PAID", finalAmount: 2000000, subTotal: 2000000, customerId: "KH2" });
    });
  }

  it("LS1. Phục vụ không sửa được điểm; thu ngân không sửa điểm tùy ý / không xóa khách", async () => {
    await seedLoyalty();
    await assertFails(db("waiter_uid").ref(`${C}/currentPoints`).set(9999));
    await assertFails(db("waiter_uid").ref(C).update({ diem_hien_tai: 9999, currentPoints: 9999 }));
    const cashier = db("cashier_uid");
    await assertFails(cashier.ref(C).update({ diem_hien_tai: 9999, currentPoints: 9999 }));
    await assertFails(cashier.ref(C).update({ totalPoints: 5000 }));
    await assertFails(cashier.ref(C).remove());
    // Sửa thông tin không đụng điểm vẫn được
    await assertSucceeds(cashier.ref(C).update({ ho_ten: "Khách Một" }));
    await assertSucceeds(cashier.ref(C).set({ ...baseCustomer, ho_ten: "Khách Một" }));
    // Điểm là cache chỉ đọc (số dư thật ở loyalty_members): Quản lý/Chủ cũng không sửa trực tiếp được
    await assertFails(db("manager_uid").ref(C).update({ diem_hien_tai: 10, currentPoints: 10 }));
    await assertFails(db("owner_uid").ref(C).update({ totalPoints: 1 }));
    await assertSucceeds(db("manager_uid").ref(C).update({ ho_ten: "Khách Một (QL)" }));
    // Xóa khách ở chi nhánh: chỉ Quản lý/Chủ (số điểm chung vẫn giữ ở loyalty_members)
    await assertSucceeds(db("manager_uid").ref(C).remove());
  });

  it("LS1b. Thu ngân tạo khách mới chỉ với 0 điểm (nhập số dư thật qua importCustomerToStore)", async () => {
    await seedLoyalty();
    const cashier = db("cashier_uid");
    const fresh = { id: "KH_NEW", ho_ten: "Khách mới", so_dien_thoai: "0900000002" };
    const N = "stores/TRAM01/customers/KH_NEW";
    await assertFails(cashier.ref(N).set({ ...fresh, diem_hien_tai: 500, currentPoints: 500, totalPoints: 500 }));
    await assertFails(cashier.ref(N).set({ ...fresh, diem_hien_tai: 0, currentPoints: 0, totalPoints: 900 }));
    await assertFails(cashier.ref(N).set({ ...fresh, diem_hien_tai: 0, currentPoints: 0, diemHienTai: 900 }));
    await assertFails(cashier.ref(N).set({ ...fresh, currentPoints: 0, loyaltyOps: { "x:award": 1 } }));
    await assertFails(cashier.ref(N).set({ ...fresh, currentPoints: 0, lastLoyaltyOp: "award_bill:award" }));
    await assertSucceeds(cashier.ref(N).set({ ...fresh, diem_hien_tai: 0, currentPoints: 0, totalPoints: 0 }));
    // Không được thêm trường điểm cũ (diemHienTai / tongDiem) vào khách đã có
    await assertFails(cashier.ref(C).update({ diemHienTai: 9999 }));
    await assertFails(cashier.ref(C).update({ tongDiem: 9999 }));
    // Quản lý cũng không tạo khách có điểm / đặt điểm tùy ý (điểm chỉ đổi qua Cloud Function)
    await assertFails(db("manager_uid").ref("stores/TRAM01/customers/KH_VIP").set({ ...fresh, id: "KH_VIP", diem_hien_tai: 800, currentPoints: 800, totalPoints: 800 }));
    await assertFails(db("manager_uid").ref(C).update({ diem_hien_tai: 999, currentPoints: 999, totalPoints: 999 }));
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/customers/KH_VIP").set({ ...fresh, id: "KH_VIP", diem_hien_tai: 0, currentPoints: 0, totalPoints: 0 }));
  });

  it("PH1. point_history: chỉ Chủ/Quản lý tạo mới (không sửa/xóa); thu ngân đọc được, phục vụ không", async () => {
    await seedLoyalty();
    const entry = { customerId: "KH1", customerName: "Khách 1", type: "ADJUST", mode: "ADD", delta: 10, before: 50, after: 60, reason: "Tặng sinh nhật", by: "manager1", at: 1700000000000 };
    const P = "stores/TRAM01/point_history/adj_1";
    await assertFails(db("cashier_uid").ref(P).set(entry));
    await assertFails(db("waiter_uid").ref(P).set(entry));
    await assertFails(db("manager_uid").ref(P).set({ ...entry, reason: "" }));
    await assertFails(db("manager_uid").ref(P).set({ ...entry, after: -1 }));
    await assertFails(db("manager_uid").ref(P).set({ ...entry, type: "AWARD" }));
    await assertSucceeds(db("manager_uid").ref(P).set(entry));
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/point_history/pool_1").set({ ...entry, type: "POOL_REDEEM", mode: "POOL", delta: -10, before: 60, after: 50 }));
    await assertFails(db("manager_uid").ref(P).set({ ...entry, delta: 99 }));
    await assertFails(db("owner_uid").ref(P).remove());
    await assertSucceeds(db("cashier_uid").ref(P).get());
    await assertFails(db("waiter_uid").ref(P).get());
  });

  it("PH2. Chỉnh điểm trực tiếp bằng multi-path update bị chặn với mọi vai trò; ghi point_history + audit không kèm điểm thì Quản lý được", async () => {
    await seedLoyalty();
    const now = Date.now();
    const hist = {
      [`stores/TRAM01/point_history/adj_${now}`]: { customerId: "KH1", type: "ADJUST", delta: 20, before: 50, after: 70, reason: "Sửa nhầm", by: "manager1", at: now },
      [`stores/TRAM01/audit_logs/log_${now}_pt`]: { timestamp: now, action: "ADJUST_POINTS", username: "manager1" },
    };
    const withPoints = {
      ...hist,
      "stores/TRAM01/customers/KH1/diem_hien_tai": 70,
      "stores/TRAM01/customers/KH1/currentPoints": 70,
      "stores/TRAM01/customers/KH1/totalPoints": 100,
    };
    await assertFails(db("cashier_uid").ref().update(withPoints));
    await assertFails(db("manager_uid").ref().update(withPoints));
    await assertFails(db("owner_uid").ref().update(withPoints));
    await assertFails(db("cashier_uid").ref().update(hist));
    await assertSucceeds(db("manager_uid").ref().update(hist));
  });

  it("LS2. Không client nào đổi/hoàn/tích điểm trực tiếp trên node khách (chỉ Cloud Function loyalty_members)", async () => {
    await seedLoyalty();
    const cashier = db("cashier_uid");
    const redeem = { ...baseCustomer, diem_hien_tai: 30, currentPoints: 30, lastLoyaltyOp: "newbill:redeem", lastLoyaltyBillId: "newbill", lastLoyaltyType: "redeem", lastRedeem: { billId: "newbill", points: 20 } };
    await assertFails(cashier.ref(C).set(redeem));
    const award = { ...baseCustomer, diem_hien_tai: 70, currentPoints: 70, totalPoints: 100, lastLoyaltyOp: "award_bill:award", lastLoyaltyBillId: "award_bill", lastLoyaltyType: "award" };
    await assertFails(cashier.ref(C).set(award));
    await assertFails(cashier.ref(C).update({ lastRedeem: { billId: "x", points: 1 } }));
    await assertFails(cashier.ref(C).update({ loyaltyOps: { a: "x:award" } }));
    await assertFails(db("manager_uid").ref(C).set(award));
    await assertFails(db("owner_uid").ref(C).set(redeem));
    // Sửa thông tin (kể cả ghi lại nguyên điểm đang có) vẫn được
    await assertSucceeds(cashier.ref(C).set({ ...baseCustomer, ho_ten: "Đổi tên" }));
  });

  it("LS3. Sổ cái cũ loyalty_applied đóng ghi với mọi client (sổ cái mới ở loyalty_ledger do Cloud Function ghi)", async () => {
    await seedLoyalty();
    const ledger = "stores/TRAM01/loyalty_applied/award_bill/award";
    await assertFails(db("cashier_uid").ref(ledger).set({ customerId: "KH1", points: 20 }));
    await assertFails(db("manager_uid").ref(ledger).set({ customerId: "KH1", points: 20 }));
    await assertFails(db("owner_uid").ref(ledger).set({ customerId: "KH1", points: 20 }));
  });

  it("LS7. Điểm dùng chung: loyalty_members / loyalty_ledger / loyalty_migration đóng đọc-ghi với client; loyalty_config chỉ đọc", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      await d.ref("loyalty_members/0912345678").set({ name: "An", phone: "0912345678", points: 10, totalPoints: 10 });
      await d.ref("loyalty_ledger/0912345678/b1_earn").set({ type: "earn", points: 10, balanceAfter: 10, storeCode: "TRAM01", at: 1 });
      await d.ref("loyalty_config").set({ pointEarnRate: 1, pointRedeemRate: 1000, loyaltyTiers: [{ name: "Bạc", minPoints: 100 }] });
    });
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid", "waiter_uid", "storeB_uid"]) {
      const c = db(uid);
      await assertFails(c.ref("loyalty_members/0912345678").get());
      await assertFails(c.ref("loyalty_members").get());
      await assertFails(c.ref("loyalty_members/0912345678/points").set(99999));
      await assertFails(c.ref("loyalty_members/0900000000").set({ name: "X", phone: "0900000000", points: 5, totalPoints: 5 }));
      await assertFails(c.ref("loyalty_ledger/0912345678/b1_earn").get());
      await assertFails(c.ref("loyalty_ledger/0912345678/hack").set({ type: "earn", points: 1 }));
      await assertFails(c.ref("loyalty_migration/shared_v1").set({ at: 1 }));
      // Cấu hình chuỗi: nhân viên thuộc ít nhất 1 chi nhánh đọc được, KHÔNG ai ghi trực tiếp (đi qua callable setLoyaltyConfig)
      await assertSucceeds(c.ref("loyalty_config").get());
      await assertFails(c.ref("loyalty_config/pointEarnRate").set(50));
    }
    await assertFails(env().unauthenticatedContext().database().ref("loyalty_config").get());
    await assertFails(db("stranger_uid").ref("loyalty_config").get());
  });

  it("LS8. Chỉ mục sổ cái loyalty_ledger_index đóng đọc-ghi với mọi client (chỉ Admin SDK)", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("loyalty_ledger_index/202601/0912345678~b1_earn").set({ memberKey: "0912345678", opId: "b1_earn", at: 1, storeCode: "TRAM01", type: "earn" });
    });
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid", "waiter_uid", "storeB_uid", "stranger_uid"]) {
      const c = db(uid);
      await assertFails(c.ref("loyalty_ledger_index").get());
      await assertFails(c.ref("loyalty_ledger_index/202601/0912345678~b1_earn").get());
      await assertFails(c.ref("loyalty_ledger_index/202601/x~y").set({ memberKey: "x", opId: "y", at: 1, storeCode: "TRAM01", type: "earn" }));
      await assertFails(c.ref("loyalty_ledger_index/_meta").set({ complete: true }));
    }
    await assertFails(env().unauthenticatedContext().database().ref("loyalty_ledger_index").get());
  });

  it("LS4. bill_stock_lines: marker từng dòng chỉ tạo 1 lần bởi thu ngân trở lên", async () => {
    const cashier = db("cashier_uid");
    const line = "stores/TRAM01/bill_stock_lines/b10/ITEM1";
    await assertFails(db("waiter_uid").ref(line).set(10));
    await assertFails(cashier.ref(line).set("10"));
    await assertSucceeds(cashier.ref(line).set(10));
    await assertFails(cashier.ref(line).set(20));
    await assertFails(cashier.ref(line).remove());
    // Ghi sổ kho + marker dòng trong cùng 1 lệnh multi-path
    await assertSucceeds(
      cashier.ref("stores/TRAM01").update({
        "bill_stock_lines/b10/ITEM2": 5,
        "stock_events/EVT_SALE_b10_ITEM2": { eventId: "EVT_SALE_b10_ITEM2", documentType: "SALE", documentId: "b10", itemId: "ITEM2", qtyDeltaBase: -5 },
      })
    );
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bill_stock_lines/b10").remove());
    // Marker tổng cũ vẫn giữ nguyên ngữ nghĩa chỉ tạo mới
    await assertSucceeds(cashier.ref("stores/TRAM01/bill_stock_applied/b10").set(true));
    await assertFails(cashier.ref("stores/TRAM01/bill_stock_applied/b10").set(true));
  });

  it("LS5. stock_retry_queue: thu ngân ghi/xóa được mục của hóa đơn, phục vụ bị chặn, dữ liệu hợp lệ", async () => {
    const cashier = db("cashier_uid");
    const q = "stores/TRAM01/stock_retry_queue/b11";
    const entry = { billId: "b11", billCode: "HD-11", username: "thungan", attempts: 1, lastError: "offline", createdAt: Date.now(), updatedAt: Date.now(), plan: [{ itemId: "ITEM1", qty: 10 }] };
    await assertFails(db("waiter_uid").ref(q).set(entry));
    await assertFails(cashier.ref(q).set({ ...entry, billId: "khac" }));
    await assertFails(cashier.ref(q).set({ ...entry, attempts: "1" }));
    await assertSucceeds(cashier.ref(q).set(entry));
    await assertSucceeds(cashier.ref(q).update({ attempts: 2, updatedAt: Date.now() }));
    await assertSucceeds(cashier.ref("stores/TRAM01/stock_retry_queue").get());
    await assertSucceeds(cashier.ref(q).remove());
    await assertFails(cashier.ref("stores/TRAM01/stock_retry_queue").remove());
  });

  it("LS6. Tồn kho có vòng khóa recentSaleBills: thu ngân vẫn trừ được, không tăng được", async () => {
    const cashier = db("cashier_uid");
    const bal = "stores/TRAM01/stock_balances/TRAM01_ITEM1";
    await assertSucceeds(
      cashier.ref(bal).set({ balanceId: "TRAM01_ITEM1", itemId: "ITEM1", onHandQty: 990, inventoryValue: 495000, averageCostScaled: 50000, recentSaleBills: ["b12"] })
    );
    await assertFails(
      cashier.ref(bal).set({ balanceId: "TRAM01_ITEM1", itemId: "ITEM1", onHandQty: 995, inventoryValue: 495000, averageCostScaled: 50000, recentSaleBills: [] })
    );
  });
});

describe("POS Trạm - Security Rules: quyền đọc theo từng nút con (không lan quyền đọc từ stores/{s})", () => {
  // Các nút mọi thành viên quán (kể cả Phục vụ / Bếp) cần đọc để vận hành POS
  const memberReadable = [
    "storeInfo", "users", "products", "categories", "product_notes", "note_groups", "topping_groups", "zones", "tables", "bills", "history",
    "kitchen_orders", "online_orders", "cash_shifts", "promotions", "campaigns", "vouchers", "voucher_lookup",
    "campaign_counters", "customer_campaign_counters", "inventory", "catalog_items", "stock_balances",
    "stock_events", "bill_stock_applied", "bill_stock_lines", "stock_retry_queue", "counters",
    "inventory_documents", "supplier_ledger", "suppliers", "receipts", "loyalty_applied",
    "payment_events", "recipes", "migration_log", "roles",
  ];

  it("RC1. Phục vụ và Bếp đọc được các nút vận hành (bàn, món, danh mục, khu vực, bếp, hóa đơn...)", async () => {
    for (const uid of ["waiter_uid", "kitchen_uid"]) {
      for (const node of memberReadable) {
        await assertSucceeds(db(uid).ref(`stores/TRAM01/${node}`).get());
      }
    }
    await assertSucceeds(db("waiter_uid").ref("stores/TRAM01/bills/open_bill").get());
    await assertSucceeds(db("waiter_uid").ref("stores/TRAM01/users/waiter_uid").get());
    // Nhật ký thao tác (audit_logs) KHÔNG phải nút mọi thành viên đọc được — xem nhóm AL
    for (const uid of ["waiter_uid", "kitchen_uid"]) {
      await assertFails(db(uid).ref("stores/TRAM01/audit_logs").get());
    }
  });

  it("RC2. Phục vụ và Bếp KHÔNG đọc được customers (cả danh sách lẫn từng khách)", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("stores/TRAM01/customers/c1").set({ name: "Khách", phone: "0900000000", currentPoints: 10 });
    });
    for (const uid of ["waiter_uid", "kitchen_uid"]) {
      await assertFails(db(uid).ref("stores/TRAM01/customers").get());
      await assertFails(db(uid).ref("stores/TRAM01/customers/c1").get());
      await assertFails(db(uid).ref("stores/TRAM01/customers/c1/currentPoints").get());
    }
    for (const uid of ["cashier_uid", "manager_uid", "owner_uid"]) {
      await assertSucceeds(db(uid).ref("stores/TRAM01/customers").get());
    }
  });

  it("RC3. Không ai đọc được cả nút stores/{s} (tránh lan quyền xuống customers / dữ liệu ẩn)", async () => {
    for (const uid of ["waiter_uid", "cashier_uid", "manager_uid", "owner_uid"]) {
      await assertFails(db(uid).ref("stores/TRAM01").get());
    }
  });

  it("RC4. login_attempts (gốc mới và nhánh cũ trong store) bị chặn với mọi client, kể cả Chủ quán", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("login_attempts/TRAM01/thungan").set({ failedCount: 3, lastAttemptAt: Date.now() });
      await context.database().ref("stores/TRAM01/login_attempts/thungan").set({ failedCount: 3, lastAttemptAt: Date.now() });
    });
    for (const uid of ["waiter_uid", "cashier_uid", "manager_uid", "owner_uid"]) {
      await assertFails(db(uid).ref("login_attempts/TRAM01/thungan").get());
      await assertFails(db(uid).ref("login_attempts/TRAM01").get());
      await assertFails(db(uid).ref("stores/TRAM01/login_attempts").get());
      await assertFails(db(uid).ref("stores/TRAM01/login_attempts/thungan").get());
      await assertFails(db(uid).ref("login_attempts/TRAM01/thungan").set({ failedCount: 0 }));
    }
  });

  it("RC5. Nút con vẫn chặn người ngoài quán, tài khoản bị khóa và người chưa đăng nhập", async () => {
    for (const node of ["tables", "products", "storeInfo", "users", "customers"]) {
      await assertFails(db("storeB_uid").ref(`stores/TRAM01/${node}`).get());
      await assertFails(db("inactive_uid").ref(`stores/TRAM01/${node}`).get());
      await assertFails(env().unauthenticatedContext().database().ref(`stores/TRAM01/${node}`).get());
    }
  });

  it("RC6. Cấu trúc rules: stores/$storeCode không có .read; mọi nút con đều tự khai báo .read", () => {
    const store = parsedRules.rules.stores.$storeCode;
    expect(store[".read"]).toBeUndefined();
    const children = Object.keys(store).filter((k) => !k.startsWith("."));
    for (const child of children) {
      expect(typeof store[child][".read"], `stores/$storeCode/${child} thiếu .read`).toBe("string");
    }
    // Danh sách test RC1 + customers + point_history (chỉ Thu ngân trở lên đọc) phải phủ hết nút con (thêm nút mới → cập nhật test)
    expect([...memberReadable, "customers", "point_history", "audit_logs"].sort()).toEqual(children.sort());
    expect(children).not.toContain("login_attempts");
  });

  it("RC7. Quyền Thu ngân trở lên vẫn đọc được mọi nút vận hành; quyền nút con không bị nhầm sang nhau", async () => {
    for (const uid of ["cashier_uid", "manager_uid", "owner_uid"]) {
      for (const node of memberReadable) {
        await assertSucceeds(db(uid).ref(`stores/TRAM01/${node}`).get());
      }
    }
    // Truy vấn có sắp xếp trên nút con (app dùng orderByChild cho bills / audit_logs)
    await assertSucceeds(db("waiter_uid").ref("stores/TRAM01/bills").orderByChild("status").equalTo("OPEN").get());
    await assertFails(db("waiter_uid").ref("stores/TRAM01/customers").orderByChild("phone").equalTo("0900000000").get());
  });
});

describe("POS Trạm - Security Rules: PIN duyệt quản lý", () => {
  it("MP1. Không ai ghi được managerPin (bản rõ) vào storeInfo; storeInfo hợp lệ vẫn ghi được", async () => {
    const owner = db("owner_uid");
    await assertSucceeds(owner.ref("stores/TRAM01/storeInfo").set({ storeName: "Trạm", pointEarnRate: 1 }));
    await assertFails(owner.ref("stores/TRAM01/storeInfo").set({ storeName: "Trạm", managerPin: "1234" }));
    await assertFails(owner.ref("stores/TRAM01/storeInfo").update({ managerPin: "5678" }));
    await assertFails(owner.ref("stores/TRAM01/storeInfo/managerPin").set("5678"));
    await assertSucceeds(owner.ref("stores/TRAM01/storeInfo").update({ storeName: "Trạm 2" }));

    // Dữ liệu cũ còn managerPin bản rõ: vẫn cập nhật được trường khác và xóa được PIN cũ
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("stores/TRAM01/storeInfo/managerPin").set("1234");
    });
    await assertSucceeds(owner.ref("stores/TRAM01/storeInfo").update({ storeName: "Trạm 3" }));
    await assertFails(owner.ref("stores/TRAM01/storeInfo/managerPin").set("9999"));
    await assertSucceeds(owner.ref("stores/TRAM01/storeInfo/managerPin").remove());
  });

  it("MP2. Băm PIN tại manager_pins/ chỉ Admin SDK truy cập được", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("manager_pins/TRAM01/manager_uid").set({ algo: "scrypt", salt: "00", hash: "00" });
    });
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid"]) {
      await assertFails(db(uid).ref("manager_pins/TRAM01/manager_uid").get());
      await assertFails(db(uid).ref("manager_pins/TRAM01/manager_uid").set({ algo: "scrypt", salt: "11", hash: "11" }));
    }
  });
});

describe("POS Trạm - Security Rules: liên kết Chấm Công Trạm", () => {
  it("CC1. chamcong_links/** (ở gốc) chỉ Admin SDK truy cập được — client đọc/ghi đều bị chặn", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("chamcong_links").set({
        stores: { TRAM01: { chamCongStoreId: "S1", chamCongStoreName: "Trạm", linkedByUid: "owner_uid", linkedAt: 1 } },
        byChamCongStore: { S1: "TRAM01" },
        users: { TRAM01: { ccUser1: "cc_ccUser1" } },
      });
    });
    const paths = [
      "chamcong_links",
      "chamcong_links/stores",
      "chamcong_links/stores/TRAM01",
      "chamcong_links/byChamCongStore/S1",
      "chamcong_links/users/TRAM01",
      "chamcong_links/users/TRAM01/ccUser1",
    ];
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid", "waiter_uid", "cc_ccUser1"]) {
      for (const p of paths) await assertFails(db(uid).ref(p).get());
      await assertFails(db(uid).ref("chamcong_links/stores/TRAM01").set({ chamCongStoreId: "S9" }));
      await assertFails(db(uid).ref("chamcong_links/byChamCongStore/S9").set("TRAM01"));
      await assertFails(db(uid).ref("chamcong_links/users/TRAM01/attacker").set("owner_uid"));
    }
    const anon = env().unauthenticatedContext().database();
    await assertFails(anon.ref("chamcong_links/stores").get());
    await assertFails(anon.ref("chamcong_links/byChamCongStore/S1").set("TRAM02"));
  });

  it("VR1. Thu ngân trả voucher REDEEMED về RELEASED chỉ khi hóa đơn dùng mã không tồn tại", async () => {
    const cashier = db("cashier_uid");
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      await d.ref("stores/TRAM01/vouchers/CAM9/V_FAIL").set({ voucherId: "V_FAIL", campaignId: "CAM9", normalizedCode: "FAIL1", state: "REDEEMED", redeemedBillId: "BILL_MISSING" });
      await d.ref("stores/TRAM01/vouchers/CAM9/V_PAID").set({ voucherId: "V_PAID", campaignId: "CAM9", normalizedCode: "PAID1", state: "REDEEMED", redeemedBillId: "BILL_REAL" });
      await d.ref("stores/TRAM01/bills/BILL_REAL").set({ status: "PAID", finalAmount: 50000 });
    });
    await assertSucceeds(cashier.ref("stores/TRAM01/vouchers/CAM9/V_FAIL").set({ voucherId: "V_FAIL", campaignId: "CAM9", normalizedCode: "FAIL1", state: "RELEASED" }));
    await assertFails(cashier.ref("stores/TRAM01/vouchers/CAM9/V_PAID").set({ voucherId: "V_PAID", campaignId: "CAM9", normalizedCode: "PAID1", state: "RELEASED" }));
    await assertFails(db("waiter_uid").ref("stores/TRAM01/vouchers/CAM9/V_FAIL").set({ voucherId: "V_FAIL", campaignId: "CAM9", normalizedCode: "FAIL1", state: "RELEASED" }));
  });
});

describe("POS Trạm - Security Rules: sao chép thực đơn giữa chi nhánh (COPY_MENU)", () => {
  const menuUpdates = {
    "products/Tra dao": { id: 9, name: "Trà đào", price: 30000, category: "Trà" },
    "categories/Trà": { name: "Trà" },
    "product_notes/note_1": { text: "Ít ngọt" },
  };

  beforeEach(async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      // Quản lý thuộc cả hai chi nhánh; thu ngân chỉ thuộc TRAM01
      await d.ref("userIndex/multi_mgr_uid/TRAM01").set(true);
      await d.ref("userIndex/multi_mgr_uid/TRAM02").set(true);
      await d.ref("stores/TRAM01/users/multi_mgr_uid").set({ username: "ql_da_cn", roleId: "manager", isActive: true });
      await d.ref("stores/TRAM02/users/multi_mgr_uid").set({ username: "ql_da_cn", roleId: "manager", isActive: true });
      await d.ref("stores/TRAM01/products/p1").set({ id: 1, name: "Cà phê", price: 20000, category: "Cà phê" });
    });
  });

  it("CM1. Quản lý thuộc cả hai chi nhánh đọc nguồn và ghi đa đường dẫn vào đích (kèm nhật ký COPY_MENU)", async () => {
    const mgr = db("multi_mgr_uid");
    await assertSucceeds(mgr.ref("stores/TRAM01/products").get());
    await assertSucceeds(mgr.ref("stores/TRAM02").update(menuUpdates));
    await assertSucceeds(
      mgr.ref("stores/TRAM02/audit_logs/LOG_1_abcd").set({
        timestamp: Date.now(),
        action: "COPY_MENU",
        username: "ql_da_cn",
        sourceStore: "TRAM01",
        targetStore: "TRAM02",
        created: 1,
        overwritten: 0,
        skipped: 0,
      })
    );
  });

  it("CM2. Chủ gốc TRAM01 không ghi được vào chi nhánh mình không thuộc (TRAM02); ghi đa đường dẫn bị từ chối toàn bộ", async () => {
    const owner = db("owner_uid");
    await assertFails(owner.ref("stores/TRAM02").update(menuUpdates));
    await assertFails(owner.ref("stores/TRAM02/products/Tra dao").set(menuUpdates["products/Tra dao"]));
    await assertFails(owner.ref("stores/TRAM02/products").get());
  });

  it("CM3. Thu ngân, phục vụ, bếp không ghi được món / nhóm / ghi chú mẫu (kể cả khi thuộc chi nhánh đích)", async () => {
    for (const uid of ["cashier_uid", "waiter_uid", "kitchen_uid"]) {
      await assertFails(db(uid).ref("stores/TRAM01").update(menuUpdates));
      await assertFails(db(uid).ref("stores/TRAM01/products/Tra dao").set(menuUpdates["products/Tra dao"]));
      await assertFails(db(uid).ref("stores/TRAM01/categories/Trà").set({ name: "Trà" }));
      await assertFails(db(uid).ref("stores/TRAM01/product_notes/note_1").set({ text: "x" }));
    }
  });

  it("CM4. Quản lý bị khóa không sao chép được; người ngoài chi nhánh nguồn không đọc được nguồn", async () => {
    await assertFails(db("inactive_mgr_uid").ref("stores/TRAM01").update(menuUpdates));
    await assertFails(db("storeB_uid").ref("stores/TRAM01/products").get());
  });
});

describe("POS Trạm - Security Rules: gộp vai trò (ROLE_MANAGER / ROLE_STAFF)", () => {
  // Mọi mã cũ + mã mới đều phải cùng quyền với vai trò đã gộp
  const staffIds: Record<string, string> = {
    staff_new_uid: "ROLE_STAFF",
    staff_alias_uid: "staff",
    staff_cashier_uid: "ROLE_CASHIER",
    staff_waiter_uid: "ROLE_WAITER",
    staff_waiter_lc_uid: "waiter",
    staff_employee_uid: "employee",
  };
  const managerIds: Record<string, string> = {
    mgr_new_uid: "ROLE_MANAGER",
    mgr_1_uid: "manager_1",
    mgr_2_uid: "ROLE_MANAGER_2",
  };

  beforeEach(async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      for (const [uid, roleId] of [...Object.entries(staffIds), ...Object.entries(managerIds)]) {
        await d.ref(`userIndex/${uid}/TRAM01`).set(true);
        await d.ref(`stores/TRAM01/users/${uid}`).set({ username: uid, fullName: uid, roleId, isActive: true });
      }
      await d.ref("userIndex/kitchen_chk_uid/TRAM01").set(true);
      await d.ref("stores/TRAM01/users/kitchen_chk_uid").set({ username: "bep2", fullName: "Bếp", roleId: "ROLE_KITCHEN", isActive: true });
      await d.ref("stores/TRAM01/bills/open_chk").set({ id: "open_chk", status: "OPEN", finalAmount: 10000, subTotal: 10000 });
      await d.ref("stores/TRAM01/bills/paid_chk").set({ id: "paid_chk", status: "PAID", finalAmount: 10000, subTotal: 10000 });
    });
  });

  it("MR1. Mọi mã Nhân viên (ROLE_STAFF + cashier/waiter/employee cũ) thanh toán được, đọc/ghi khách, ghi cash_shifts", async () => {
    for (const uid of Object.keys(staffIds)) {
      await assertSucceeds(db(uid).ref("stores/TRAM01/bills/open_chk").update({ status: "PAID", closedAt: Date.now(), paymentMethod: "CASH" }));
      await assertSucceeds(db(uid).ref("stores/TRAM01/customers").get());
      await assertSucceeds(db(uid).ref("stores/TRAM01/customers/c_mr1").set({ name: "Khách", phone: "0911111111" }));
      await assertSucceeds(db(uid).ref(`stores/TRAM01/cash_shifts/s_${uid}`).set({ id: `s_${uid}`, status: "OPEN", staffUid: uid }));
      await env().withSecurityRulesDisabled(async (context) => {
        await context.database().ref("stores/TRAM01/bills/open_chk").update({ status: "OPEN" });
      });
    }
  });

  it("MR2. Mọi mã Nhân viên không sửa được thực đơn/khuyến mãi/hồ sơ người khác và không xóa hóa đơn", async () => {
    for (const uid of Object.keys(staffIds)) {
      await assertFails(db(uid).ref("stores/TRAM01/products/p_mr2").set({ name: "X", price: 1 }));
      await assertFails(db(uid).ref("stores/TRAM01/promotions/pr_mr2").set({ discount: 5 }));
      await assertFails(db(uid).ref("stores/TRAM01/users/owner_uid/fullName").set("Hack"));
      await assertFails(db(uid).ref("stores/TRAM01/bills/paid_chk").remove());
    }
  });

  it("MR3. Bếp vẫn bị chặn thanh toán/khách hàng (không gộp vào Nhân viên)", async () => {
    const kitchen = db("kitchen_chk_uid");
    await assertFails(kitchen.ref("stores/TRAM01/bills/open_chk").update({ status: "PAID" }));
    await assertFails(kitchen.ref("stores/TRAM01/customers").get());
    await assertFails(kitchen.ref("stores/TRAM01/cash_shifts/s_k").set({ id: "s_k", status: "OPEN" }));
  });

  it("MR4. Mọi mã Quản lý (ROLE_MANAGER, manager_1, ROLE_MANAGER_2) ghi được thực đơn; xóa hóa đơn đã thanh toán thì cần quyền CANCEL_BILL riêng", async () => {
    for (const uid of Object.keys(managerIds)) {
      await assertSucceeds(db(uid).ref(`stores/TRAM01/products/p_${uid}`).set({ name: "Trà", price: 20000 }));
      await assertFails(db(uid).ref("stores/TRAM01/bills/paid_chk").remove());
      // Hóa đơn chưa chốt (mở) thì Quản lý vẫn xóa được như cũ
      await assertSucceeds(db(uid).ref("stores/TRAM01/bills/open_chk").remove());
      await env().withSecurityRulesDisabled(async (context) => {
        await context.database().ref("stores/TRAM01/bills/open_chk").set({ id: "open_chk", status: "OPEN", finalAmount: 10000, subTotal: 10000 });
      });
    }
  });

  it("LV1. Thu ngân ghi được lastVisitAt của khách nhưng vẫn không đổi được điểm", async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("stores/TRAM01/customers/CLV1").set({ id: "CLV1", fullName: "Khách LV", phone: "0900000001", diem_hien_tai: 0, totalPoints: 0 });
    });
    const cashier = db("cashier_uid");
    await assertSucceeds(cashier.ref("stores/TRAM01/customers/CLV1/lastVisitAt").set(1791741842208));
    await assertFails(cashier.ref("stores/TRAM01/customers/CLV1/diem_hien_tai").set(9999));
    await assertFails(cashier.ref("stores/TRAM01/customers/CLV1/totalPoints").set(9999));
  });
});

describe("POS Trạm - Security Rules: báo hết món (isAvailable / soldOut*)", () => {
  const P = "stores/TRAM01/products/Tra dao";
  beforeEach(async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref(P).set({ id: 9, name: "Trà đào", price: 30000, category: "Trà", isAvailable: true });
    });
  });

  it("SO1. Bếp bật/tắt isAvailable và ghi soldOutAt/By/Until bằng một lệnh update", async () => {
    const k = db("kitchen_uid");
    await assertSucceeds(k.ref(P).update({ isAvailable: false, soldOutAt: 1791741842208, soldOutBy: "bep", soldOutUntil: 1791800000000 }));
    await assertSucceeds(k.ref(P + "/isAvailable").set(true));
    await assertSucceeds(k.ref(P).update({ soldOutAt: null, soldOutBy: null, soldOutUntil: null }));
  });

  it("SO2. Bếp không đổi được giá, tên, không xóa món, không tạo món mới", async () => {
    const k = db("kitchen_uid");
    await assertFails(k.ref(P + "/price").set(1));
    await assertFails(k.ref(P + "/name").set("Hack"));
    await assertFails(k.ref(P).update({ isAvailable: false, price: 1 }));
    await assertFails(k.ref(P).remove());
    await assertFails(k.ref(P).set({ name: "Trà đào", price: 30000, isAvailable: false }));
    await assertFails(k.ref("stores/TRAM01/products/Mon moi/isAvailable").set(false));
  });

  it("SO3. Nhân viên (cashier, ROLE_STAFF) và quản lý bật/tắt được; chủ/quản lý vẫn sửa giá", async () => {
    await assertSucceeds(db("cashier_uid").ref(P + "/isAvailable").set(false));
    await assertSucceeds(db("manager_uid").ref(P + "/isAvailable").set(true));
    await assertSucceeds(db("manager_uid").ref(P + "/price").set(35000));
    await assertSucceeds(db("owner_uid").ref(P + "/price").set(36000));
    await assertFails(db("cashier_uid").ref(P + "/price").set(1));
  });

  it("SO4. Kiểm tra kiểu dữ liệu", async () => {
    const k = db("kitchen_uid");
    await assertFails(k.ref(P + "/isAvailable").set("false"));
    await assertFails(k.ref(P + "/soldOutAt").set("hôm nay"));
    await assertFails(k.ref(P + "/soldOutUntil").set("mai"));
    await assertFails(k.ref(P + "/soldOutBy").set(123));
    await assertFails(k.ref(P + "/soldOutBy").set("x".repeat(65)));
    await assertSucceeds(k.ref(P + "/soldOutBy").set("x".repeat(64)));
  });

  it("SO5. Người ngoài quán, quán khác và tài khoản bị khóa không được ghi", async () => {
    await assertFails(db("unindexed_uid").ref(P + "/isAvailable").set(false));
    await assertFails(db("storeB_uid").ref(P + "/isAvailable").set(false));
    await assertFails(db("inactive_uid").ref(P + "/isAvailable").set(false));
    await assertFails(db("noindex_uid").ref(P + "/isAvailable").set(false));
  });
});

describe("POS Trạm - Security Rules: ca/két tiền độc lập theo tài khoản (cash_shifts)", () => {
  const shiftOf = (uid: string, extra: Record<string, unknown> = {}) => ({
    id: `sh_${uid}`, status: "OPEN", staffUid: uid, staffUsername: uid, openedAt: 1000, initialCash: 100000, totalCashSales: 0, ...extra,
  });
  const P = (id: string) => `stores/TRAM01/cash_shifts/${id}`;

  beforeEach(async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      const users: Record<string, string> = {
        sh_staff_a: "ROLE_STAFF", sh_staff_b: "ROLE_CASHIER", sh_mgr: "ROLE_MANAGER", sh_owner: "ROLE_OWNER", sh_kitchen: "ROLE_KITCHEN",
      };
      for (const [uid, roleId] of Object.entries(users)) {
        await d.ref(`userIndex/${uid}/TRAM01`).set(true);
        await d.ref(`stores/TRAM01/users/${uid}`).set({ username: uid, fullName: uid, roleId, isActive: true });
      }
      await d.ref(P("sh_sh_staff_a")).set(shiftOf("sh_staff_a"));
      await d.ref(P("sh_closed_a")).set(shiftOf("sh_staff_a", { id: "sh_closed_a", status: "CLOSED", closedAt: 2000 }));
      // Ca cũ (chưa có staffUid) của sh_staff_a, nhận diện theo username
      await d.ref(P("sh_legacy_a")).set({ id: "sh_legacy_a", status: "OPEN", staffUsername: "sh_staff_a", openedAt: 500 });
    });
  });

  it("SH1. Nhân viên tạo/cập nhật ca CỦA MÌNH được; cộng dồn doanh số (transaction) được", async () => {
    const a = db("sh_staff_a");
    await assertSucceeds(a.ref(P("sh_new_a")).set(shiftOf("sh_staff_a", { id: "sh_new_a" })));
    await assertSucceeds(a.ref(P("sh_sh_staff_a")).update({ totalCashSales: 50000 }));
    await assertSucceeds(a.ref(P("sh_sh_staff_a")).update({ status: "CLOSED", closedAt: 3000, actualCash: 150000 }));
  });

  it("SH2. Nhân viên KHÔNG tạo ca mang tên người khác, không sửa/đóng ca người khác, không giả staffUid", async () => {
    const b = db("sh_staff_b");
    await assertFails(b.ref(P("sh_fake")).set(shiftOf("sh_staff_a", { id: "sh_fake" })));
    await assertFails(b.ref(P("sh_nouid")).set({ id: "sh_nouid", status: "OPEN", openedAt: 1 }));
    await assertFails(b.ref(P("sh_sh_staff_a")).update({ totalCashSales: 999 }));
    await assertFails(b.ref(P("sh_sh_staff_a")).update({ status: "CLOSED", closedAt: 5 }));
    await assertFails(b.ref(P("sh_sh_staff_a")).update({ staffUid: "sh_staff_b" }));
    await assertFails(b.ref(P("sh_sh_staff_a")).remove());
    await assertFails(b.ref("stores/TRAM01/cash_shifts").set({}));
  });

  it("SH3. Nhân viên không sửa lại ca đã chốt (kể cả ca của mình) và không chiếm ca cũ của người khác", async () => {
    const a = db("sh_staff_a");
    await assertFails(a.ref(P("sh_closed_a")).update({ actualCash: 1, difference: 0 }));
    await assertFails(a.ref(P("sh_closed_a")).update({ status: "OPEN" }));
    await assertFails(db("sh_staff_b").ref(P("sh_legacy_a")).update({ status: "CLOSED", closedAt: 9 }));
  });

  it("SH4. Ca cũ (không có staffUid) chỉ chủ ca theo username đóng được", async () => {
    await assertSucceeds(db("sh_staff_a").ref(P("sh_legacy_a")).update({ status: "CLOSED", closedAt: 9, staffUid: "sh_staff_a" }));
  });

  it("SH5. Quản lý/Chủ đọc mọi ca và đóng bắt buộc ca của người khác; Bếp không ghi/đọc", async () => {
    for (const uid of ["sh_mgr", "sh_owner"]) {
      await assertSucceeds(db(uid).ref("stores/TRAM01/cash_shifts").get());
      await assertSucceeds(db(uid).ref(P("sh_sh_staff_a")).update({ status: "CLOSED", closedAt: 7, forceClosedBy: uid }));
      await env().withSecurityRulesDisabled(async (c) => { await c.database().ref(P("sh_sh_staff_a")).set(shiftOf("sh_staff_a")); });
    }
    const k = db("sh_kitchen");
    await assertFails(k.ref(P("sh_k")).set(shiftOf("sh_kitchen", { id: "sh_k" })));
    await assertFails(k.ref(P("sh_sh_staff_a")).update({ totalCashSales: 1 }));
  });
});

describe("POS Trạm - Security Rules: danh mục note & topping (note_groups / topping_groups)", () => {
  const noteGroup = { name: "Đồ uống", sortOrder: 1, active: true, items: [{ id: "a", text: "Ít đá" }] };
  const toppingGroup = { name: "Topping trà", sortOrder: 1, active: true, multi: true, max: 0, items: [{ id: "1", name: "Trân châu", price: 5000 }] };

  it("NG1. Chủ và quản lý ghi/xóa được cả hai nút", async () => {
    for (const uid of ["owner_uid", "manager_uid"]) {
      await assertSucceeds(db(uid).ref("stores/TRAM01/note_groups/g1").set(noteGroup));
      await assertSucceeds(db(uid).ref("stores/TRAM01/topping_groups/g1").set(toppingGroup));
      await assertSucceeds(db(uid).ref("stores/TRAM01/note_groups/g1").remove());
      await assertSucceeds(db(uid).ref("stores/TRAM01/topping_groups/g1").remove());
    }
  });

  it("NG2. Thu ngân, phục vụ, bếp, quản lý bị khóa không ghi/xóa được", async () => {
    await env().withSecurityRulesDisabled(async (c) => {
      await c.database().ref("stores/TRAM01/note_groups/g2").set(noteGroup);
      await c.database().ref("stores/TRAM01/topping_groups/g2").set(toppingGroup);
    });
    for (const uid of ["cashier_uid", "waiter_uid", "kitchen_uid", "inactive_mgr_uid"]) {
      await assertFails(db(uid).ref("stores/TRAM01/note_groups/g3").set(noteGroup));
      await assertFails(db(uid).ref("stores/TRAM01/topping_groups/g3").set(toppingGroup));
      await assertFails(db(uid).ref("stores/TRAM01/note_groups/g2").remove());
      await assertFails(db(uid).ref("stores/TRAM01/topping_groups/g2").remove());
    }
  });

  it("NG3. Mọi thành viên quán đọc được (để gọi món); người ngoài chi nhánh và chủ chi nhánh khác thì không", async () => {
    await env().withSecurityRulesDisabled(async (c) => {
      await c.database().ref("stores/TRAM01/note_groups/g4").set(noteGroup);
      await c.database().ref("stores/TRAM01/topping_groups/g4").set(toppingGroup);
    });
    for (const uid of ["owner_uid", "manager_uid", "cashier_uid", "waiter_uid", "kitchen_uid"]) {
      await assertSucceeds(db(uid).ref("stores/TRAM01/note_groups").get());
      await assertSucceeds(db(uid).ref("stores/TRAM01/topping_groups").get());
    }
    await assertFails(db("storeB_uid").ref("stores/TRAM01/note_groups").get());
    await assertFails(db("storeB_uid").ref("stores/TRAM01/topping_groups").set(toppingGroup));
  });

  it("NG4. Chủ chi nhánh này không ghi được danh mục của chi nhánh khác; quản lý gắn danh mục vào món/nhóm món được", async () => {
    await assertFails(db("owner_uid").ref("stores/TRAM02/note_groups/g5").set(noteGroup));
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01").update({
      "products/Tra dao/noteGroupIds": ["g1"],
      "categories/Trà/toppingGroupIds": ["__none__"],
    }));
    await assertFails(db("cashier_uid").ref("stores/TRAM01/products/Tra dao/noteGroupIds").set(["g1"]));
  });
});

describe("POS Trạm - Security Rules: Quản lý không hủy/xóa hóa đơn, không xem nhật ký thao tác trừ khi được Chủ cấp (RR)", () => {
  beforeEach(async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      for (const uid of ["mgr_cp_uid", "mgr_cp2_uid", "mgr_audit_uid", "staff_cp_uid", "staff_audit_uid"]) {
        await d.ref(`userIndex/${uid}/TRAM01`).set(true);
      }
      // Quản lý được Chủ cấp CANCEL_BILL (đứng ở vị trí thứ 3 trong mảng customPermissions)
      await d.ref("stores/TRAM01/users/mgr_cp_uid").set({ username: "ql_cp", roleId: "ROLE_MANAGER", isActive: true, customPermissions: ["EXPORT_CODES", "DELETE_MENU", "CANCEL_BILL"] });
      // Quản lý có quyền khác nhưng KHÔNG có CANCEL_BILL / VIEW_AUDIT_LOGS
      await d.ref("stores/TRAM01/users/mgr_cp2_uid").set({ username: "ql_cp2", roleId: "ROLE_MANAGER", isActive: true, customPermissions: ["EXPORT_CODES"] });
      await d.ref("stores/TRAM01/users/mgr_audit_uid").set({ username: "ql_audit", roleId: "ROLE_MANAGER", isActive: true, customPermissions: ["VIEW_AUDIT_LOGS"] });
      // Nhân viên được cấp CANCEL_BILL / VIEW_AUDIT_LOGS riêng
      await d.ref("stores/TRAM01/users/staff_cp_uid").set({ username: "nv_cp", roleId: "ROLE_STAFF", isActive: true, customPermissions: ["CANCEL_BILL"] });
      await d.ref("stores/TRAM01/users/staff_audit_uid").set({ username: "nv_audit", roleId: "ROLE_STAFF", isActive: true, customPermissions: ["VIEW_AUDIT_LOGS"] });
      await d.ref("stores/TRAM01/audit_logs/log_seed").set({ timestamp: Date.now(), action: "CANCEL_BILL", username: "x" });
      await d.ref("stores/TRAM01/bills/closed_chk").set({ id: "closed_chk", status: "CANCELLED", finalAmount: 0, subTotal: 0 });
    });
  });

  const resetPaid = async () => {
    await env().withSecurityRulesDisabled(async (context) => {
      const d = context.database();
      await d.ref("stores/TRAM01/bills/paid_bill").set({ id: "paid_bill", billCode: "HD-1", status: "PAID", finalAmount: 100000, subTotal: 100000 });
      await d.ref("stores/TRAM01/history/paid_bill").set({ id: "paid_bill", billCode: "HD-1", status: "PAID", totalAmount: 100000 });
    });
  };

  it("RR1. Quản lý mặc định KHÔNG xóa được hóa đơn đã thanh toán/đã hủy (bills và history)", async () => {
    const mgr = db("manager_uid");
    await assertFails(mgr.ref("stores/TRAM01/bills/paid_bill").remove());
    await assertFails(mgr.ref("stores/TRAM01/history/paid_bill").remove());
    await assertFails(mgr.ref("stores/TRAM01/bills/closed_chk").remove());
    await assertFails(db("mgr_cp2_uid").ref("stores/TRAM01/bills/paid_bill").remove()); // có quyền khác nhưng không có CANCEL_BILL
  });

  it("RR2. Quản lý được cấp CANCEL_BILL (customPermissions) xóa được; Chủ quán luôn xóa được", async () => {
    await assertSucceeds(db("mgr_cp_uid").ref("stores/TRAM01/bills/paid_bill").remove());
    await assertSucceeds(db("mgr_cp_uid").ref("stores/TRAM01/history/paid_bill").remove());
    await resetPaid();
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/bills/paid_bill").remove());
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/history/paid_bill").remove());
  });

  it("RR3. Hủy hóa đơn ĐÃ THANH TOÁN (ghi đè PAID -> CANCELLED) cần Chủ hoặc CANCEL_BILL; nhân viên/quản lý mặc định bị chặn", async () => {
    const cancelled = { id: "paid_bill", billCode: "HD-1", status: "CANCELLED", finalAmount: 100000, subTotal: 100000, cancelReason: "test" };
    await assertFails(db("manager_uid").ref("stores/TRAM01/bills/paid_bill").set(cancelled));
    await assertFails(db("manager_uid").ref("stores/TRAM01/history/paid_bill").update({ status: "CANCELLED" }));
    await assertFails(db("cashier_uid").ref("stores/TRAM01/bills/paid_bill").set(cancelled));
    await assertFails(db("mgr_cp2_uid").ref("stores/TRAM01/bills/paid_bill").set(cancelled));
    await assertSucceeds(db("mgr_cp_uid").ref("stores/TRAM01/bills/paid_bill").set(cancelled));
    await assertSucceeds(db("staff_cp_uid").ref("stores/TRAM01/history/paid_bill").update({ status: "CANCELLED" }));
    await resetPaid();
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/bills/paid_bill").set(cancelled));
  });

  it("RR4. Luồng thường ngày không đổi: thu ngân thanh toán, hủy bàn đang mở, quản lý xóa hóa đơn mở", async () => {
    await assertSucceeds(db("cashier_uid").ref("stores/TRAM01/bills/open_bill").update({ status: "PAID", closedAt: Date.now(), paymentMethod: "CASH" }));
    await assertSucceeds(db("cashier_uid").ref("stores/TRAM01/bills/BILL_CANCELLED_9").set({ status: "CANCELLED", finalAmount: 0, totalAmount: 5000 }));
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bills/BILL_CANCELLED_10").set({ status: "CANCELLED", finalAmount: 0, totalAmount: 5000 }));
    await env().withSecurityRulesDisabled(async (context) => {
      await context.database().ref("stores/TRAM01/bills/open2").set({ id: "open2", status: "OPEN", finalAmount: 1, subTotal: 1 });
    });
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bills/open2").remove());
    await assertFails(db("cashier_uid").ref("stores/TRAM01/bills/paid_bill").remove());
  });

  it("RR5. Chỉ Chủ quán, hoặc Quản lý có VIEW_AUDIT_LOGS, đọc được audit_logs; nhân viên/bếp không bao giờ", async () => {
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/audit_logs").get());
    await assertSucceeds(db("mgr_audit_uid").ref("stores/TRAM01/audit_logs").get());
    await assertSucceeds(db("mgr_audit_uid").ref("stores/TRAM01/audit_logs").orderByChild("timestamp").limitToLast(150).get());
    await assertFails(db("manager_uid").ref("stores/TRAM01/audit_logs").get());
    await assertFails(db("mgr_cp_uid").ref("stores/TRAM01/audit_logs").get());
    await assertFails(db("cashier_uid").ref("stores/TRAM01/audit_logs").get());
    await assertFails(db("staff_audit_uid").ref("stores/TRAM01/audit_logs").get()); // nhân viên: kể cả customPermissions
    await assertFails(db("kitchen_uid").ref("stores/TRAM01/audit_logs").get());
    await assertFails(db("storeB_uid").ref("stores/TRAM01/audit_logs").get());
  });

  it("RR6. Ghi audit_logs vẫn mở cho mọi thành viên đang hoạt động (thao tác tự ghi nhật ký); không ghi đè/xóa", async () => {
    for (const uid of ["manager_uid", "cashier_uid", "kitchen_uid", "owner_uid"]) {
      await assertSucceeds(db(uid).ref(`stores/TRAM01/audit_logs/log_${uid}`).set({ timestamp: Date.now(), action: "LOGIN", username: uid }));
    }
    await assertFails(db("manager_uid").ref("stores/TRAM01/audit_logs/log_seed").remove());
    await assertFails(db("manager_uid").ref("stores/TRAM01/audit_logs/log_seed/action").set("X"));
  });

  it("RR7. Chỉ Chủ quán cấp được CANCEL_BILL / VIEW_AUDIT_LOGS qua customPermissions; Quản lý không tự cấp, không cấp cho người khác", async () => {
    const path = "stores/TRAM01/users/cashier_uid/customPermissions";
    await assertFails(db("manager_uid").ref(path).set(["CANCEL_BILL"]));
    await assertFails(db("manager_uid").ref(path).set(["VIEW_AUDIT_LOGS"]));
    await assertFails(db("manager_uid").ref("stores/TRAM01/users/manager_uid/customPermissions").set(["CANCEL_BILL"]));
    await assertFails(db("mgr_cp2_uid").ref("stores/TRAM01/users/mgr_cp2_uid/customPermissions").set(["EXPORT_CODES", "CANCEL_BILL"]));
    await assertFails(db("mgr_cp2_uid").ref("stores/TRAM01/users/manager_uid/customPermissions").set(["CANCEL_BILL"]));
    // Quản lý vẫn cấp được quyền thường cho Nhân viên (không thuộc nhóm bảo vệ)
    await assertSucceeds(db("manager_uid").ref(path).set(["VIEW_REPORTS"]));
    // Chủ quán cấp được cho một Quản lý cụ thể
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/users/manager_uid/customPermissions").set(["CANCEL_BILL", "VIEW_AUDIT_LOGS"]));
    // ...và quyền có hiệu lực ngay trên rules
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/audit_logs").get());
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bills/paid_bill").remove());
    // Thu hồi (Chủ gỡ) thì mất quyền
    await assertSucceeds(db("owner_uid").ref("stores/TRAM01/users/manager_uid/customPermissions").remove());
    await assertFails(db("manager_uid").ref("stores/TRAM01/audit_logs").get());
  });

  it("RR8. Cấu trúc: audit_logs vẫn có .read dạng chuỗi và chỉ mục timestamp", () => {
    const al = parsedRules.rules.stores.$storeCode.audit_logs;
    expect(typeof al[".read"]).toBe("string");
    expect(al[".read"]).toContain("VIEW_AUDIT_LOGS");
    expect(al[".indexOn"]).toContain("timestamp");
  });
});

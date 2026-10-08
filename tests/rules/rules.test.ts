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
    await d.ref("stores/TRAM01/users/waiter_uid").set({ username: "phucvu", fullName: "Phục Vụ", roleId: "waiter", isActive: true });
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
    expect(topLevelKeys.sort()).toEqual(["stores", "userIndex"].sort());
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
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/bills/paid_bill").remove());
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

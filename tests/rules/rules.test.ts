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
    // Quản lý điều chỉnh điểm được
    await assertSucceeds(db("manager_uid").ref(C).update({ diem_hien_tai: 10, currentPoints: 10 }));
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
    // Quản lý tạo / đặt điểm tùy ý được
    await assertSucceeds(db("manager_uid").ref("stores/TRAM01/customers/KH_VIP").set({ ...fresh, id: "KH_VIP", diem_hien_tai: 800, currentPoints: 800, totalPoints: 800 }));
    await assertSucceeds(db("manager_uid").ref(C).update({ diem_hien_tai: 999, currentPoints: 999, totalPoints: 999 }));
  });

  it("LS2. Thu ngân đổi điểm (giảm) kèm khóa thao tác và lastRedeem đúng", async () => {
    await seedLoyalty();
    const cashier = db("cashier_uid");
    const redeem = {
      ...baseCustomer,
      diem_hien_tai: 30,
      currentPoints: 30,
      lastLoyaltyOp: "newbill:redeem",
      lastLoyaltyBillId: "newbill",
      lastLoyaltyType: "redeem",
      lastRedeem: { billId: "newbill", points: 20 },
    };
    await assertFails(cashier.ref(C).set({ ...redeem, lastLoyaltyOp: "fake" }));
    await assertFails(cashier.ref(C).set({ ...redeem, lastRedeem: { billId: "newbill", points: 5 } }));
    await assertFails(cashier.ref(C).set({ ...redeem, diem_hien_tai: -10, currentPoints: -10, lastRedeem: { billId: "newbill", points: 60 } }));
    await assertSucceeds(cashier.ref(C).set(redeem));
    // Lặp lại cùng khóa thao tác bị chặn
    await assertFails(cashier.ref(C).set({ ...redeem, diem_hien_tai: 20, currentPoints: 20, lastRedeem: { billId: "newbill", points: 10 } }));

    // Hoàn điểm khi hóa đơn chưa PAID: tối đa đúng số đã đổi
    const refund = { ...redeem, diem_hien_tai: 50, currentPoints: 50, lastLoyaltyOp: "newbill:refund", lastLoyaltyType: "refund" } as Record<string, unknown>;
    delete refund.lastRedeem;
    await assertFails(cashier.ref(C).set({ ...refund, diem_hien_tai: 90, currentPoints: 90 }));
    await assertSucceeds(cashier.ref(C).set(refund));
  });

  it("LS3. Tích điểm chỉ cho hóa đơn PAID của đúng khách, có giới hạn theo tiền và chỉ 1 lần", async () => {
    await seedLoyalty();
    const cashier = db("cashier_uid");
    // 2.000.000đ × 1% / 1000đ = 20 điểm
    const award = { ...baseCustomer, diem_hien_tai: 70, currentPoints: 70, totalPoints: 100, lastLoyaltyOp: "award_bill:award", lastLoyaltyBillId: "award_bill", lastLoyaltyType: "award" };
    await assertFails(cashier.ref(C).set({ ...award, diem_hien_tai: 500, currentPoints: 500, totalPoints: 530 }));
    await assertFails(cashier.ref(C).set({ ...award, lastLoyaltyOp: "other_cust_bill:award", lastLoyaltyBillId: "other_cust_bill" }));
    await assertFails(cashier.ref(C).set({ ...award, lastLoyaltyOp: "open_bill:award", lastLoyaltyBillId: "open_bill" }));
    await assertFails(cashier.ref(C).set({ ...award, totalPoints: 999 }));
    await assertSucceeds(cashier.ref(C).set(award));

    // Sổ cái loyalty_applied: chỉ tạo mới; sau khi có thì không cộng lại được cho hóa đơn đó
    const ledger = "stores/TRAM01/loyalty_applied/award_bill/award";
    await assertFails(db("waiter_uid").ref(ledger).set({ customerId: "KH1", points: 20 }));
    await assertFails(cashier.ref("stores/TRAM01/loyalty_applied/award_bill/bonus").set({ customerId: "KH1", points: 20 }));
    await assertFails(cashier.ref(ledger).set({ customerId: "KH1" }));
    await assertSucceeds(cashier.ref(ledger).set({ customerId: "KH1", points: 20, before: 50, after: 70, at: Date.now(), by: "thungan" }));
    await assertFails(cashier.ref(ledger).set({ customerId: "KH1", points: 99 }));
    await assertFails(cashier.ref(ledger).remove());
    await assertFails(
      cashier.ref(C).set({ ...award, diem_hien_tai: 90, currentPoints: 90, totalPoints: 120, lastLoyaltyOp: "award_bill:award" })
    );
    await assertSucceeds(db("manager_uid").ref(ledger).remove());
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
    "storeInfo", "users", "products", "categories", "product_notes", "zones", "tables", "bills", "history",
    "kitchen_orders", "online_orders", "cash_shifts", "promotions", "campaigns", "vouchers", "voucher_lookup",
    "campaign_counters", "customer_campaign_counters", "inventory", "catalog_items", "stock_balances",
    "stock_events", "bill_stock_applied", "bill_stock_lines", "stock_retry_queue", "counters",
    "inventory_documents", "supplier_ledger", "suppliers", "receipts", "loyalty_applied", "audit_logs",
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
    // Danh sách test RC1 + customers phải phủ hết nút con (thêm nút mới → cập nhật test)
    expect([...memberReadable, "customers"].sort()).toEqual(children.sort());
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
});

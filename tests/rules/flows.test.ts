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
 * MA TRẬN LUỒNG × VAI TRÒ chạy trên Rules emulator (RULES_AUDIT mục 7).
 *
 * Mỗi luồng nghiệp vụ (payload lấy từ toMap() của app Flutter và web) được thử với 7 cột:
 *   - owner        : Chủ quán (ROLE_OWNER, isRootOwner)
 *   - manager      : Quản lý (ROLE_MANAGER), không có customPermissions
 *   - manager_cp   : Quản lý được cấp CANCEL_BILL qua customPermissions (biến thể để kiểm tra cấp riêng)
 *   - staff        : Nhân viên (ROLE_STAFF)
 *   - kitchen      : Bếp / Bar (ROLE_KITCHEN)
 *   - inactive     : Nhân viên có userIndex nhưng isActive=false
 *   - nonmember    : Không có userIndex (không thuộc quán)
 *
 * Kỳ vọng (cột "tài liệu") lấy từ docs/ROLE_RULES.md, docs/PERMISSIONS_AUDIT.md và docs/RULES_AUDIT.md.
 *
 * QUY ƯỚC MISMATCH:
 *   Khi rules và tài liệu KHÔNG khớp, KHÔNG sửa rules. Ô đó được khai báo trong `mm` của luồng
 *   và test assert HÀNH VI THẬT của rules (để test xanh và bắt được thay đổi về sau),
 *   kèm chú thích "MISMATCH" + loại: LỖI RULES, LỆCH TÀI LIỆU hoặc ĐÃ BIẾT (RULES_AUDIT mục 6).
 *   Danh sách đầy đủ nằm trong docs/RULES_AUDIT.md mục 7.
 *
 * Chạy (trong thư mục gốc dự án):
 *   firebase emulators:exec --only database --project demo-tram-pos "cd tests/rules && npx vitest run"
 *
 * File này dùng projectId riêng "demo-tram-pos-flows" (RTDB namespace = projectId) để không
 * tranh dữ liệu với rules.test.ts khi vitest chạy song song các file.
 */

const PROJECT = "demo-tram-pos-flows";
const STORE = "stores/TRAM01";
const rulesPath = path.resolve(__dirname, "../../database.rules.json");
const rulesContent = fs.readFileSync(rulesPath, "utf8");

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
    throw new Error("Chưa kết nối Firebase Database Emulator. Hãy chạy qua `firebase emulators:exec --only database ...`.");
  }
  return testEnv;
}

const dbOf = (uid: string) => env().authenticatedContext(uid).database();
type Db = ReturnType<typeof dbOf>;

// ---------- Vai trò ----------
const UID = {
  owner: "m_owner",
  manager: "m_manager",
  manager_cp: "m_manager_cp",
  staff: "m_staff",
  kitchen: "m_kitchen",
  inactive: "m_inactive",
  nonmember: "m_nonmember",
} as const;
type Role = keyof typeof UID;
const ROLES = Object.keys(UID) as Role[];
const ROLE_LABEL: Record<Role, string> = {
  owner: "Chủ (ROLE_OWNER)",
  manager: "Quản lý (ROLE_MANAGER)",
  manager_cp: "Quản lý + CANCEL_BILL",
  staff: "Nhân viên (ROLE_STAFF)",
  kitchen: "Bếp (ROLE_KITCHEN)",
  inactive: "Bị khóa (isActive=false)",
  nonmember: "Không thuộc quán",
};

type Exp = Record<Role, boolean>;
/** Kỳ vọng cho luồng ghi thông thường: không phải thành viên / bị khóa luôn bị từ chối. */
function ex(owner: boolean, manager: boolean, staff: boolean, kitchen: boolean, opt: { cp?: boolean } = {}): Exp {
  return { owner, manager, manager_cp: opt.cp ?? manager, staff, kitchen, inactive: false, nonmember: false };
}

type MmKind = "LỖI RULES" | "LỆCH TÀI LIỆU" | "ĐÃ BIẾT (RULES_AUDIT §6)";
interface Mm {
  actual: boolean; // hành vi thật của rules (test assert giá trị này)
  kind: MmKind;
  note: string;
}

interface Flow {
  id: string;
  title: string;
  doc: string; // nguồn kỳ vọng
  exp: Exp;
  mm?: Partial<Record<Role, Mm>>;
  run: (d: Db, uid: string) => Promise<unknown>;
}

// ---------- Payload giống app ----------
/** Giống BillModel.toMap() (Flutter) — các trường bắt buộc tối thiểu. */
function billOf(id: string, status: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    billCode: `HD-${id}`,
    tableName: "Bàn 2",
    zone: "Tầng 1",
    createdAt: Date.now(),
    status,
    staffUsername: "nv",
    staffFullName: "Nhân viên",
    cashierName: "Nhân viên",
    orderStaff: "nv",
    subTotal: 25000,
    totalDiscount: 0,
    vatRate: 0,
    vatAmount: 0,
    finalAmount: 25000,
    paymentMethod: "CASH",
    notes: "",
    note: "",
    deletedItemsCount: 0,
    deletedItemsAmount: 0,
    ...extra,
  };
}
/** Giống TableModel.toMap(). */
function tableOf(name: string, inUse: boolean, currentOrderJson: string): Record<string, unknown> {
  return { name, zone: "Tầng 1", inUse, currentOrderJson, isReserved: false, reservationDeposit: 0, capacity: 4 };
}
/** Giống KitchenOrderModel.toMap(). */
function kitchenOrderOf(tableName: string, orderedBy: string): Record<string, unknown> {
  return { tableName, orderCode: "D-1", billCode: "HD-K", itemsJson: "[]", timestamp: Date.now(), isDone: false, pickedUp: false, orderedBy };
}
/** Giống CashShiftModel/ShiftModel.toMap(). */
function shiftOf(staffUid: string, status: string): Record<string, unknown> {
  return {
    shiftCode: `CA-${staffUid}`,
    shiftName: "Ca 1",
    storeCode: "TRAM01",
    staffUid,
    staffUsername: staffUid,
    staffFullName: staffUid,
    openedAt: 1000,
    initialCash: 100000,
    totalCashSales: 0,
    totalQrSales: 0,
    totalCardSales: 0,
    cashIn: 0,
    cashOut: 0,
    status,
    notes: "",
  };
}
/** Giống CustomerModel.toMap() (tên khóa tiếng Việt + tiếng Anh). */
function customerOf(id: string, points: number): Record<string, unknown> {
  return {
    id,
    ma_khach_hang: id,
    code: id,
    ho_ten: "Khách",
    name: "Khách",
    so_dien_thoai: "0900000000",
    phone: "0900000000",
    diem_hien_tai: points,
    currentPoints: points,
    totalPoints: points,
    ho_ten_upper: "KHÁCH",
    ngay_cap_nhat: Date.now(),
  };
}
/** Giống AuditModel.toMap(). */
function auditOf(uid: string, action: string): Record<string, unknown> {
  return {
    timestamp: Date.now(),
    username: uid,
    userFullName: uid,
    userRole: "ROLE_STAFF",
    action,
    targetType: "bill",
    targetId: "o1",
    details: "",
    isSuspicious: false,
    storeCode: "TRAM01",
  };
}

// ---------- Seed ----------
async function seed() {
  await env().clearDatabase();
  await env().withSecurityRulesDisabled(async (context) => {
    const d = context.database();
    // userIndex: mọi thành viên trừ nonmember
    for (const uid of [UID.owner, UID.manager, UID.manager_cp, UID.staff, UID.kitchen, UID.inactive]) {
      await d.ref(`userIndex/${uid}/TRAM01`).set(true);
    }
    // Hồ sơ thành viên (nonmember không có hồ sơ)
    await d.ref(`${STORE}/users/${UID.owner}`).set({ username: "admin", fullName: "Chủ quán", roleId: "ROLE_OWNER", isRootOwner: true, isActive: true });
    await d.ref(`${STORE}/users/${UID.manager}`).set({ username: "ql", fullName: "Quản lý", roleId: "ROLE_MANAGER", isActive: true });
    await d.ref(`${STORE}/users/${UID.manager_cp}`).set({ username: "ql_cp", fullName: "Quản lý CP", roleId: "ROLE_MANAGER", isActive: true, customPermissions: ["CANCEL_BILL"] });
    await d.ref(`${STORE}/users/${UID.staff}`).set({ username: "nv", fullName: "Nhân viên", roleId: "ROLE_STAFF", isActive: true });
    await d.ref(`${STORE}/users/${UID.kitchen}`).set({ username: "bep", fullName: "Bếp", roleId: "ROLE_KITCHEN", isActive: true });
    await d.ref(`${STORE}/users/${UID.inactive}`).set({ username: "nv_khoa", fullName: "NV bị khóa", roleId: "ROLE_STAFF", isActive: false });

    // Bàn, hóa đơn (mở + đã thanh toán), lịch sử, thực đơn, phiếu bếp
    await d.ref(`${STORE}/tables/T1`).set(tableOf("Bàn 1", true, "[]"));
    await d.ref(`${STORE}/bills/o1`).set(billOf("o1", "OPEN", { finalAmount: 50000, subTotal: 50000 }));
    await d.ref(`${STORE}/bills/p1`).set(billOf("p1", "PAID", { finalAmount: 100000, subTotal: 100000, closedAt: 2000 }));
    await d.ref(`${STORE}/history/p1`).set(billOf("p1", "PAID", { totalAmount: 100000 }));
    await d.ref(`${STORE}/products/p1`).set({ name: "Cà phê", price: 25000, isAvailable: true, categoryId: "c1" });
    await d.ref(`${STORE}/kitchen_orders/k1`).set(kitchenOrderOf("Bàn 1", UID.staff));

    // Ca làm việc: mỗi thành viên có ca của mình; "sh_other" là ca của người khác (không có trong quán)
    for (const uid of Object.values(UID)) {
      await d.ref(`${STORE}/cash_shifts/sh_${uid}`).set(shiftOf(uid, "OPEN"));
    }
    await d.ref(`${STORE}/cash_shifts/sh_other`).set(shiftOf("other_uid", "OPEN"));

    // Khách, khu vực, ghi chú, thông tin quán, nhật ký, tồn kho, điểm dùng chung
    await d.ref(`${STORE}/customers/c1`).set(customerOf("c1", 100));
    await d.ref(`${STORE}/zones/z1`).set({ name: "Tầng 1" });
    await d.ref(`${STORE}/product_notes/n1`).set({ name: "Ít đường" });
    await d.ref(`${STORE}/storeInfo`).set({ name: "POS Trạm" });
    await d.ref(`${STORE}/audit_logs/a_seed`).set(auditOf("seed", "SEED"));
    await d.ref(`${STORE}/stock_balances/TRAM01_ITEM1`).set({ balanceId: "TRAM01_ITEM1", branchId: "TRAM01", itemId: "ITEM1", onHandQty: 1000, reservedQty: 0, inventoryValue: 500000, averageCostScaled: 50000 });
    await d.ref("loyalty_members/x1").set({ points: 100 });
  });
}

// ---------- Ma trận luồng ----------
// Quy ước đọc: ex(owner, manager, staff, kitchen [, {cp}]); cột manager_cp mặc định = manager.
const FLOWS: Flow[] = [
  // ----- A. Bàn & gọi món -----
  {
    id: "F01",
    title: "Mở bàn và lưu order (tables/$key inUse=true, currentOrderJson)",
    doc: "ROLE_RULES §4 (Bếp không có mở bàn); PERMISSIONS_AUDIT §2 OPEN_TABLE",
    exp: ex(true, true, true, false),
    mm: {
      kitchen: { actual: true, kind: "ĐÃ BIẾT (RULES_AUDIT §6)", note: "Bếp ghi được tables/* (rules nhánh tables: mọi thành viên có newData)." },
    },
    run: (d) => d.ref(`${STORE}/tables/T2`).set(tableOf("Bàn 2", true, '[{"name":"Cà phê","qty":1}]')),
  },
  {
    id: "F02",
    title: "Tạo hóa đơn OPEN khi mở bàn",
    doc: "ROLE_RULES §4; PERMISSIONS_AUDIT §2 OPEN_TABLE/CREATE_BILL",
    exp: ex(true, true, true, false),
    mm: {
      kitchen: { actual: true, kind: "ĐÃ BIẾT (RULES_AUDIT §6)", note: "Bếp tạo bill OPEN/CANCELLED (nhánh 'không PAID' của bills cho mọi thành viên)." },
    },
    run: (d) => d.ref(`${STORE}/bills/o_new`).set(billOf("o_new", "OPEN")),
  },
  {
    id: "F03",
    title: "Gửi bếp: tạo phiếu bếp mới (kitchen_orders push)",
    doc: "PERMISSIONS_AUDIT §2 SEND_KITCHEN (Chủ, QL, NV, Bếp)",
    exp: ex(true, true, true, true),
    run: (d, uid) => d.ref(`${STORE}/kitchen_orders/k_new`).set(kitchenOrderOf("Bàn 2", uid)),
  },
  {
    id: "F04",
    title: "Bếp đánh dấu xong món (kitchen_orders/$id isDone, doneAt)",
    doc: "ROLE_RULES §4: Bếp = nhận/hoàn tất món; Nhân viên chỉ 'xem màn Bếp'",
    exp: ex(true, true, false, true),
    mm: {
      staff: {
        actual: true,
        kind: "LỖI RULES",
        note: "Mọi thành viên ghi được kitchen_orders. Tài liệu chỉ cho NV xem màn Bếp. Nếu phục vụ cần nhận món thì nên cập nhật tài liệu, còn không thì siết rules.",
      },
    },
    run: (d, uid) => d.ref(`${STORE}/kitchen_orders/k1`).update({ isDone: true, doneAt: Date.now(), pickedUpBy: uid }),
  },
  {
    id: "F05",
    title: "Xóa phiếu bếp (kitchen_orders remove)",
    doc: "RULES_AUDIT §3 / existing test 23: chỉ Quản lý xóa",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/kitchen_orders/k1`).remove(),
  },

  // ----- B. Hủy bàn đang mở, xóa hóa đơn chưa chốt -----
  {
    id: "F06",
    title: "Hủy bàn đang mở: bill OPEN -> CANCELLED",
    doc: "RULES_AUDIT §3 (hủy bàn đang mở OK); ROLE_RULES §3 (QL hủy bàn mở); NV theo yêu cầu chủ",
    exp: ex(true, true, true, false),
    mm: {
      kitchen: { actual: true, kind: "ĐÃ BIẾT (RULES_AUDIT §6)", note: "Bếp sửa được bill OPEN -> CANCELLED." },
    },
    run: (d) => d.ref(`${STORE}/bills/o1`).update({ status: "CANCELLED", cancelledAt: Date.now() }),
  },
  {
    id: "F07",
    title: "Xóa hóa đơn CHƯA CHỐT (bills/$id remove, status OPEN)",
    doc: "ROLE_RULES §3 (QL xóa bill chưa chốt được); RULES_AUDIT §4 (NV xóa hóa đơn: bị chặn)",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/bills/o1`).remove(),
  },

  // ----- C. Thanh toán -----
  {
    id: "F08",
    title: "Thanh toán: bills PAID + history + tables clear + bill_stock_applied + bill_seq (multi-path)",
    doc: "PERMISSIONS_AUDIT §4 CREATE_BILL (QL, NV); Bếp không thanh toán (ROLE_RULES §4)",
    exp: ex(true, true, true, false),
    run: (d, uid) =>
      d.ref(STORE).update({
        "bills/pay1": billOf("pay1", "PAID", { closedAt: Date.now(), staffUid: uid }),
        "history/pay1": billOf("pay1", "PAID", { totalAmount: 25000, staffUid: uid }),
        "tables/T1": tableOf("Bàn 1", false, "[]"),
        "bill_stock_applied/pay1": true,
        "counters/bill_seq/260101": 1,
      }),
  },
  {
    id: "F09",
    title: "Sửa hóa đơn ĐÃ thanh toán (bills/p1 PAID -> PAID, đổi finalAmount)",
    doc: "PERMISSIONS_AUDIT §3 (NV không sửa hóa đơn đã thanh toán); EDIT_BILL: QL/Chủ",
    exp: ex(true, true, false, false),
    mm: {
      staff: {
        actual: true,
        kind: "ĐÃ BIẾT (RULES_AUDIT §6)",
        note: "Nhân viên sửa được bill PAID bằng ghi PAID->PAID (rules chỉ chặn chuyển sang CANCELLED).",
      },
    },
    run: (d) => d.ref(`${STORE}/bills/p1`).update({ finalAmount: 90000 }),
  },

  // ----- D. Hủy / xóa hóa đơn đã thanh toán -----
  {
    id: "F10",
    title: "Hủy hóa đơn đã thanh toán (bills/p1 PAID -> CANCELLED)",
    doc: "ROLE_RULES §5 + PERMISSIONS_AUDIT §4: CANCEL_BILL (Chủ; QL khi được cấp)",
    exp: ex(true, false, false, false, { cp: true }),
    run: (d) => d.ref(`${STORE}/bills/p1`).update({ status: "CANCELLED", cancelledAt: Date.now() }),
  },
  {
    id: "F11",
    title: "Xóa hóa đơn đã thanh toán (bills/p1 remove)",
    doc: "ROLE_RULES §6: xóa PAID = Chủ hoặc QL có CANCEL_BILL",
    exp: ex(true, false, false, false, { cp: true }),
    run: (d) => d.ref(`${STORE}/bills/p1`).remove(),
  },
  {
    id: "F12",
    title: "Xóa bản ghi lịch sử đã thanh toán (history/p1 remove)",
    doc: "ROLE_RULES §6: history cùng quy tắc với bills",
    exp: ex(true, false, false, false, { cp: true }),
    run: (d) => d.ref(`${STORE}/history/p1`).remove(),
  },

  // ----- E. Món hết hàng, thực đơn -----
  {
    id: "F13",
    title: "Bật/tắt món hết hàng (products/$p/isAvailable)",
    doc: "ROLE_RULES §1: TOGGLE_ITEM_AVAILABILITY (Chủ, QL, NV, Bếp)",
    exp: ex(true, true, true, true),
    run: (d) => d.ref(`${STORE}/products/p1/isAvailable`).set(false),
  },
  {
    id: "F14",
    title: "Bếp đánh dấu hết hàng nhiều trường một lệnh (isAvailable + soldOutAt/By)",
    doc: "ROLE_RULES §1 / RULES_AUDIT §3 (SO1)",
    exp: ex(true, true, true, true),
    run: (d, uid) => d.ref(`${STORE}/products/p1`).update({ isAvailable: false, soldOutAt: Date.now(), soldOutBy: uid }),
  },
  {
    id: "F15",
    title: "Đổi giá món (products/$p/price)",
    doc: "PERMISSIONS_AUDIT §2 CHANGE_PRICE (Chủ, QL)",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/products/p1/price`).set(99000),
  },
  {
    id: "F16",
    title: "Thêm món mới vào thực đơn (products/$p)",
    doc: "PERMISSIONS_AUDIT §2 EDIT_MENU (Chủ, QL)",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/products/p9`).set({ name: "Món mới", price: 1000, isAvailable: true }),
  },
  {
    id: "F17",
    title: "Sao chép thực đơn (multi-path products/* trên quán)",
    doc: "PERMISSIONS_AUDIT §4 COPY_MENU (Chủ, QL)",
    exp: ex(true, true, false, false),
    run: (d) =>
      d.ref(`${STORE}/products`).update({
        cp1: { name: "Bản sao 1", price: 1000, isAvailable: true },
        cp2: { name: "Bản sao 2", price: 2000, isAvailable: true },
      }),
  },
  {
    id: "F18",
    title: "Ghi chú mẫu (product_notes/$id)",
    doc: "ROLE_RULES §1 / PERMISSIONS_AUDIT §4 MANAGE_NOTE_CATALOG (Chủ, QL)",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/product_notes/n2`).set({ name: "Ít đá" }),
  },

  // ----- F. Ca làm việc & két -----
  {
    id: "F19",
    title: "Mở ca của chính mình (cash_shifts/$id, staffUid = uid người ghi)",
    doc: "ROLE_RULES §1 / PERMISSIONS_AUDIT §4 MANAGE_CASH_SHIFT (Chủ, QL, NV)",
    exp: ex(true, true, true, false),
    run: (d, uid) => d.ref(`${STORE}/cash_shifts/sh_new_${uid}`).set(shiftOf(uid, "OPEN")),
  },
  {
    id: "F20",
    title: "Đóng ca của chính mình (update status CLOSED, actualCash)",
    doc: "PERMISSIONS_AUDIT §4 MANAGE_CASH_SHIFT",
    exp: ex(true, true, true, false),
    run: (d, uid) => d.ref(`${STORE}/cash_shifts/sh_${uid}`).update({ status: "CLOSED", closedAt: Date.now(), actualCash: 100000, difference: 0 }),
  },
  {
    id: "F21",
    title: "Mở ca mang staffUid của người khác",
    doc: "ROLE_RULES §4: NV không ca của người khác; QL điều hành ca",
    exp: ex(true, true, false, false),
    run: (d, uid) => d.ref(`${STORE}/cash_shifts/sh_fake_${uid}`).set(shiftOf("other_uid", "OPEN")),
  },
  {
    id: "F22",
    title: "Đóng ca của người khác (cash_shifts/sh_other update)",
    doc: "ROLE_RULES §4 (ca của người khác: NV không); QL/Chủ điều hành",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/cash_shifts/sh_other`).update({ status: "CLOSED", closedAt: Date.now() }),
  },
  {
    id: "F23",
    title: "Đọc ca của người khác (cash_shifts/sh_other get)",
    doc: "ROLE_RULES §1: ca/hóa đơn của NV chỉ của mình; Bếp không có ca/két",
    exp: ex(true, true, false, false),
    mm: {
      staff: {
        actual: true,
        kind: "ĐÃ BIẾT (RULES_AUDIT §6)",
        note: "cash_shifts.read mở cho mọi thành viên (app cần đọc ca để mở ca). Lệch ROLE_RULES §1; UI tự lọc.",
      },
      kitchen: {
        actual: true,
        kind: "ĐÃ BIẾT (RULES_AUDIT §6)",
        note: "Bếp đọc được cash_shifts (RULES_AUDIT §6). Tài liệu ROLE_RULES: Bếp không có ca/két.",
      },
    },
    run: (d) => d.ref(`${STORE}/cash_shifts/sh_other`).get(),
  },

  // ----- G. Khách hàng -----
  {
    id: "F24",
    title: "Tạo khách mới với 0 điểm (customers/$id set)",
    doc: "PERMISSIONS_AUDIT §4 MANAGE_CUSTOMERS (Chủ, QL, NV); RULES_AUDIT §3 (tạo 0 điểm)",
    exp: ex(true, true, true, false),
    run: (d) => d.ref(`${STORE}/customers/c_new`).set(customerOf("c_new", 0)),
  },
  {
    id: "F25",
    title: "Tạo khách có điểm > 0 (customers/$id set diem=500)",
    doc: "RULES_AUDIT §4: chỉnh điểm trực tiếp bị chặn (chỉ qua callable)",
    exp: ex(false, false, false, false),
    run: (d) => d.ref(`${STORE}/customers/c_bonus`).set(customerOf("c_bonus", 500)),
  },
  {
    id: "F26",
    title: "Chỉnh điểm khách có sẵn trực tiếp (diem_hien_tai 100 -> 999)",
    doc: "PERMISSIONS_AUDIT §4 ADJUST_POINTS (Chủ, QL; 'rules customers')",
    exp: ex(true, true, false, false),
    mm: {
      owner: {
        actual: false,
        kind: "LỆCH TÀI LIỆU",
        note: "PERMISSIONS_AUDIT §4 ghi ADJUST_POINTS dựa trên rules customers, nhưng rules chặn ghi điểm trực tiếp cho MỌI vai trò (RULES_AUDIT §4). Web đổi điểm qua callable (web/lib/loyalty-client.ts). Đây là lệch tài liệu, không phải lỗi rules.",
      },
      manager: {
        actual: false,
        kind: "LỆCH TÀI LIỆU",
        note: "Như trên: QL không ghi điểm trực tiếp được; tài liệu PERMISSIONS_AUDIT nói có.",
      },
      manager_cp: {
        actual: false,
        kind: "LỆCH TÀI LIỆU",
        note: "Như trên (cùng nhánh QL).",
      },
    },
    run: (d) => d.ref(`${STORE}/customers/c1`).update({ diem_hien_tai: 999, currentPoints: 999 }),
  },
  {
    id: "F27",
    title: "Sửa hồ sơ khách không đụng điểm (name)",
    doc: "RULES_AUDIT §3 (sửa hồ sơ không đụng điểm); MANAGE_CUSTOMERS",
    exp: ex(true, true, true, false),
    run: (d) => d.ref(`${STORE}/customers/c1`).update({ name: "Khách đổi tên", ho_ten: "Khách đổi tên" }),
  },
  {
    id: "F28",
    title: "Xóa khách (customers/$id remove)",
    doc: "Không có mã quyền riêng cho xóa khách; QL được xóa (theo yêu cầu chủ), NV không",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/customers/c1`).remove(),
  },
  {
    id: "F29",
    title: "Đọc khách hàng (customers/$id get)",
    doc: "PERMISSIONS_AUDIT §4 VIEW_CUSTOMERS (Chủ, QL, NV); Bếp không đọc khách",
    exp: ex(true, true, true, false),
    run: (d) => d.ref(`${STORE}/customers/c1`).get(),
  },

  // ----- H. Khu vực, thông tin quán -----
  {
    id: "F30",
    title: "Tạo / đổi tên khu vực (zones/$id)",
    doc: "PERMISSIONS_AUDIT §4 MANAGE_TABLES (Chủ, QL)",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/zones/z2`).set({ name: "Tầng 2" }),
  },
  {
    id: "F31",
    title: "Sửa thông tin cửa hàng (storeInfo/name)",
    doc: "PERMISSIONS_AUDIT §4 MANAGE_STORE_SETTINGS (chỉ Chủ); ROLE_RULES: storeInfo chỉ Chủ",
    exp: ex(true, false, false, false),
    run: (d) => d.ref(`${STORE}/storeInfo/name`).set("POS Trạm mới"),
  },

  // ----- I. Kho -----
  {
    id: "F32",
    title: "Trừ tồn kho khi bán (stock_balances giảm + stock_events SALE, multi-path)",
    doc: "RULES_AUDIT §3 (trừ kho khi bán OK, thu ngân trở lên)",
    exp: ex(true, true, true, false),
    run: (d, uid) =>
      d.ref(STORE).update({
        "stock_balances/TRAM01_ITEM1/onHandQty": 990,
        [`stock_events/ev_${uid}`]: {
          eventId: `ev_${uid}`,
          documentType: "SALE",
          qtyDeltaBase: -10,
          itemId: "ITEM1",
          branchId: "TRAM01",
          timestamp: Date.now(),
        },
      }),
  },
  {
    id: "F33",
    title: "Nhập kho tăng tồn (stock_balances onHandQty 1000 -> 1200)",
    doc: "PERMISSIONS_AUDIT §4 INVENTORY_STOCK_IN / CREATE_RECEIPT (Chủ, QL); web stock-adjust.ts",
    exp: ex(true, true, false, false),
    run: (d) => d.ref(`${STORE}/stock_balances/TRAM01_ITEM1/onHandQty`).set(1200),
  },

  // ----- J. Nhật ký thao tác -----
  {
    id: "F34",
    title: "Ghi nhật ký thao tác (audit_logs/$id tạo mới)",
    doc: "ROLE_RULES §6: ghi audit_logs mở cho mọi thành viên đang hoạt động",
    exp: ex(true, true, true, true),
    run: (d, uid) => d.ref(`${STORE}/audit_logs/a_new_${uid}`).set(auditOf(uid, "TEST_ACTION")),
  },
  {
    id: "F35",
    title: "Đọc lịch sử thao tác (audit_logs get)",
    doc: "ROLE_RULES §3/§6: Chủ, hoặc QL có VIEW_AUDIT_LOGS (mặc định QL không có)",
    exp: ex(true, false, false, false),
    run: (d) => d.ref(`${STORE}/audit_logs/a_seed`).get(),
  },
  {
    id: "F36",
    title: "Sửa hoặc xóa nhật ký đã ghi (audit_logs/a_seed update)",
    doc: "ROLE_RULES §6: nhật ký không sửa/xóa (ai cũng không)",
    exp: ex(false, false, false, false),
    run: (d) => d.ref(`${STORE}/audit_logs/a_seed`).update({ action: "SỬA" }),
  },

  // ----- K. Tài khoản & quyền -----
  {
    id: "F37",
    title: "Đọc userIndex của chính mình",
    doc: "RULES_AUDIT §3: userIndex chỉ đọc của chính mình (áp dụng cả khi không thuộc quán)",
    exp: { owner: true, manager: true, manager_cp: true, staff: true, kitchen: true, inactive: true, nonmember: true },
    run: (d, uid) => d.ref(`userIndex/${uid}`).get(),
  },
  {
    id: "F38",
    title: "Đọc userIndex của người khác",
    doc: "RULES_AUDIT §3: userIndex của người khác bị chặn",
    exp: { owner: false, manager: false, manager_cp: false, staff: false, kitchen: false, inactive: false, nonmember: false },
    run: (d, uid) => d.ref(`userIndex/${uid === UID.owner ? UID.staff : UID.owner}`).get(),
  },
  {
    id: "F39",
    title: "Đổi vai trò nhân viên khác (users/m_staff/roleId -> ROLE_KITCHEN)",
    doc: "ROLE_RULES §3: QL không quản lý nhân sự (MANAGE_USERS chỉ Chủ)",
    exp: ex(true, false, false, false),
    mm: {
      manager: {
        actual: true,
        kind: "ĐÃ BIẾT (RULES_AUDIT §6)",
        note: "Quản lý (không phải Chủ) ghi được users/{uid} của nhân viên: đổi roleId, tạo, xóa tài khoản. ROLE_RULES: QL không có quản lý nhân sự mặc định.",
      },
      manager_cp: {
        actual: true,
        kind: "ĐÃ BIẾT (RULES_AUDIT §6)",
        note: "Như QL thường (cùng nhánh rules users).",
      },
    },
    run: (d) => d.ref(`${STORE}/users/${UID.staff}/roleId`).set("ROLE_KITCHEN"),
  },
  {
    id: "F40",
    title: "Tạo tài khoản Chủ quán mới (users/new_owner roleId ROLE_OWNER)",
    doc: "ROLE_RULES §2: chỉ Chủ quản lý nhân sự/phân quyền",
    exp: ex(true, false, false, false),
    run: (d) => d.ref(`${STORE}/users/new_owner`).set({ username: "chu2", fullName: "Chủ 2", roleId: "ROLE_OWNER", isActive: true }),
  },
  {
    id: "F41",
    title: "Đọc / ghi loyalty_members từ client",
    doc: "RULES_AUDIT §4 / PERMISSIONS_AUDIT §4 LOYALTY: chỉ Cloud Function (Admin SDK)",
    exp: ex(false, false, false, false),
    run: (d) => d.ref("loyalty_members/x1").get(),
  },

  // ----- L. Đọc vận hành -----
  {
    id: "F42",
    title: "Đọc bàn, thực đơn, phiếu bếp (tables + products + kitchen_orders)",
    doc: "RULES_AUDIT §3 / RC1: mọi thành viên đọc được nút vận hành (không khách hàng)",
    exp: ex(true, true, true, true),
    run: (d) => Promise.all([d.ref(`${STORE}/tables`).get(), d.ref(`${STORE}/products`).get(), d.ref(`${STORE}/kitchen_orders`).get()]),
  },
];

// ---------- Harness ----------
beforeAll(async () => {
  const { host, port } = resolveEmulatorHost();
  try {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT,
      database: { rules: rulesContent, host, port },
    });
    await testEnv.clearDatabase();
  } catch (e) {
    throw new Error(
      `Không kết nối được Firebase Database Emulator tại ${host}:${port}. Chi tiết: ${(e as Error)?.message || e}`
    );
  }
}, 30_000);

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await seed();
});

describe("Ma trận luồng × vai trò (RULES_AUDIT mục 7)", () => {
  it("Ma trận có đủ luồng và đủ cột vai trò", () => {
    expect(FLOWS.length).toBeGreaterThanOrEqual(40);
    expect(ROLES.length).toBe(7);
    const ids = FLOWS.map((f) => f.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  for (const flow of FLOWS) {
    describe(`${flow.id} ${flow.title} [nguồn: ${flow.doc}]`, () => {
      for (const role of ROLES) {
        const docAllowed = flow.exp[role];
        const mm = flow.mm?.[role];
        // Ô khớp: assert đúng tài liệu. Ô lệch: assert hành vi thật của rules (có chú thích MISMATCH).
        const want = mm ? mm.actual : docAllowed;
        const verdict = want ? "CHO PHÉP" : "TỪ CHỐI";
        const title = mm
          ? `MISMATCH [${mm.kind}] ${role} (${ROLE_LABEL[role]}): ${verdict}, tài liệu ${docAllowed ? "cho phép" : "từ chối"}`
          : `${role} (${ROLE_LABEL[role]}): ${verdict}`;

        it(title, async () => {
          // MISMATCH (nếu mm có giá trị): ô này lệch tài liệu. Test assert HÀNH VI THẬT của rules (mm.actual),
          // không phải kỳ vọng tài liệu; ghi chú nguyên nhân nằm trong khối mm của luồng.
          const uid = UID[role];
          const p = flow.run(dbOf(uid), uid);
          if (want) {
            await assertSucceeds(p);
          } else {
            await assertFails(p);
          }
        });
      }
    });
  }
});

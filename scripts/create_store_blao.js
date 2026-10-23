#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");

const PROJECT_ID = "tramapp-36f53";
const STORE_CODE = "BLAO";
const STORE_NAME = "Trạm Blao";
const PASSWORD = process.env.TEST_PASSWORD || "12345678";
const DB_URL = "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app";
const WEB_API_KEY = "AIzaSyBWSS2o1ERO1HBnAyVZwAbzOSWNkkWa7GY";

function getAccessToken() {
  const configPath = path.join(os.homedir(), ".config/configstore/firebase-tools.json");
  if (!fs.existsSync(configPath)) {
    throw new Error("Không tìm thấy firebase-tools.json tại: " + configPath);
  }
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  return config.tokens.access_token;
}

const token = getAccessToken();

async function authApi(endpoint, body) {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/${endpoint}`, {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (data.error) {
    throw new Error(data.error.message || JSON.stringify(data.error));
  }
  return data;
}

async function rtdbPut(path, data) {
  const res = await fetch(`${DB_URL}/${path}.json?access_token=${token}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RTDB PUT ${path} thất bại: ${res.status} ${text}`);
  }
  return await res.json();
}

async function rtdbPatch(path, data) {
  const res = await fetch(`${DB_URL}/${path}.json?access_token=${token}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RTDB PATCH ${path} thất bại: ${res.status} ${text}`);
  }
  return await res.json();
}

async function getOrCreateAuthUser(email, password, displayName) {
  // Kiểm tra user đã có chưa
  try {
    const lookup = await authApi("accounts:lookup", { email: [email] });
    if (lookup.users && lookup.users.length > 0) {
      const existing = lookup.users[0];
      console.log(`- Tài khoản ${email} đã tồn tại (UID: ${existing.localId}), đang cập nhật mật khẩu...`);
      // Update password
      await authApi("accounts:update", {
        localId: existing.localId,
        password: password,
        displayName: displayName,
      });
      return existing.localId;
    }
  } catch (e) {
    // lookup failed or user not found
  }

  // Tạo mới
  console.log(`- Đang tạo tài khoản Firebase Auth cho ${email}...`);
  const created = await authApi("accounts", {
    email: email,
    password: password,
    displayName: displayName,
    returnSecureToken: false,
  });
  return created.localId;
}

async function verifyLogin(email, password) {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: true,
    }),
  });
  const data = await res.json();
  if (data.error) {
    throw new Error(`Đăng nhập thử ${email} thất bại: ${data.error.message}`);
  }
  return data;
}

async function main() {
  console.log("=== BẮT ĐẦU TẠO CỬA HÀNG VÀ TÀI KHOẢN CHO TRẠM BLAO ===");
  console.log(`Mã cửa hàng: ${STORE_CODE}`);
  console.log(`Tên cửa hàng: ${STORE_NAME}`);
  console.log(`Mật khẩu dùng chung: ${PASSWORD}\n`);

  const now = Date.now();

  // 1. Cấu hình các tài khoản mẫu
  const accounts = [
    {
      username: "chu_blao",
      fullName: "Chủ quán Trạm Blao",
      roleId: "ROLE_OWNER",
      role: "ROLE_OWNER",
      isRootOwner: true,
      description: "Chủ cửa hàng (toàn quyền)",
    },
    {
      username: "quanly_blao",
      fullName: "Quản lý Trạm Blao",
      roleId: "ROLE_MANAGER",
      role: "ROLE_MANAGER",
      isRootOwner: false,
      description: "Quản lý (duyệt ca, báo cáo, menu, bàn)",
    },
    {
      username: "nhanvien_blao",
      fullName: "Nhân viên Trạm Blao",
      roleId: "ROLE_STAFF",
      role: "ROLE_STAFF",
      isRootOwner: false,
      description: "Nhân viên (bán hàng, gọi món, thu ngân)",
    },
    {
      username: "bep_blao",
      fullName: "Nhân viên Bếp Trạm Blao",
      roleId: "ROLE_KITCHEN",
      role: "ROLE_KITCHEN",
      isRootOwner: false,
      description: "Bếp / Bar (nhận đơn bếp, báo hết món)",
    },
  ];

  const createdUsers = {};

  for (const acc of accounts) {
    const email = `${acc.username}.${STORE_CODE.toLowerCase()}@tram.local`;
    const uid = await getOrCreateAuthUser(email, PASSWORD, acc.fullName);
    createdUsers[uid] = {
      uid,
      username: acc.username,
      fullName: acc.fullName,
      roleId: acc.roleId,
      role: acc.role,
      isRootOwner: acc.isRootOwner,
      isActive: true,
      phone: "0987654321",
      customPermissions: [],
      createdAt: now,
      mustChangePassword: false,
      storeCode: STORE_CODE,
    };
    acc.uid = uid;
    acc.email = email;

    // Ghi userIndex
    await rtdbPut(`userIndex/${uid}/${STORE_CODE}`, true);
  }

  // 2. Tạo storeInfo
  const storeInfo = {
    id: STORE_CODE,
    storeCode: STORE_CODE,
    storeName: STORE_NAME,
    address: "Bảo Lộc, Lâm Đồng",
    phone: "0987654321",
    wifiName: "Tram_Blao_Free",
    bankId: "MB",
    bankAccount: "0987654321",
    accountName: "TRAM BLAO",
    defaultVatRate: 0,
    allowStackPromotions: true,
    allowStaffViewShiftDifference: true,
    autoPrintBill: false,
    pointEarnRate: 1.0,
    pointRedeemRate: 1000,
    active: true,
    createdAt: now,
  };

  console.log("\n-> Đang lưu thông tin cửa hàng (storeInfo)...");
  await rtdbPut(`stores/${STORE_CODE}/storeInfo`, storeInfo);

  // 3. Tạo Khu vực & Bàn (Zones & Tables)
  console.log("-> Đang tạo khu vực và bàn mặc định...");
  const zones = {
    "Tầng 1": { name: "Tầng 1" },
    "Tầng 2": { name: "Tầng 2" },
    "Sân Vườn": { name: "Sân Vườn" },
  };
  const tables = {
    "Tầng 1_Bàn 01": { name: "Bàn 01", zone: "Tầng 1", inUse: false, currentOrderJson: "" },
    "Tầng 1_Bàn 02": { name: "Bàn 02", zone: "Tầng 1", inUse: false, currentOrderJson: "" },
    "Tầng 1_Bàn 03": { name: "Bàn 03", zone: "Tầng 1", inUse: false, currentOrderJson: "" },
    "Tầng 2_Bàn 04": { name: "Bàn 04", zone: "Tầng 2", inUse: false, currentOrderJson: "" },
    "Tầng 2_Bàn 05": { name: "Bàn 05", zone: "Tầng 2", inUse: false, currentOrderJson: "" },
    "Sân Vườn_Bàn SV1": { name: "Bàn SV1", zone: "Sân Vườn", inUse: false, currentOrderJson: "" },
  };
  await rtdbPut(`stores/${STORE_CODE}/zones`, zones);
  await rtdbPut(`stores/${STORE_CODE}/tables`, tables);

  // 4. Tạo Danh mục (Categories)
  console.log("-> Đang tạo danh mục món...");
  const categories = {
    "Nước": {
      name: "Nước",
      order: 1,
      allowedToppingIds: ["Thạch chanh", "Thạch dừa"],
    },
    "Bánh lăn nướng": {
      name: "Bánh lăn nướng",
      order: 2,
    },
    "Topping": {
      name: "Topping",
      order: 3,
    },
  };
  await rtdbPut(`stores/${STORE_CODE}/categories`, categories);

  // 5. Tạo Thực đơn (Products)
  console.log("-> Đang tạo thực đơn...");
  const products = {
    // Nhóm Nước
    "Trà tắc": {
      id: 101,
      name: "Trà tắc",
      code: "TRA_TAC",
      price: 20000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/trachanh.jpg",
    },
    "Trà olong chanh tươi": {
      id: 102,
      name: "Trà olong chanh tươi",
      code: "TRA_OLONG_CHANH_TUOI",
      price: 22000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/trachanh.jpg",
    },
    "Trà olong chanh đào": {
      id: 103,
      name: "Trà olong chanh đào",
      code: "TRA_OLONG_CHANH_DAO",
      price: 25000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/tradao.jpg",
    },
    "Trà olong bưởi hồng đào": {
      id: 104,
      name: "Trà olong bưởi hồng đào",
      code: "TRA_OLONG_BUOI_HONG_DAO",
      price: 32000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/tradao.jpg",
    },
    "Trà olong xoài đào": {
      id: 105,
      name: "Trà olong xoài đào",
      code: "TRA_OLONG_XOAI_DAO",
      price: 28000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/traxoai.jpg",
    },
    "Trà olong cam đào": {
      id: 106,
      name: "Trà olong cam đào",
      code: "TRA_OLONG_CAM_DAO",
      price: 29000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/tradao.jpg",
    },
    "Trà xoài chanh dây": {
      id: 107,
      name: "Trà xoài chanh dây",
      code: "TRA_XOAI_CHANH_DAY",
      price: 27000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/trachanhday.jpg",
    },
    "Trà olong quýt hoàng kim": {
      id: 108,
      name: "Trà olong quýt hoàng kim",
      code: "TRA_OLONG_QUYT_HOANG_KIM",
      price: 35000,
      unit: "Ly",
      category: "Nước",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: true,
      sizes: { "S": 0, "M": 5000, "L": 10000 },
      allowedToppings: ["Thạch chanh", "Thạch dừa"],
      imageResourceName: "assets/images/products/traquamong.jpg",
    },

    // Nhóm Bánh lăn nướng
    "Bánh lăn truyền thống": {
      id: 201,
      name: "Bánh lăn truyền thống",
      code: "BANH_LAN_TRUYEN_THONG",
      price: 22000,
      unit: "Cái",
      category: "Bánh lăn nướng",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: false,
      imageResourceName: "assets/images/products/banhlannho.jpg",
    },
    "Bánh lăn phô mai": {
      id: 202,
      name: "Bánh lăn phô mai",
      code: "BANH_LAN_PHO_MAI",
      price: 28000,
      unit: "Cái",
      category: "Bánh lăn nướng",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: false,
      imageResourceName: "assets/images/products/banhlanvua.jpg",
    },
    "Bánh lăn choco chip": {
      id: 203,
      name: "Bánh lăn choco chip",
      code: "BANH_LAN_CHOCO_CHIP",
      price: 26000,
      unit: "Cái",
      category: "Bánh lăn nướng",
      isAvailable: true,
      isTopping: false,
      hasIceSugarOptions: false,
      imageResourceName: "assets/images/products/banhlanlon.jpg",
    },

    // Toppings
    "Thạch chanh": {
      id: 301,
      name: "Thạch chanh",
      code: "TOPPING_THACH_CHANH",
      price: 5000,
      unit: "Phần",
      category: "Topping",
      isAvailable: true,
      isTopping: true,
      imageResourceName: "assets/images/products/product_0.jpg",
    },
    "Thạch dừa": {
      id: 302,
      name: "Thạch dừa",
      code: "TOPPING_THACH_DUA",
      price: 5000,
      unit: "Phần",
      category: "Topping",
      isAvailable: true,
      isTopping: true,
      imageResourceName: "assets/images/products/product_0.jpg",
    },
  };
  await rtdbPut(`stores/${STORE_CODE}/products`, products);

  // 6. Lưu danh sách Users vào quán
  console.log("-> Đang lưu danh sách nhân viên vào cửa hàng...");
  await rtdbPut(`stores/${STORE_CODE}/users`, createdUsers);

  // 7. Ghi Audit Log
  const logId = `LOG_${now}_init`;
  await rtdbPut(`stores/${STORE_CODE}/audit_logs/${logId}`, {
    action: "CREATE_STORE",
    targetType: "STORE",
    targetId: STORE_CODE,
    details: `Khởi tạo chi nhánh mới: ${STORE_NAME} (${STORE_CODE}) kèm menu và tài khoản test`,
    timestamp: now,
    username: "system",
    userFullName: "Hệ thống",
    userRole: "ADMIN",
  });

  // 8. Kiểm thử đăng nhập thực tế
  console.log("\n-> Đang kiểm thử đăng nhập các tài khoản vừa tạo...");
  for (const acc of accounts) {
    try {
      const res = await verifyLogin(acc.email, PASSWORD);
      console.log(`  ✓ Đăng nhập thành công: ${acc.username} (${acc.roleId}) - UID: ${res.localId}`);
    } catch (e) {
      console.error(`  ✗ Đăng nhập thất bại: ${acc.username} - ${e.message}`);
    }
  }

  console.log("\n=== TẤT CẢ ĐÃ HOÀN TẤT THÀNH CÔNG ===");
}

main().catch((err) => {
  console.error("Lỗi:", err.message);
  process.exit(1);
});

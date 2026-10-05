#!/usr/bin/env node

/**
 * Script di chuyển tài khoản cũ của POS Trạm sang Firebase Auth:
 * - Chuẩn hóa username và tạo email ảo theo quy ước: {username}.{storeCode}@tram.local
 * - Tạo Firebase Auth account (hoặc cập nhật nếu đã tồn tại)
 * - Đảm bảo mật khẩu tạm: giữ nguyên nếu >= 6 ký tự, sinh ngẫu nhiên 8 ký tự nếu < 6 ký tự
 * - Xuất mật khẩu sinh mới ra CSV trong migration_output/
 * - Cập nhật user profile trong Realtime Database: gắn mustChangePassword = true, xóa hoàn toàn trường password
 * - Ghi userIndex/{uid}/{storeCode} = true
 * - Trước khi thực hiện ở chế độ --apply, xuất bản sao lưu đầy đủ dạng JSON vào migration_output/
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const admin = require("firebase-admin");

// -----------------------------------------------------------------------------
// 1. Phân tích tham số dòng lệnh
// -----------------------------------------------------------------------------
const args = process.argv.slice(2);
const isApply = args.includes("--apply");
const isDryRun = !isApply;

function getArgValue(prefix) {
  const arg = args.find((a) => a.startsWith(prefix));
  return arg ? arg.split("=")[1] : null;
}

const customSaPath = getArgValue("--service-account=");
const customDbUrl = getArgValue("--database-url=");

// Thư mục lưu trữ output
const outputDir = path.resolve(__dirname, "../../migration_output");
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// -----------------------------------------------------------------------------
// 2. Tìm kiếm và nạp Service Account Key
// -----------------------------------------------------------------------------
function findServiceAccountKey() {
  if (customSaPath && fs.existsSync(customSaPath)) {
    return path.resolve(customSaPath);
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    return path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS);
  }

  const searchDirs = [
    path.resolve(__dirname),
    path.resolve(__dirname, "../.."),
    process.cwd(),
  ];

  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir);
    const saFile = files.find(
      (f) => f.startsWith("service-account") && f.endsWith(".json")
    );
    if (saFile) {
      return path.join(dir, saFile);
    }
  }

  return null;
}

const saKeyPath = findServiceAccountKey();
if (!saKeyPath) {
  console.error("❌ KHÔNG TÌM THẤY SERVICE ACCOUNT KEY!");
  console.error("Vui lòng tải khóa service account từ Firebase Console (Cài đặt dự án -> Tài khoản dịch vụ -> Tạo khóa riêng tư mới),");
  console.error("lưu vào thư mục gốc dự án với tên 'service-account.json',");
  console.error("hoặc truyền qua cờ: --service-account=path/to/key.json");
  console.error("hoặc đặt biến môi trường: GOOGLE_APPLICATION_CREDENTIALS");
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(saKeyPath, "utf-8"));
const projectId = serviceAccount.project_id;
const databaseURL =
  customDbUrl ||
  `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`;

console.log("================================================================");
console.log(`🚀 POS TRẠM - SCRIPT MIGRATE TÀI KHOẢN NGƯỜI DÙNG CŨ`);
console.log(`Dự án Firebase:  ${projectId}`);
console.log(`Database URL:    ${databaseURL}`);
console.log(`Service Account: ${saKeyPath}`);
console.log(`Chế độ chạy:     ${isApply ? "⚠️  --apply (GHI DỮ LIỆU THẬT)" : "🛡️  DRY-RUN (CHỈ KIỂM TRA, KHÔNG GHI)"}`);
console.log("================================================================");

// -----------------------------------------------------------------------------
// 3. Khởi tạo Firebase Admin SDK
// -----------------------------------------------------------------------------
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: databaseURL,
});

const db = admin.database();
const auth = admin.auth();

// -----------------------------------------------------------------------------
// 4. Các hàm trợ giúp chuẩn hóa & sinh mật khẩu
// -----------------------------------------------------------------------------
function normalizeUsername(raw) {
  if (!raw) return "";
  return String(raw)
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/[^a-z0-9_.-]/g, "");
}

function buildSyntheticEmail(username, storeCode) {
  const cleanUser = normalizeUsername(username);
  const cleanStore = String(storeCode).trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  return `${cleanUser}.${cleanStore}@tram.local`;
}

function generateRandomPassword(length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$";
  let pass = "";
  const randomBytes = crypto.randomBytes(length);
  for (let i = 0; i < length; i++) {
    pass += chars[randomBytes[i] % chars.length];
  }
  return pass;
}

// -----------------------------------------------------------------------------
// 5. Tiến trình quét dữ liệu & di chuyển
// -----------------------------------------------------------------------------
async function run() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

  console.log("\n🔍 1. Đang đọc dữ liệu người dùng từ Realtime Database...");

  // Đọc danh sách stores
  const storesSnap = await db.ref("stores").once("value");
  const storesData = storesSnap.val() || {};

  // Đọc danh sách legacy users ở nút gốc
  const rootUsersSnap = await db.ref("users").once("value");
  const rootUsersData = rootUsersSnap.val() || {};

  const candidates = [];

  // Quét từng store
  for (const [storeCode, storeVal] of Object.entries(storesData)) {
    if (!storeVal || typeof storeVal !== "object" || !storeVal.users) continue;
    const usersObj = storeVal.users;
    for (const [userKey, userVal] of Object.entries(usersObj)) {
      if (!userVal || typeof userVal !== "object") continue;
      candidates.push({
        sourceType: "store",
        storeCode: storeCode.toUpperCase(),
        userKey: userKey,
        data: userVal,
        path: `stores/${storeCode}/users/${userKey}`,
      });
    }
  }

  // Quét root users (nếu có tài khoản POS)
  for (const [userKey, userVal] of Object.entries(rootUsersData)) {
    if (!userVal || typeof userVal !== "object") continue;
    // Bỏ qua nếu không phải cấu trúc người dùng của POS
    const inferredStore = userVal.storeCode || "TRAM01";
    candidates.push({
      sourceType: "root",
      storeCode: inferredStore.toUpperCase(),
      userKey: userKey,
      data: userVal,
      path: `users/${userKey}`,
    });
  }

  console.log(`📌 Tìm thấy tổng cộng ${candidates.length} bản ghi người dùng trên hệ thống.`);

  // Lập kế hoạch di chuyển
  const plan = [];
  let skippedCount = 0;

  for (const item of candidates) {
    const u = item.data;
    const hasPlainPassword = !!u.password;
    const existingAuthUid = u.uid && u.uid.length >= 20 ? u.uid : null;

    const username = u.username || u.name || item.userKey;
    const cleanUser = normalizeUsername(username);

    if (!cleanUser) {
      console.warn(`⚠️  Bỏ qua bản ghi tại ${item.path}: Không xác định được username.`);
      skippedCount++;
      continue;
    }

    const syntheticEmail = buildSyntheticEmail(cleanUser, item.storeCode);
    const rawPass = u.password ? String(u.password) : "";

    let finalPass = "";
    let passAction = "";

    if (rawPass && rawPass.length >= 6) {
      finalPass = rawPass;
      passAction = "KEPT_OLD";
    } else {
      finalPass = generateRandomPassword(8);
      passAction = "GENERATED_NEW";
    }

    plan.push({
      item,
      cleanUser,
      syntheticEmail,
      finalPass,
      passAction,
      hasPlainPassword,
      existingAuthUid,
    });
  }

  console.log(`\n📋 Kế hoạch di chuyển: ${plan.length} tài khoản cần xử lý (Bỏ qua: ${skippedCount}).\n`);

  // In danh sách tóm tắt
  for (const p of plan) {
    const flag = p.hasPlainPassword ? "⚠️ CÓ PASSWORD THÔ" : "✅ KHÔNG CÓ PASSWORD THÔ";
    console.log(
      ` - [${p.item.storeCode}] @${p.cleanUser.padEnd(15)} -> Email: ${p.syntheticEmail.padEnd(35)} ` +
      `| Mật khẩu: ${p.passAction === "KEPT_OLD" ? "(Giữ cũ >= 6 ký tự)" : "(Sinh mới 8 ký tự)"} | ${flag}`
    );
  }

  // Nếu là DRY-RUN, dừng lại ở đây
  if (isDryRun) {
    console.log("\n================================================================");
    console.log("🛡️  KẾT QUẢ CHẠY THỬ (DRY-RUN)");
    console.log(` - Tổng tài khoản quét được:    ${candidates.length}`);
    console.log(` - Tài khoản sẽ di chuyển:      ${plan.length}`);
    console.log(` - Tài khoản sinh mật khẩu mới:  ${plan.filter((x) => x.passAction === "GENERATED_NEW").length}`);
    console.log(` - Bỏ qua:                      ${skippedCount}`);
    console.log("\nChưa có thay đổi nào được ghi vào Firebase.");
    console.log("👉 Để áp dụng thật, chạy lại lệnh với cờ: --apply");
    console.log("   npm run apply -- --service-account=path/to/key.json");
    console.log("================================================================\n");
    process.exit(0);
  }

  // ---------------------------------------------------------------------------
  // 6. THỰC HIỆN GHI DỮ LIỆU (--apply)
  // ---------------------------------------------------------------------------
  console.log("\n⚠️  ĐANG Ở CHẾ ĐỘ --apply. BẮT ĐẦU QUÁ TRÌNH DI CHUYỂN...\n");

  // BƯỚC 6.1: SAO LƯU DỮ LIỆU TRƯỚC KHI THỰC HIỆN
  const backupFilePath = path.join(outputDir, `backup_pre_migration_${timestamp}.json`);
  console.log(`💾 1. Đang tạo bản sao lưu dữ liệu tại: ${backupFilePath}`);

  const backupData = {
    timestamp: new Date().toISOString(),
    stores: storesData,
    rootUsers: rootUsersData,
  };
  fs.writeFileSync(backupFilePath, JSON.stringify(backupData, null, 2), "utf-8");
  console.log("✅ Bản sao lưu JSON đã được lưu an toàn.\n");

  // BƯỚC 6.2: DI CHUYỂN TỪNG TÀI KHOẢN
  const csvRecords = [];
  let successCount = 0;
  let errorCount = 0;

  for (let i = 0; i < plan.length; i++) {
    const p = plan[i];
    const u = p.item.data;
    const storeCode = p.item.storeCode;

    process.stdout.write(`[${i + 1}/${plan.length}] Di chuyển @${p.cleanUser} (${storeCode})... `);

    try {
      let authUser;
      try {
        authUser = await auth.getUserByEmail(p.syntheticEmail);
        // Cập nhật mật khẩu nếu cần
        await auth.updateUser(authUser.uid, {
          password: p.finalPass,
          displayName: u.fullName || p.cleanUser,
          disabled: u.isActive === false,
        });
      } catch (err) {
        if (err.code === "auth/user-not-found") {
          authUser = await auth.createUser({
            email: p.syntheticEmail,
            password: p.finalPass,
            displayName: u.fullName || p.cleanUser,
            disabled: u.isActive === false,
          });
        } else {
          throw err;
        }
      }

      const newUid = authUser.uid;

      // 1. Cập nhật hồ sơ trong RTDB tại stores/{storeCode}/users/{newUid}
      const updatedProfile = {
        ...u,
        uid: newUid,
        username: p.cleanUser,
        fullName: u.fullName || p.cleanUser,
        roleId: u.roleId || "cashier",
        isActive: u.isActive !== false,
        mustChangePassword: true,
        migratedAt: Date.now(),
      };
      // Xóa bỏ trường password thô khỏi hồ sơ
      delete updatedProfile.password;

      // Ghi tại đường dẫn chuẩn: stores/{storeCode}/users/{newUid}
      await db.ref(`stores/${storeCode}/users/${newUid}`).set(updatedProfile);

      // Nếu userKey cũ khác với newUid, xóa node cũ để tránh dư thừa
      if (p.item.userKey !== newUid) {
        await db.ref(p.item.path).remove();
      }

      // 2. Ghi userIndex/{newUid}/{storeCode} = true
      await db.ref(`userIndex/${newUid}/${storeCode}`).set(true);

      // 3. Nếu là root node /users/{userKey}, xóa trường password ở root node nếu còn
      if (p.item.sourceType === "root") {
        await db.ref(`users/${p.item.userKey}/password`).remove().catch(() => {});
      }

      // 4. Lưu lại thông tin mật khẩu tạm để xuất CSV
      csvRecords.push({
        storeCode,
        username: p.cleanUser,
        fullName: u.fullName || p.cleanUser,
        roleId: u.roleId || "cashier",
        email: p.syntheticEmail,
        tempPassword: p.finalPass,
        passwordAction: p.passAction,
      });

      successCount++;
      console.log(`✅ Thành công (UID: ${newUid})`);
    } catch (err) {
      errorCount++;
      console.log(`❌ Thất bại: ${err.message}`);
    }
  }

  // BƯỚC 6.3: XUẤT FILE CSV MẬT KHẨU TẠM
  const csvFilePath = path.join(outputDir, `migrated_users_${timestamp}.csv`);
  console.log(`\n📄 3. Đang xuất danh sách mật khẩu tạm tại: ${csvFilePath}`);

  const csvHeader = "Chi nhánh,Tên đăng nhập,Họ và tên,Vai trò,Email Firebase Auth,Mật khẩu tạm,Ghi chú\n";
  const csvRows = csvRecords
    .map(
      (r) =>
        `"${r.storeCode}","${r.username}","${r.fullName}","${r.roleId}","${r.email}","${r.tempPassword}","${r.passwordAction}"`
    )
    .join("\n");

  fs.writeFileSync(csvFilePath, "\uFEFF" + csvHeader + csvRows, "utf-8"); // UTF-8 BOM cho Excel
  console.log("✅ File CSV mật khẩu đã được tạo thành công.");

  // TỔNG KẾT
  console.log("\n================================================================");
  console.log("🎉 HOÀN TẤT DI CHUYỂN TÀI KHOẢN NGƯỜI DÙNG");
  console.log(` - Tổng số tài khoản cần xử lý: ${plan.length}`);
  console.log(` - Di chuyển thành công:        ${successCount}`);
  console.log(` - Bỏ qua:                      ${skippedCount}`);
  console.log(` - Thất bại:                    ${errorCount}`);
  console.log(` - Bản sao lưu JSON:            ${backupFilePath}`);
  console.log(` - File CSV mật khẩu tạm:       ${csvFilePath}`);
  console.log("\n⚠️  LƯU Ý QUAN TRỌNG:");
  console.log("1. Gửi file CSV mật khẩu tạm cho nhân viên có mật khẩu được sinh mới.");
  console.log("2. Sau khi kiểm tra hệ thống hoạt động ổn định, vui lòng XÓA file");
  console.log("   service-account.json và file CSV để bảo mật.");
  console.log("================================================================\n");

  process.exit(0);
}

run().catch((err) => {
  console.error("💥 Lỗi ngoài dự tính khi chạy script migrate:", err);
  process.exit(1);
});

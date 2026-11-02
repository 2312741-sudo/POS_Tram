package vn.tram.fnb.tram_payment_bot

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.Executors
import java.util.regex.Pattern

class BankNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "BankNotifListener"
        const val FIREBASE_BASE_URL = "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app"
        const val ACTION_NEW_PAYMENT = "vn.tram.fnb.tram_payment_bot.NEW_PAYMENT"

        // Danh sách các package app ngân hàng, ví điện tử và SMS phổ biến tại VN
        val KNOWN_BANK_PACKAGES = mapOf(
            "com.mbmobile" to "MB Bank",
            "com.VCB" to "Vietcombank",
            "com.vcb.digibank" to "Vietcombank",
            "vn.com.techcombank.bb.app" to "Techcombank",
            "com.techcombank" to "Techcombank",
            "mobile.acb.com.vn" to "ACB",
            "com.vpb.neo" to "VPBank",
            "com.vnpay.bidv" to "BIDV",
            "com.vietinbank.ipay" to "VietinBank",
            "com.tpb.mb.gprs" to "TPBank",
            "com.vnpay.sacombank" to "Sacombank",
            "com.sacombank.mplus" to "Sacombank Pay",
            "com.sacombank.pay" to "Sacombank Pay",
            "com.vnpay.hdbank" to "HDBank",
            "com.mplus.omni" to "OCB",
            "com.ocb.omni" to "OCB OMNI",
            "com.vib.myvib2" to "MyVIB 2.0",
            "com.vib.myvib" to "MyVIB",
            "com.shb.mobile" to "SHB",
            "vn.com.seabank.mb1" to "SeABank",
            "xyz.be.cake" to "Cake by VPBank",
            "com.vnpay.Agribank" to "Agribank",
            "com.agribank.emobilebanking" to "Agribank",
            "vn.com.msb.smartBanking" to "MSB",
            "com.lpbank.mobilebanking" to "LPBank",
            "vn.com.lpb" to "LPBank",
            "com.timo.bank" to "Timo Digital Bank",
            "com.kasikornbank.kplus.vn" to "KBank",
            "com.bplus.vtpay" to "Viettel Money",
            "com.mservice.momopay" to "MoMo",
            "vn.com.vng.zalopay" to "ZaloPay",
            // SMS Banking (Google, Samsung, Xiaomi, Oppo/Realme, Vivo, Huawei, AOSP)
            "com.google.android.apps.messaging" to "Tin nhắn SMS",
            "com.samsung.android.messaging" to "Tin nhắn SMS",
            "com.android.mms" to "Tin nhắn SMS",
            "com.miui.mms" to "Tin nhắn SMS (Xiaomi)",
            "com.coloros.mms" to "Tin nhắn SMS (Oppo)",
            "com.oppo.mms" to "Tin nhắn SMS (Oppo)",
            "com.heytap.mms" to "Tin nhắn SMS (Oppo/Realme)",
            "com.vivo.mms" to "Tin nhắn SMS (Vivo)",
            "com.huawei.message" to "Tin nhắn SMS (Huawei)"
        )

        // Cache chống trùng lặp thông báo (lưu 100 sự kiện gần nhất trong 15s)
        private val recentSignatures = Collections.synchronizedMap(
            object : LinkedHashMap<String, Long>(100, 0.75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean {
                    return size > 100
                }
            }
        )
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "BankNotificationListener connected successfully")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "BankNotificationListener disconnected, requesting rebind")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, BankNotificationListener::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Lỗi khi gọi requestRebind: ${e.message}")
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        try {
            val notification = sbn.notification ?: return

            // Bỏ qua các thông báo dịch vụ chạy ngầm cố định (ongoing foreground notification)
            if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) {
                return
            }

            val packageName = sbn.packageName ?: return
            val extras = notification.extras ?: return

            // Đọc toàn bộ các trường text có thể có trong Notification của Android
            val title = extras.getString(Notification.EXTRA_TITLE) 
                ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras.getString(Notification.EXTRA_TEXT) 
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
            val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
            val summaryText = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString() ?: ""
            val infoText = extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString() ?: ""
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.joinToString(" ") { it.toString() } ?: ""
            val ticker = notification.tickerText?.toString() ?: ""

            val fullContent = listOf(title, text, bigText, subText, summaryText, infoText, lines, ticker)
                .filter { it.isNotBlank() }
                .joinToString(" ")
                .replace(Regex("\\s+"), " ")
                .trim()

            if (fullContent.isEmpty()) return

            val isBankPackage = KNOWN_BANK_PACKAGES.containsKey(packageName)
            val lowerContent = fullContent.lowercase(Locale.getDefault())

            // Kiểm tra các từ khóa nhận tiền
            val hasMoneyKeywords = fullContent.contains("+") || 
                lowerContent.contains("nhận") || 
                lowerContent.contains("nhan") ||
                lowerContent.contains("cộng") ||
                lowerContent.contains("cong") ||
                lowerContent.contains("tang") ||
                lowerContent.contains("tăng") ||
                lowerContent.contains("gd:") ||
                lowerContent.contains("biến động") ||
                lowerContent.contains("bien dong") ||
                lowerContent.contains("so du") ||
                lowerContent.contains("số dư") ||
                lowerContent.contains("giao dịch") ||
                lowerContent.contains("giao dich") ||
                lowerContent.contains("credit") ||
                lowerContent.contains("cr:") ||
                lowerContent.contains("vnd") ||
                lowerContent.contains("vnđ") ||
                lowerContent.contains("đ")

            if (!isBankPackage && !hasMoneyKeywords) {
                return
            }

            // Bỏ qua nếu đây là giao dịch tiền ra / trừ tiền / rút tiền (Debit / Outgoing payment)
            if (isDebitTransaction(fullContent)) {
                Log.d(TAG, "Bỏ qua thông báo tiền ra / trừ tiền từ $packageName: $fullContent")
                return
            }

            val bankName = KNOWN_BANK_PACKAGES[packageName] ?: "Ngân hàng"

            // Trích xuất số tiền nhận vào
            val extractedAmount = parseAmount(fullContent)
            if (extractedAmount <= 0) {
                Log.d(TAG, "Không tìm thấy số tiền cộng hợp lệ trong thông báo: $fullContent")
                return
            }

            val extractedContent = parseContent(fullContent)

            // Kiểm tra chống trùng lặp (nhiều lần thông báo cập nhật cho cùng 1 giao dịch trong 15 giây)
            val now = System.currentTimeMillis()
            val dedupeKey = "$packageName:$extractedAmount:$extractedContent"
            val lastSeen = recentSignatures[dedupeKey]
            if (lastSeen != null && (now - lastSeen) < 15000) {
                Log.d(TAG, "Bỏ qua thông báo trùng lặp (vừa nhận cách đây ${(now - lastSeen)}ms): $dedupeKey")
                return
            }
            recentSignatures[dedupeKey] = now

            Log.d(TAG, "Phát hiện tiền về từ $bankName ($packageName): $extractedAmount VND (ND: $extractedContent)")

            // Đọc cấu hình chi nhánh từ SharedPreferences
            val prefs = getSharedPreferences("tram_bot_prefs", Context.MODE_PRIVATE)
            val autoDetect = prefs.getBoolean("auto_detect_store", true)
            val defaultStore = prefs.getString("default_store_code", "TRAM01") ?: "TRAM01"

            // 1. Tự động nhận diện chi nhánh từ nội dung chuyển khoản nếu bật autoDetect (TRAM01, TRAM02, TRAM03, TRAM04, TRAM05...)
            val tramCodeMatch = if (autoDetect) Regex("""(?i)\b(tram\d{1,4})\b""").find(fullContent) else null
            val detectedStoreCode = tramCodeMatch?.value?.uppercase()

            // 2. Tra cứu cấu hình gán theo Ngân hàng -> Chi nhánh
            val bankMappedStore = prefs.getString("bank_map_$packageName", null)
                ?: if (packageName == "com.vcb.digibank") prefs.getString("bank_map_com.VCB", null)
                   else if (packageName == "com.techcombank") prefs.getString("bank_map_vn.com.techcombank.bb.app", null)
                   else if (packageName == "com.agribank.emobilebanking") prefs.getString("bank_map_com.vnpay.Agribank", null)
                   else if (packageName == "com.sacombank.mplus" || packageName == "com.sacombank.pay") prefs.getString("bank_map_com.vnpay.sacombank", null)
                   else if (packageName == "com.vib.myvib") prefs.getString("bank_map_com.vib.myvib2", null)
                   else if (packageName == "com.ocb.omni") prefs.getString("bank_map_com.mplus.omni", null)
                   else if (packageName == "vn.com.lpb") prefs.getString("bank_map_com.lpbank.mobilebanking", null)
                   else if (packageName.contains("messaging") || packageName.contains("mms") || packageName.contains("message")) {
                       prefs.getString("bank_map_com.google.android.apps.messaging", null)
                   }
                   else null

            val storeCode = when {
                detectedStoreCode != null -> detectedStoreCode
                !bankMappedStore.isNullOrBlank() -> bankMappedStore
                else -> defaultStore
            }

            val timeStr = SimpleDateFormat("HH:mm:ss dd/MM/yyyy", Locale.getDefault()).format(Date(now))
            val eventId = "PAY_${now}_${(1000..9999).random()}"

            // Bắn sự kiện lên Firebase Realtime Database qua background worker có retry
            executor.execute {
                syncToFirebase(storeCode, eventId, extractedAmount, extractedContent, bankName, fullContent, now, timeStr)
            }

            // Bắn broadcast cục bộ về màn hình Flutter app
            val intent = Intent(ACTION_NEW_PAYMENT).apply {
                putExtra("eventId", eventId)
                putExtra("storeCode", storeCode)
                putExtra("amount", extractedAmount)
                putExtra("content", extractedContent)
                putExtra("bankName", bankName)
                putExtra("timeStr", timeStr)
                putExtra("rawText", fullContent)
            }
            sendBroadcast(intent)
        } catch (e: Throwable) {
            Log.e(TAG, "Lỗi xử lý thông báo: ${e.message}", e)
        }
    }

    /**
     * Nhận diện giao dịch tiền ra / trừ tiền / rút tiền để tuyệt đối không đẩy nhầm lên POS
     */
    private fun isDebitTransaction(text: String): Boolean {
        val hasPlus = Pattern.compile("""\+\s*[0-9]""").matcher(text).find()
        val hasMinus = Pattern.compile("""-\s*[0-9]""").matcher(text).find()

        // Nếu có dấu trừ trước số tiền và không có dấu cộng -> chắc chắn là tiền ra
        if (hasMinus && !hasPlus) {
            return true
        }

        val lower = text.lowercase(Locale.getDefault())

        val debitKeywords = listOf(
            "rút tiền", "rut tien",
            "chuyển đi", "chuyen di",
            "chuyển cho", "chuyen cho",
            "chuyển đến", "chuyen den",
            "thanh toán cho", "thanh toan cho",
            "thanh toán hoá đơn", "thanh toan hoa don",
            "phí duy trì", "phi duy tri",
            "phí thường niên", "phi thuong nien",
            "biến động giảm", "bien dong giam",
            "số dư giảm", "so du giam",
            "debit", "dr:", "dr "
        )

        val creditKeywords = listOf(
            "nhận", "nhan",
            "cộng", "cong",
            "tăng", "tang",
            "credit", "cr:", "cr "
        )

        val hasDebitWord = debitKeywords.any { lower.contains(it) }
        val hasCreditWord = creditKeywords.any { lower.contains(it) }

        if (hasDebitWord && !hasCreditWord && !hasPlus) {
            return true
        }

        return false
    }

    private fun parseAmount(text: String): Long {
        // 1. Ưu tiên số có dấu cộng: +15.000, + 15,000, +15000, +15.000VND
        val plusPattern = Pattern.compile("""\+\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})""")
        val mPlus = plusPattern.matcher(text)
        if (mPlus.find()) {
            val num = mPlus.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num > 0) return num
        }

        // 2. Dạng có từ khóa nhận tiền: nhận 50.000, nhận được 50.000đ, cộng 50.000, GD: 50.000, Số tiền: 50.000
        val prefixPattern = Pattern.compile(
            """(?i)(?:nhận|nhan|cộng|cong|tăng|tang|credit|cr:|gd:|giao dịch:|giao dich:|số tiền:|so tien:)\s*(?:được|duoc|thành công|thanh cong)?\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})"""
        )
        val mPrefix = prefixPattern.matcher(text)
        if (mPrefix.find()) {
            val num = mPrefix.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num > 0) return num
        }

        // 3. Dạng có hậu tố đơn vị tiền tệ: 50.000 VND, 50,000VND, 50.000đ, 50000d
        // Lưu ý: Dùng (?![a-zA-Z0-9]) thay cho \b vì ký tự Unicode 'đ' không khớp \b trong regex chuẩn
        val suffixPattern = Pattern.compile(
            """([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:VND|vnd|VNĐ|vnđ|d|đ)(?![a-zA-Z0-9])"""
        )
        val mSuffix = suffixPattern.matcher(text)
        if (mSuffix.find()) {
            // Đảm bảo số này không bị đi liền sau dấu trừ
            val matchStart = mSuffix.start()
            val charBefore = if (matchStart > 0) text[matchStart - 1] else ' '
            if (charBefore != '-') {
                val num = mSuffix.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
                if (num > 0) return num
            }
        }

        // 4. Fallback bắt chuỗi có dấu phân cách nghìn
        val fallbackPattern = Pattern.compile("""\b([0-9]{1,3}(?:[.,][0-9]{3})+)\b""")
        val mFallback = fallbackPattern.matcher(text)
        if (mFallback.find()) {
            val matchStart = mFallback.start()
            val charBefore = if (matchStart > 0) text[matchStart - 1] else ' '
            if (charBefore != '-') {
                val num = mFallback.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
                if (num >= 1000) return num
            }
        }

        return 0L
    }

    private fun parseContent(text: String): String {
        // Bước 1: Ưu tiên tìm mã đơn / mã bàn của Trạm (VD: TRAM01 BAN 1, TRAM01 BAN A1, TRAM02 MV 2, TRAM04_BAN_D5...)
        val tramPattern = Pattern.compile("""(?i)\b(tram\d{1,4}[\s_-]*(?:ban|bàn|mv|mang\s*ve)?[\s_-]*[a-z0-9]+)\b""")
        val mTram = tramPattern.matcher(text)
        val extractedTramCode = if (mTram.find()) mTram.group(1)?.trim() else null

        // Bước 2: Tìm nội dung chuyển khoản theo các từ khóa phổ biến trong app ngân hàng
        val keywords = listOf(
            "nội dung:", "noi dung:", "nội dung", "noi dung",
            "lời nhắn:", "loi nhan:", "lời nhắn", "loi nhan",
            "diễn giải:", "dien giai:", "diễn giải", "dien giai", "dg:", "dg ",
            "mô tả:", "mo ta:", "mô tả", "mo ta",
            "lý do:", "ly do:", "lý do", "ly do",
            "nd:", "nd :", "nd ",
            "ref:", "ref.", "ref ",
            "memo:", "memo ", "msg:", "msg ",
            "ct:"
        )

        var contentFromKeyword: String? = null
        for (kw in keywords) {
            val idx = text.indexOf(kw, ignoreCase = true)
            if (idx != -1) {
                var candidate = text.substring(idx + kw.length).trim()
                // Cắt bỏ phần thông tin số dư / thời gian / mã GD phía sau nếu có
                val stopKeywords = listOf(
                    "|", ". SD", "; SD", ", SD", "- SD", " SD:", ". Số dư", ". Số dư", ". So du",
                    "So du sau GD", "Số dư sau GD", "Số dư:", "Số dư:", "So du:",
                    "tai MB", "tại MB", "Ma GD:", "Mã GD:", "Ma GD "
                )
                for (skw in stopKeywords) {
                    val sIdx = candidate.indexOf(skw, ignoreCase = true)
                    if (sIdx != -1) {
                        candidate = candidate.substring(0, sIdx).trim()
                    }
                }
                if (candidate.isNotBlank()) {
                    contentFromKeyword = candidate
                    break
                }
            }
        }

        // Bước 3: Quyết định nội dung trả về
        if (contentFromKeyword != null) {
            return contentFromKeyword.take(200)
        }

        if (extractedTramCode != null) {
            return extractedTramCode
        }

        return text.take(200)
    }

    private fun syncToFirebase(
        storeCode: String,
        eventId: String,
        amount: Long,
        content: String,
        bankName: String,
        rawText: String,
        timestamp: Long,
        timeStr: String
    ) {
        val urlString = "$FIREBASE_BASE_URL/stores/$storeCode/payment_events/$eventId.json"
        val json = JSONObject().apply {
            put("eventId", eventId)
            put("storeCode", storeCode)
            put("amount", amount)
            put("content", content)
            put("bankName", bankName)
            put("rawText", rawText)
            put("timestamp", timestamp)
            put("timeStr", timeStr)
            put("status", "UNPROCESSED") // UNPROCESSED -> PROCESSED (sau khi POS khớp đơn)
        }
        val jsonPayload = json.toString()

        var success = false
        var attempts = 0
        val maxAttempts = 3

        while (!success && attempts < maxAttempts) {
            attempts++
            try {
                val url = URL(urlString)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "PUT"
                conn.setRequestProperty("Content-Type", "application/json; utf-8")
                conn.doOutput = true
                conn.connectTimeout = 6000
                conn.readTimeout = 6000

                OutputStreamWriter(conn.outputStream).use { writer ->
                    writer.write(jsonPayload)
                    writer.flush()
                }

                val responseCode = conn.responseCode
                if (responseCode in 200..299) {
                    success = true
                    Log.d(TAG, "Đã đồng bộ giao dịch lên Firebase thành công [$storeCode] (lần thử $attempts): $amount VND (ND: $content)")
                } else {
                    Log.e(TAG, "Lỗi đồng bộ Firebase [$storeCode], HTTP $responseCode (lần thử $attempts)")
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Lỗi kết nối Firebase (lần thử $attempts/$maxAttempts): ${e.message}")
            }

            if (!success && attempts < maxAttempts) {
                try {
                    Thread.sleep(1000L * attempts)
                } catch (_: InterruptedException) {}
            }
        }
    }
}

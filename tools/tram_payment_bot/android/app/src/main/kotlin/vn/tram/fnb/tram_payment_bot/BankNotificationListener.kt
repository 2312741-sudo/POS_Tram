package vn.tram.fnb.tram_payment_bot

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
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
            "com.vnpay.hdbank" to "HDBank",
            "com.mplus.omni" to "OCB",
            "com.vib.myvib2" to "VIB",
            "com.shb.mobile" to "SHB",
            "vn.com.seabank.mb1" to "SeABank",
            "xyz.be.cake" to "Cake by VPBank",
            "com.vnpay.Agribank" to "Agribank",
            "com.agribank.emobilebanking" to "Agribank",
            "vn.com.msb.smartBanking" to "MSB",
            "com.lpbank.mobilebanking" to "LPBank",
            "vn.com.lpb" to "LPBank",
            "com.bplus.vtpay" to "Viettel Money",
            "com.mservice.momopay" to "MoMo",
            "vn.com.vng.zalopay" to "ZaloPay",
            // SMS Banking (Google Messages, Samsung Messages, AOSP SMS)
            "com.google.android.apps.messaging" to "Tin nhắn SMS",
            "com.samsung.android.messaging" to "Tin nhắn SMS",
            "com.android.mms" to "Tin nhắn SMS"
        )
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        val notification = sbn.notification ?: return
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
        val hasMoneyKeywords = fullContent.contains("+") || 
            lowerContent.contains("nhận") || 
            lowerContent.contains("cộng") ||
            lowerContent.contains("tang") ||
            lowerContent.contains("tăng") ||
            lowerContent.contains("gd:") ||
            lowerContent.contains("biến động") ||
            lowerContent.contains("so du") ||
            lowerContent.contains("số dư") ||
            lowerContent.contains("thay đổi") ||
            lowerContent.contains("giao dịch") ||
            lowerContent.contains("credit") ||
            lowerContent.contains("cr:") ||
            lowerContent.contains("vnd") ||
            lowerContent.contains("vnđ") ||
            lowerContent.contains("đ")

        if (!isBankPackage && !hasMoneyKeywords) {
            return
        }

        val bankName = KNOWN_BANK_PACKAGES[packageName] ?: "Ngân hàng"
        Log.d(TAG, "Phát hiện thông báo từ $bankName ($packageName): $fullContent")

        // Trích xuất số tiền và nội dung
        val extractedAmount = parseAmount(fullContent)
        if (extractedAmount <= 0) {
            Log.d(TAG, "Không tìm thấy số tiền hợp lệ trong thông báo: $fullContent")
            return
        }

        val extractedContent = parseContent(fullContent)

        // Đọc cấu hình chi nhánh từ SharedPreferences
        val prefs = getSharedPreferences("tram_bot_prefs", Context.MODE_PRIVATE)
        val defaultStore = prefs.getString("default_store_code", "TRAM01") ?: "TRAM01"

        // Tự động nhận diện chi nhánh nếu trong nội dung hoặc toàn bộ thông báo có mã chi nhánh
        val storeCode = when {
            extractedContent.contains("TRAM01", ignoreCase = true) || fullContent.contains("TRAM01", ignoreCase = true) -> "TRAM01"
            extractedContent.contains("TRAM02", ignoreCase = true) || fullContent.contains("TRAM02", ignoreCase = true) -> "TRAM02"
            extractedContent.contains("TRAM03", ignoreCase = true) || fullContent.contains("TRAM03", ignoreCase = true) -> "TRAM03"
            else -> defaultStore
        }

        val now = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("HH:mm:ss dd/MM/yyyy", Locale.getDefault()).format(Date(now))
        val eventId = "PAY_${now}_${(1000..9999).random()}"

        // Bắn sự kiện lên Firebase Realtime Database
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
    }

    private fun parseAmount(text: String): Long {
        // 1. Dạng có dấu cộng: +15.000, + 15,000, +15000, +15.000VND
        val plusPattern = Pattern.compile("""\+\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})""")
        val mPlus = plusPattern.matcher(text)
        if (mPlus.find()) {
            val num = mPlus.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num > 0) return num
        }

        // 2. Dạng có tiền tố: nhận 50.000, cộng 50.000, GD: 50.000, Số tiền: 50.000
        val prefixPattern = Pattern.compile("""(?i)(?:nhận|cộng|tăng|gd:|giao dịch:|số tiền:|so tien:)\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})""")
        val mPrefix = prefixPattern.matcher(text)
        if (mPrefix.find()) {
            val num = mPrefix.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num > 0) return num
        }

        // 3. Dạng có hậu tố đơn vị tiền tệ: 50.000 VND, 50,000VND, 50.000đ, 50000d
        val suffixPattern = Pattern.compile("""([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:VND|vnd|VNĐ|vnđ|d|đ)\b""")
        val mSuffix = suffixPattern.matcher(text)
        if (mSuffix.find()) {
            val num = mSuffix.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num > 0) return num
        }

        // 4. Fallback bắt chuỗi có dấu phân cách nghìn
        val fallbackPattern = Pattern.compile("""\b([0-9]{1,3}(?:[.,][0-9]{3})+)\b""")
        val mFallback = fallbackPattern.matcher(text)
        if (mFallback.find()) {
            val num = mFallback.group(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: 0L
            if (num >= 1000) return num
        }

        return 0L
    }

    private fun parseContent(text: String): String {
        // Bước 1: Ưu tiên tìm mã đơn / mã bàn của Trạm (VD: tram01a1, TRAM01_A1, TRAM01 A1, TRAM01_BAN_A1...)
        val tramPattern = Pattern.compile("""(?i)\b(tram\d{0,2}[\s_-]*(?:ban|bàn)?[\s_-]*[a-z0-9]+)\b""")
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
                // Cắt bỏ phần thông tin số dư phía sau nếu có (VD: "|SD: 500,000VND", ". So du:", ". Số dư:")
                val stopKeywords = listOf("|", ". SD", ". Số dư", ". So du", "So du sau GD", "Số dư sau GD")
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
        try {
            val urlString = "$FIREBASE_BASE_URL/stores/$storeCode/payment_events/$eventId.json"
            val url = URL(urlString)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "PUT"
            conn.setRequestProperty("Content-Type", "application/json; utf-8")
            conn.doOutput = true
            conn.connectTimeout = 5000
            conn.readTimeout = 5000

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

            OutputStreamWriter(conn.outputStream).use { writer ->
                writer.write(json.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                Log.d(TAG, "Đã đồng bộ giao dịch lên Firebase thành công [$storeCode]: $amount VND (ND: $content)")
            } else {
                Log.e(TAG, "Lỗi đồng bộ Firebase [$storeCode], mã lỗi: $responseCode")
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Lỗi kết nối Firebase: ${e.message}", e)
        }
    }
}

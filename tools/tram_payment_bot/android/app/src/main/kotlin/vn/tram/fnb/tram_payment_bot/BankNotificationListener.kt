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

        // Danh sách các package app ngân hàng & ví điện tử phổ biến tại VN
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
            "com.bplus.vtpay" to "Viettel Money",
            "com.mservice.momopay" to "MoMo",
            "vn.com.vng.zalopay" to "ZaloPay"
        )
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getString(Notification.EXTRA_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getString(Notification.EXTRA_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val fullContent = "$title $text $bigText".trim()

        if (fullContent.isEmpty()) return

        val isBankPackage = KNOWN_BANK_PACKAGES.containsKey(packageName)
        val hasMoneyKeywords = fullContent.contains("+") || 
            fullContent.lowercase(Locale.getDefault()).contains("nhận") || 
            fullContent.lowercase(Locale.getDefault()).contains("cộng") ||
            fullContent.lowercase(Locale.getDefault()).contains("gd:") ||
            fullContent.lowercase(Locale.getDefault()).contains("biến động số dư")

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

        // Tự động nhận diện chi nhánh nếu trong nội dung có mã chi nhánh
        val storeCode = when {
            extractedContent.contains("TRAM01", ignoreCase = true) -> "TRAM01"
            extractedContent.contains("TRAM02", ignoreCase = true) -> "TRAM02"
            extractedContent.contains("TRAM03", ignoreCase = true) -> "TRAM03"
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
        // Regex tìm số tiền dạng: +35.000, + 35,000, nhận 50.000VND, GD: 100.000d...
        val patterns = listOf(
            Pattern.compile("""(?:\+|cộng|nhận|gd:\s*)\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})""", Pattern.CASE_INSENSITIVE),
            Pattern.compile("""([0-9]{1,3}(?:[.,][0-9]{3})+)\s*(?:VND|vnd|VNĐ|vnđ|d|đ)""", Pattern.CASE_INSENSITIVE),
            Pattern.compile("""\+\s*([0-9.,]+)""")
        )

        for (pattern in patterns) {
            val matcher = pattern.matcher(text)
            if (matcher.find()) {
                val rawNum = matcher.group(1)?.replace(".", "")?.replace(",", "") ?: ""
                val amount = rawNum.toLongOrNull()
                if (amount != null && amount > 0) {
                    return amount
                }
            }
        }
        return 0L
    }

    private fun parseContent(text: String): String {
        val keywords = listOf("ND:", "Nội dung:", "Noi dung:", "Lý do:", "Ref:", "GD:", "MGD:", "tại", "memo:")
        for (kw in keywords) {
            val idx = text.indexOf(kw, ignoreCase = true)
            if (idx != -1) {
                return text.substring(idx + kw.length).trim().take(120)
            }
        }
        return text.take(120)
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
                Log.d(TAG, "Đã đồng bộ giao dịch lên Firebase thành công [$storeCode]: $amount VND")
            } else {
                Log.e(TAG, "Lỗi đồng bộ Firebase [$storeCode], mã lỗi: $responseCode")
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Lỗi kết nối Firebase: ${e.message}", e)
        }
    }
}

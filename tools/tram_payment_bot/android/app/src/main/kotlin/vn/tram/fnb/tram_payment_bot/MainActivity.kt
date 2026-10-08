package vn.tram.fnb.tram_payment_bot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "vn.tram.fnb.tram_payment_bot/methods"
    private val EVENT_CHANNEL = "vn.tram.fnb.tram_payment_bot/events"

    private var eventSink: EventChannel.EventSink? = null
    private val executor = Executors.newSingleThreadExecutor()

    private val paymentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BankNotificationListener.ACTION_NEW_PAYMENT) {
                val data = mapOf(
                    "eventId" to (intent.getStringExtra("eventId") ?: ""),
                    "storeCode" to (intent.getStringExtra("storeCode") ?: "TRAM01"),
                    "amount" to intent.getLongExtra("amount", 0L),
                    "content" to (intent.getStringExtra("content") ?: ""),
                    "bankName" to (intent.getStringExtra("bankName") ?: ""),
                    "timeStr" to (intent.getStringExtra("timeStr") ?: ""),
                    "rawText" to (intent.getStringExtra("rawText") ?: "")
                )
                runOnUiThread {
                    eventSink?.success(data)
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationPermissionGranted" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "setDefaultStoreCode" -> {
                    val code = call.argument<String>("storeCode") ?: "TRAM01"
                    val prefs = getSharedPreferences("tram_bot_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putString("default_store_code", code).apply()
                    result.success(true)
                }
                "getDefaultStoreCode" -> {
                    val prefs = getSharedPreferences("tram_bot_prefs", Context.MODE_PRIVATE)
                    val code = prefs.getString("default_store_code", "TRAM01") ?: "TRAM01"
                    result.success(code)
                }
                "sendTestPayment" -> {
                    val storeCode = call.argument<String>("storeCode") ?: "TRAM01"
                    val amount = (call.argument<Number>("amount") ?: 30000).toLong()
                    val content = call.argument<String>("content") ?: "${storeCode}_BAN_D5"
                    val bankName = call.argument<String>("bankName") ?: "MB Bank (Test)"

                    val now = System.currentTimeMillis()
                    val timeStr = SimpleDateFormat("HH:mm:ss dd/MM/yyyy", Locale.getDefault()).format(Date(now))
                    val eventId = "TEST_${now}_${(1000..9999).random()}"

                    executor.execute {
                        syncTestToFirebase(storeCode, eventId, amount, content, bankName, now, timeStr)
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                val filter = IntentFilter(BankNotificationListener.ACTION_NEW_PAYMENT)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(paymentReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(paymentReceiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                try {
                    unregisterReceiver(paymentReceiver)
                } catch (_: Exception) {}
                eventSink = null
            }
        })
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(pkgName)
    }

    private fun syncTestToFirebase(
        storeCode: String,
        eventId: String,
        amount: Long,
        content: String,
        bankName: String,
        timestamp: Long,
        timeStr: String
    ) {
        try {
            val urlString = "${BankNotificationListener.FIREBASE_BASE_URL}/stores/$storeCode/payment_events/$eventId.json"
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
                put("rawText", "Giao dịch test thử nghiệm từ Trạm Bot")
                put("timestamp", timestamp)
                put("timeStr", timeStr)
                put("status", "UNPROCESSED")
            }

            OutputStreamWriter(conn.outputStream).use { writer ->
                writer.write(json.toString())
                writer.flush()
            }

            conn.responseCode
            conn.disconnect()

            // Gửi event về Flutter
            val data = mapOf(
                "eventId" to eventId,
                "storeCode" to storeCode,
                "amount" to amount,
                "content" to content,
                "bankName" to bankName,
                "timeStr" to timeStr,
                "rawText" to "Giao dịch test thử nghiệm từ Trạm Bot"
            )
            runOnUiThread {
                eventSink?.success(data)
            }
        } catch (_: Exception) {}
    }
}

package com.example.tramapp;

import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.MultiFormatWriter;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.journeyapps.barcodescanner.BarcodeEncoder;

public class QRCodeActivity extends AppCompatActivity {

    private ImageView imgQRCode;
    private TextView txtTableInfo, txtQRUrl;
    private String tableName, tableZone;
    private String qrUrl;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_qr_code);

        Toolbar toolbar = findViewById(R.id.toolbar_qr);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            toolbar.setNavigationOnClickListener(v -> finish());
        }

        imgQRCode = findViewById(R.id.img_qr_code);
        txtTableInfo = findViewById(R.id.txt_table_info);
        txtQRUrl = findViewById(R.id.txt_qr_url);

        // Get table info from intent
        tableName = getIntent().getStringExtra("TABLE_NAME");
        tableZone = getIntent().getStringExtra("TABLE_ZONE");

        if (tableName == null || tableName.isEmpty()) {
            Toast.makeText(this, "Lỗi: Không có thông tin bàn", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        // Build QR URL
        qrUrl = "https://ungdungdidong-94edd.web.app/?table=" + Uri.encode(tableName) + "&zone=" + Uri.encode(tableZone);
        
        txtTableInfo.setText("Bàn: " + tableName + " - " + tableZone);
        txtQRUrl.setText(qrUrl);

        generateQRCode(qrUrl);

        findViewById(R.id.btn_share_qr).setOnClickListener(v -> shareQRCode());
        findViewById(R.id.btn_copy_url).setOnClickListener(v -> copyUrlToClipboard());
        findViewById(R.id.btn_print_qr).setOnClickListener(v -> printQRCode());
    }

    private void printQRCode() {
        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
        String printerIp = prefs.getString("BILL_PRINTER_IP", "");
        if (printerIp.isEmpty()) {
            Toast.makeText(this, "Chưa cài đặt IP máy in! Vào Cấu hình hệ thống để cài.", Toast.LENGTH_LONG).show();
            return;
        }
        EscPosPrinter.TableQRData tableQRData = new EscPosPrinter.TableQRData(tableName, tableZone, qrUrl);
        EscPosPrinter.printTableQRDirect(printerIp, tableQRData);
        Toast.makeText(this, "Đang gửi lệnh in QR bàn " + tableName + "...", Toast.LENGTH_SHORT).show();
    }

    private void generateQRCode(String url) {
        try {
            MultiFormatWriter writer = new MultiFormatWriter();
            BitMatrix bitMatrix = writer.encode(url, BarcodeFormat.QR_CODE, 512, 512);
            BarcodeEncoder encoder = new BarcodeEncoder();
            Bitmap bitmap = encoder.createBitmap(bitMatrix);
            imgQRCode.setImageBitmap(bitmap);
        } catch (WriterException e) {
            Log.e("QRCode", "Error generating QR code", e);
            Toast.makeText(this, "Lỗi tạo mã QR", Toast.LENGTH_SHORT).show();
        }
    }

    private void shareQRCode() {
        Intent shareIntent = new Intent(Intent.ACTION_SEND);
        shareIntent.setType("text/plain");
        shareIntent.putExtra(Intent.EXTRA_TEXT, "Quét mã QR để order: " + qrUrl);
        startActivity(Intent.createChooser(shareIntent, "Chia sẻ mã QR"));
    }

    private void copyUrlToClipboard() {
        android.content.ClipboardManager clipboard = 
            (android.content.ClipboardManager) getSystemService(android.content.Context.CLIPBOARD_SERVICE);
        android.content.ClipData clip = android.content.ClipData.newPlainText("QR URL", qrUrl);
        clipboard.setPrimaryClip(clip);
        Toast.makeText(this, "Đã copy link!", Toast.LENGTH_SHORT).show();
    }
}

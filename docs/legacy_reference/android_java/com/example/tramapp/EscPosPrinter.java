package com.example.tramapp;

import android.os.AsyncTask;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.text.DecimalFormat;
import java.text.Normalizer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

public class EscPosPrinter {

    public static void printKitchenOrderDirect(String ipAddress, KitchenOrderEntity order) {
        if (ipAddress == null || ipAddress.isEmpty()) return;
        new PrintTask(ipAddress, order, null, false, null, null, null).execute();
    }

    public static void printBillDirect(String ipAddress, OrderHistoryEntity history, boolean includeQR, String qrData) {
        if (ipAddress == null || ipAddress.isEmpty()) return;
        new PrintTask(ipAddress, null, history, includeQR, qrData, null, null).execute();
    }

    public static void printReportDirect(String ipAddress, ReportData report) {
        if (ipAddress == null || ipAddress.isEmpty()) return;
        new PrintTask(ipAddress, null, null, false, null, report, null).execute();
    }

    public static void printTableQRDirect(String ipAddress, TableQRData tableQR) {
        if (ipAddress == null || ipAddress.isEmpty()) return;
        new PrintTask(ipAddress, null, null, false, null, null, tableQR).execute();
    }

    public static class TableQRData {
        public String tableName;
        public String tableZone;
        public String qrUrl; // URL to encode as QR
        public TableQRData(String tableName, String tableZone, String qrUrl) {
            this.tableName = tableName;
            this.tableZone = tableZone;
            this.qrUrl = qrUrl;
        }
    }

    public static String removeAccent(String s) {
        if (s == null) return "";
        String temp = Normalizer.normalize(s, Normalizer.Form.NFD);
        Pattern pattern = Pattern.compile("\\p{InCombiningDiacriticalMarks}+");
        String out = pattern.matcher(temp).replaceAll("");
        return out.replaceAll("đ", "d").replaceAll("Đ", "D").replaceAll("[^\\p{ASCII}]", "");
    }

    public static String generateVietQRText(String bankId, String accountNo, String accountName, int amount, String memo) {
        try {
            String bin = mapBankIdToBin(bankId);
            String safeAcc = accountNo.trim().replaceAll("\\s+", "");
            String safeName = removeAccent(accountName).toUpperCase().replaceAll("[^A-Z0-9 ]", "").trim();
            if (safeName.isEmpty()) safeName = "TRAM APP";
            String cleanMemo = removeAccent(memo).toUpperCase().replaceAll("[^A-Z0-9 ]", "").trim();
            StringBuilder sb = new StringBuilder();
            sb.append("000201");
            sb.append("010212");
            StringBuilder pspData = new StringBuilder();
            pspData.append("0006").append(bin);
            pspData.append("01").append(String.format("%02d", safeAcc.length())).append(safeAcc);
            StringBuilder f38Value = new StringBuilder();
            f38Value.append("0010A000000727");
            f38Value.append("01").append(String.format("%02d", pspData.length())).append(pspData.toString());
            f38Value.append("0208QRIBFTTA");
            sb.append("38").append(String.format("%02d", f38Value.length())).append(f38Value.toString());
            sb.append("52040000");
            sb.append("5303704");
            if (amount > 0) {
                String sAmount = String.valueOf(amount);
                sb.append("54").append(String.format("%02d", sAmount.length())).append(sAmount);
            }
            sb.append("5802VN");
            sb.append("59").append(String.format("%02d", safeName.length())).append(safeName);
            if (!cleanMemo.isEmpty()) {
                if (cleanMemo.length() > 25) cleanMemo = cleanMemo.substring(0, 25);
                String memoSub = "08" + String.format("%02d", cleanMemo.length()) + cleanMemo;
                sb.append("62").append(String.format("%02d", memoSub.length())).append(memoSub);
            }
            sb.append("6304");
            String payload = sb.toString();
            return payload + crc16(payload);
        } catch (Exception e) { return ""; }
    }

    private static String mapBankIdToBin(String id) {
        if (id == null) return "970422";
        id = id.toUpperCase().trim();
        if (id.matches("\\d{6}")) return id;
        switch (id) {
            case "MB": case "MBBANK": return "970422";
            case "VCB": case "VIETCOMBANK": return "970436";
            case "VTB": case "VIETINBANK": return "970415";
            case "BIDV": return "970418";
            case "AGRIBANK": return "970405";
            case "ACB": return "970416";
            case "TPB": case "TPBANK": return "970423";
            case "VPB": case "VPBANK": return "970432";
            case "TCB": case "TECHCOMBANK": return "970407";
            case "HDB": case "HDBANK": return "970437";
            case "VIB": return "970441";
            case "STB": case "SACOMBANK": return "970403";
            case "SHB": return "970443";
            case "MSB": return "970426";
            case "LPB": return "970449";
            case "OCB": return "970448";
            default: return "970422";
        }
    }

    private static String crc16(String data) {
        int crc = 0xFFFF;
        byte[] bytes = data.getBytes(StandardCharsets.US_ASCII);
        for (byte b : bytes) {
            crc ^= (b & 0xFF) << 8;
            for (int i = 0; i < 8; i++) {
                if ((crc & 0x8000) != 0) crc = (crc << 1) ^ 0x1021;
                else crc <<= 1;
            }
        }
        return String.format("%04X", crc & 0xFFFF);
    }

    public static class ReportData {
        public String period;
        public int invoiceCount;
        public long totalSales;
        public long cashAmount;
        public long transferAmount;
        public List<Map.Entry<String, Integer>> itemStats;
    }

    private static class PrintTask extends AsyncTask<Void, Void, Boolean> {
        private String ip;
        private KitchenOrderEntity kitchenOrder;
        private OrderHistoryEntity billHistory;
        private boolean includeQR;
        private String qrData;
        private ReportData report;
        private TableQRData tableQR;

        PrintTask(String ip, KitchenOrderEntity kitchenOrder, OrderHistoryEntity billHistory, boolean includeQR, String qrData, ReportData report, TableQRData tableQR) {
            this.ip = ip;
            this.kitchenOrder = kitchenOrder;
            this.billHistory = billHistory;
            this.includeQR = includeQR;
            this.qrData = qrData;
            this.report = report;
            this.tableQR = tableQR;
        }

        @Override
        protected Boolean doInBackground(Void... voids) {
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress(ip, 9100), 4000);
                OutputStream os = socket.getOutputStream();
                os.write(new byte[]{0x1B, 0x40});
                if (kitchenOrder != null) printKitchen(os);
                else if (billHistory != null) printBill(os);
                else if (report != null) printReport(os);
                else if (tableQR != null) printTableQR(os);
                os.write("\n\n\n\n".getBytes("US-ASCII"));
                os.write(new byte[]{0x1D, 0x56, 0x41, 0x00});
                os.flush();
                return true;
            } catch (Exception e) { return false; }
        }

        private void printKitchen(OutputStream os) throws Exception {
            os.write(new byte[]{0x1B, 0x61, 0x01, 0x1D, 0x21, 0x11});
            os.write((removeAccent("PHIEU BAO BEP") + "\n\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x61, 0x00, 0x1D, 0x21, 0x00});
            os.write(("Ban: " + removeAccent(kitchenOrder.tableName) + "\n").getBytes("US-ASCII"));
            os.write(("Gio: " + new SimpleDateFormat("HH:mm:ss dd/MM", Locale.getDefault()).format(new Date(kitchenOrder.timestamp)) + "\n").getBytes("US-ASCII"));
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            ArrayList<Product> products = new Gson().fromJson(kitchenOrder.itemsJson, new TypeToken<ArrayList<Product>>(){}.getType());
            for (Product p : products) {
                os.write(new byte[]{0x1D, 0x21, 0x01});
                os.write((removeAccent(p.getName()) + " x" + p.getQuantity() + "\n").getBytes("US-ASCII"));
                if (p.getNote() != null && !p.getNote().trim().isEmpty()) {
                    os.write(new byte[]{0x1D, 0x21, 0x00});
                    os.write((" -> " + removeAccent(p.getNote()) + "\n").getBytes("US-ASCII"));
                }
            }
        }

        private void printBill(OutputStream os) throws Exception {
            os.write(new byte[]{0x1B, 0x61, 0x01, 0x1D, 0x21, 0x11});
            os.write((removeAccent("TRAM APP") + "\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1D, 0x21, 0x00});
            os.write((removeAccent("HOA DON THANH TOAN") + "\n\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x61, 0x00});
            os.write(("HD: " + billHistory.orderCode + "\n").getBytes("US-ASCII"));
            os.write(("Ban: " + removeAccent(billHistory.tableName) + "\n").getBytes("US-ASCII"));
            os.write(("Gio: " + new SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault()).format(new Date(billHistory.timestamp)) + "\n").getBytes("US-ASCII"));
            os.write("-------------------------------------------------\n".getBytes("US-ASCII"));
            ArrayList<Product> items = new Gson().fromJson(billHistory.itemsJson, new TypeToken<ArrayList<Product>>(){}.getType());
            DecimalFormat df = new DecimalFormat("#,###");
            for (Product p : items) {
                os.write((removeAccent(p.getName()) + " x" + p.getQuantity() + "\n").getBytes("US-ASCII"));
                if (p.getNote() != null && !p.getNote().trim().isEmpty()) {
                    os.write(("  (" + removeAccent(p.getNote()) + ")\n").getBytes("US-ASCII"));
                }
                os.write(new byte[]{0x1B, 0x61, 0x02});
                os.write((df.format((long)p.getPrice() * p.getQuantity()) + "d\n").getBytes("US-ASCII"));
                os.write(new byte[]{0x1B, 0x61, 0x00});
            }
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            os.write(new byte[]{0x1D, 0x21, 0x01, 0x1B, 0x61, 0x02});
            os.write(("TONG: " + df.format(billHistory.totalAmount) + "d\n").getBytes("US-ASCII"));
            if (includeQR && qrData != null && !qrData.isEmpty()) {
                os.write(new byte[]{0x1B, 0x61, 0x01, 0x1D, 0x21, 0x00});
                os.write("\nQUET MA CHUYEN KHOAN\n".getBytes("US-ASCII"));
                printQRCode(os, qrData);
            }
            os.write(new byte[]{0x1B, 0x61, 0x01});
            os.write("\nCAM ON QUY KHACH!\n".getBytes("US-ASCII"));
        }

        private void printReport(OutputStream os) throws Exception {
            DecimalFormat df = new DecimalFormat("#,###");
            os.write(new byte[]{0x1B, 0x61, 0x01, 0x1D, 0x21, 0x11});
            os.write((removeAccent("BAO CAO DOANH THU") + "\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1D, 0x21, 0x00});
            os.write((removeAccent(report.period) + "\n\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x61, 0x00});
            os.write(("So hoa don: " + report.invoiceCount + "\n").getBytes("US-ASCII"));
            os.write(("Tong doanh thu: " + df.format(report.totalSales) + "d\n").getBytes("US-ASCII"));
            os.write((" - Tien mat: " + df.format(report.cashAmount) + "d\n").getBytes("US-ASCII"));
            os.write((" - Chuyen khoan: " + df.format(report.transferAmount) + "d\n").getBytes("US-ASCII"));
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x61, 0x01, 0x1B, 0x45, 0x01});
            os.write((removeAccent("HANG HOA BAN RA") + "\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x45, 0x00, 0x1B, 0x61, 0x00});
            if (report.itemStats != null) {
                for (Map.Entry<String, Integer> entry : report.itemStats) {
                    os.write((removeAccent(entry.getKey()) + ": " + entry.getValue() + "\n").getBytes("US-ASCII"));
                }
            }
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            os.write(new byte[]{0x1B, 0x61, 0x01});
            os.write(("\nNgay in: " + new SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault()).format(new Date()) + "\n").getBytes("US-ASCII"));
        }

        private void printTableQR(OutputStream os) throws Exception {
            // Header
            os.write(new byte[]{0x1B, 0x61, 0x01}); // center
            os.write(new byte[]{0x1D, 0x21, 0x11}); // double size
            os.write((removeAccent("MA QR DAT MON") + "\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1D, 0x21, 0x00});
            os.write((removeAccent("Quet ma de dat mon online") + "\n").getBytes("US-ASCII"));
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            // Table name
            os.write(new byte[]{0x1D, 0x21, 0x11});
            os.write((removeAccent(tableQR.tableName) + "\n").getBytes("US-ASCII"));
            os.write(new byte[]{0x1D, 0x21, 0x00});
            os.write((removeAccent(tableQR.tableZone) + "\n\n").getBytes("US-ASCII"));
            // Print QR code
            printQRCode(os, tableQR.qrUrl);
            os.write("\n".getBytes("US-ASCII"));
            os.write("--------------------------------\n".getBytes("US-ASCII"));
            os.write((removeAccent("Cam on quy khach!") + "\n").getBytes("US-ASCII"));
        }

        private void printQRCode(OutputStream os, String data) throws Exception {
            os.write(0x0A);
            byte[] dBytes = data.getBytes(StandardCharsets.US_ASCII);
            int store_len = dBytes.length + 3;
            os.write(new byte[]{0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00});
            os.write(new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06});
            os.write(new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31});
            os.write(new byte[]{0x1D, 0x28, 0x6B, (byte)(store_len%256), (byte)(store_len/256), 0x31, 0x50, 0x30});
            os.write(dBytes);
            os.write(new byte[]{0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30});
            os.write(0x0A);
        }
    }
}

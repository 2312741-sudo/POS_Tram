package com.example.tramapp;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.text.DecimalFormat;
import java.text.Normalizer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class OnlineOrderDetailActivity extends AppCompatActivity {

    private static final String TAG = "OnlineOrderDetail";
    private Toolbar toolbar;
    private TextView txtTableInfo, txtTime, txtItems, txtNotes, txtTotal;
    private TextView txtTypeBadge, txtStatusBadge;
    private Button btnDetailConfirm, btnDetailCancel;
    private LinearLayout layoutActionButtons;
    private View cardNotes, cardTotal;
    private Gson gson;

    private int orderId = -1;
    private String firebaseKey;
    private String orderType;
    private String orderStatus;
    private String tableName, tableZone, itemsJson, notes;
    private long timestamp;

    private OnlineOrderDao onlineOrderDao;
    private ProductDao productDao;
    private KitchenOrderDao kitchenOrderDao;
    private TableDao tableDao;
    private List<ProductEntity> localProducts = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_online_order_detail);

        gson = new Gson();

        AppDatabase db = AppDatabase.getInstance(this);
        onlineOrderDao = db.onlineOrderDao();
        productDao = db.productDao();
        kitchenOrderDao = db.kitchenOrderDao();
        tableDao = db.tableDao();
        localProducts = productDao.getAllProducts();

        initViews();
        setupToolbar();
        loadData();
    }

    private void initViews() {
        toolbar = findViewById(R.id.toolbar_detail);
        txtTableInfo = findViewById(R.id.txt_detail_table);
        txtTime = findViewById(R.id.txt_detail_time);
        txtItems = findViewById(R.id.txt_detail_items);
        txtNotes = findViewById(R.id.txt_detail_notes);
        txtTotal = findViewById(R.id.txt_detail_total);
        txtTypeBadge = findViewById(R.id.txt_detail_type_badge);
        txtStatusBadge = findViewById(R.id.txt_detail_status_badge);
        btnDetailConfirm = findViewById(R.id.btn_detail_confirm);
        btnDetailCancel = findViewById(R.id.btn_detail_cancel);
        layoutActionButtons = findViewById(R.id.layout_action_buttons);
        cardNotes = findViewById(R.id.card_notes);
        cardTotal = findViewById(R.id.card_total);
    }

    private void setupToolbar() {
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Chi tiết đơn hàng");
        }
        toolbar.setNavigationOnClickListener(v -> onBackPressed());
    }

    private void loadData() {
        Bundle extras = getIntent().getExtras();
        if (extras == null) { finish(); return; }

        orderId = extras.getInt("ORDER_ID", -1);
        firebaseKey = extras.getString("FIREBASE_KEY");
        tableName = extras.getString("TABLE_NAME", "");
        tableZone = extras.getString("TABLE_ZONE", "");
        itemsJson = extras.getString("ITEMS_JSON", "");
        notes = extras.getString("NOTES", "");
        timestamp = extras.getLong("TIMESTAMP", System.currentTimeMillis());
        orderType = extras.getString("ORDER_TYPE", "ORDER");
        orderStatus = extras.getString("ORDER_STATUS", "PENDING");

        Log.d(TAG, "Order ID=" + orderId + ", type=" + orderType + ", status=" + orderStatus);

        // Bàn + thời gian
        txtTableInfo.setText(String.format("Bàn: %s - %s", tableName, tableZone));
        txtTime.setText("🕐 " + new SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.getDefault())
                .format(new Date(timestamp)));

        // Type badge
        boolean isCallWaiter = "CALL_WAITER".equalsIgnoreCase(orderType);
        if (isCallWaiter) {
            txtTypeBadge.setText("🔔 GỌI PHỤC VỤ");
            txtTypeBadge.setBackgroundResource(R.drawable.badge_bg_orange);
        } else {
            txtTypeBadge.setText("📦 ĐƠN HÀNG");
            txtTypeBadge.setBackgroundResource(R.drawable.badge_bg_green);
        }

        // Status badge
        boolean isPending = isPendingStatus(orderStatus);
        if (isPending) {
            txtStatusBadge.setText("⏳ CHỜ XỬ LÝ");
            txtStatusBadge.setBackgroundResource(R.drawable.badge_bg_orange);
        } else if ("CONFIRMED".equalsIgnoreCase(orderStatus)) {
            txtStatusBadge.setText("✅ ĐÃ XÁC NHẬN");
            txtStatusBadge.setBackgroundResource(R.drawable.badge_bg_green);
        } else if ("CANCELLED".equalsIgnoreCase(orderStatus)) {
            txtStatusBadge.setText("❌ ĐÃ HỦY");
            txtStatusBadge.setBackgroundResource(R.drawable.badge_bg_grey);
        } else {
            txtStatusBadge.setText(orderStatus != null ? orderStatus : "");
            txtStatusBadge.setBackgroundResource(R.drawable.badge_bg_grey);
        }

        // Hiện/ẩn các card và nút theo loại đơn
        if (isCallWaiter) {
            txtItems.setText("Khách đang gọi nhân viên đến phục vụ.");
            if (cardTotal != null) cardTotal.setVisibility(View.GONE);
        } else {
            // Parse và hiển thị items
            ArrayList<Map<String, Object>> parsedItems = parseItems(itemsJson);
            txtItems.setText(formatItems(parsedItems));
            int total = calculateTotal(parsedItems);
            if (cardTotal != null) cardTotal.setVisibility(View.VISIBLE);
            txtTotal.setText(new DecimalFormat("#,###").format(total) + "đ");
        }

        // Ghi chú
        if (notes != null && !notes.isEmpty()) {
            if (cardNotes != null) cardNotes.setVisibility(View.VISIBLE);
            txtNotes.setText(notes);
        } else {
            if (cardNotes != null) cardNotes.setVisibility(View.GONE);
        }

        // Nút thao tác chỉ hiện khi PENDING
        if (isPending) {
            layoutActionButtons.setVisibility(View.VISIBLE);
            if (isCallWaiter) {
                btnDetailConfirm.setText("✅ Đã nhận");
            } else {
                btnDetailConfirm.setText("✅ Xác nhận đơn");
            }
            btnDetailConfirm.setOnClickListener(v -> confirmOrder());
            btnDetailCancel.setOnClickListener(v -> cancelOrder());
        } else {
            layoutActionButtons.setVisibility(View.GONE);
        }
    }

    private boolean isPendingStatus(String status) {
        if (status == null) return true;
        String norm = status.toLowerCase().trim();
        return norm.equals("pending") || norm.isEmpty() || norm.equals("null");
    }

    private void confirmOrder() {
        if (orderId < 0) { Toast.makeText(this, "Không tìm thấy đơn", Toast.LENGTH_SHORT).show(); return; }
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                OnlineOrderEntity order = onlineOrderDao.getOrderById(orderId);
                if (order == null) {
                    runOnUiThread(() -> Toast.makeText(this, "Không tìm thấy đơn", Toast.LENGTH_SHORT).show());
                    return;
                }

                if ("CALL_WAITER".equalsIgnoreCase(order.type)) {
                    order.status = "CONFIRMED";
                    onlineOrderDao.update(order);
                    if (order.firebaseKey != null) {
                        FirebaseHelper.getOnlineOrdersRef().child(order.firebaseKey).child("status").setValue("CONFIRMED");
                    }
                    runOnUiThread(() -> {
                        Toast.makeText(this, "✅ Đã xác nhận gọi nhân viên", Toast.LENGTH_SHORT).show();
                        setResult(RESULT_OK);
                        finish();
                    });
                    return;
                }

                // ORDER: tìm bàn và gửi bếp
                TableEntity table = findMatchingTable(order.tableName, order.tableZone);
                if (table == null) {
                    runOnUiThread(() -> Toast.makeText(this, "❌ Không tìm thấy bàn tương ứng", Toast.LENGTH_SHORT).show());
                    return;
                }

                String mappedJson = mapFirebaseItemsToLocalProducts(order.itemsJson);

                table.inUse = true;
                table.currentOrderJson = mappedJson;
                tableDao.updateTable(table);

                KitchenOrderEntity kitchenOrder = new KitchenOrderEntity();
                kitchenOrder.tableName = table.name;
                kitchenOrder.itemsJson = mappedJson;
                kitchenOrder.timestamp = System.currentTimeMillis();
                kitchenOrder.isDone = false;
                kitchenOrderDao.insertKitchenOrder(kitchenOrder);

                com.google.firebase.database.DatabaseReference ref = FirebaseHelper.getKitchenOrdersRef().push();
                kitchenOrder.firebaseKey = ref.getKey();
                ref.setValue(kitchenOrder);

                order.status = "CONFIRMED";
                onlineOrderDao.update(order);
                if (order.firebaseKey != null) {
                    FirebaseHelper.getOnlineOrdersRef().child(order.firebaseKey).child("status").setValue("CONFIRMED");
                }
                FirebaseHelper.getTablesRef().child(table.zone + "_" + table.name).setValue(table);

                runOnUiThread(() -> {
                    Toast.makeText(this, "✅ Đã xác nhận - Gửi đến bếp thành công!", Toast.LENGTH_SHORT).show();
                    setResult(RESULT_OK);
                    finish();
                });

            } catch (Exception e) {
                Log.e(TAG, "Error confirming", e);
                runOnUiThread(() -> Toast.makeText(this, "Lỗi: " + e.getMessage(), Toast.LENGTH_SHORT).show());
            }
        });
    }

    private void cancelOrder() {
        if (orderId < 0) { Toast.makeText(this, "Không tìm thấy đơn", Toast.LENGTH_SHORT).show(); return; }
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                OnlineOrderEntity order = onlineOrderDao.getOrderById(orderId);
                if (order == null) {
                    runOnUiThread(() -> Toast.makeText(this, "Không tìm thấy đơn", Toast.LENGTH_SHORT).show());
                    return;
                }
                order.status = "CANCELLED";
                onlineOrderDao.update(order);
                if (order.firebaseKey != null) {
                    FirebaseHelper.getOnlineOrdersRef().child(order.firebaseKey).child("status").setValue("CANCELLED");
                }
                runOnUiThread(() -> {
                    Toast.makeText(this, "Đã hủy đơn hàng", Toast.LENGTH_SHORT).show();
                    setResult(RESULT_OK);
                    finish();
                });
            } catch (Exception e) {
                Log.e(TAG, "Error cancelling", e);
                runOnUiThread(() -> Toast.makeText(this, "Lỗi: " + e.getMessage(), Toast.LENGTH_SHORT).show());
            }
        });
    }

    // ---- Helpers ----

    private ArrayList<Map<String, Object>> parseItems(String itemsJson) {
        ArrayList<Map<String, Object>> result = new ArrayList<>();
        if (itemsJson == null || itemsJson.isEmpty() || "null".equalsIgnoreCase(itemsJson.trim())) return result;
        try {
            if (itemsJson.trim().startsWith("[")) {
                Type type = new TypeToken<ArrayList<Map<String, Object>>>() {}.getType();
                ArrayList<Map<String, Object>> parsed = gson.fromJson(itemsJson, type);
                if (parsed != null) result = parsed;
            } else if (itemsJson.trim().startsWith("{")) {
                Type type = new TypeToken<Map<String, Object>>() {}.getType();
                Map<String, Object> single = gson.fromJson(itemsJson, type);
                result.add(single);
            }
        } catch (Exception e) {
            Log.e(TAG, "Parse items error", e);
        }
        return result;
    }

    private String formatItems(ArrayList<Map<String, Object>> items) {
        if (items == null || items.isEmpty()) return "Không có món";
        StringBuilder sb = new StringBuilder();
        for (Map<String, Object> item : items) {
            if (item == null) continue;
            String name = item.get("name") != null ? String.valueOf(item.get("name")) : "Món";
            int quantity = 0;
            Object q = item.get("quantity");
            if (q instanceof Number) quantity = ((Number) q).intValue();
            else if (q != null) { try { quantity = Integer.parseInt(String.valueOf(q)); } catch (Exception ignored) {} }
            int price = 0;
            Object p = item.get("price");
            if (p instanceof Number) price = ((Number) p).intValue();
            else if (p != null) { try { price = Integer.parseInt(String.valueOf(p)); } catch (Exception ignored) {} }

            sb.append("• ").append(name)
              .append("  x").append(quantity)
              .append("  =  ").append(new DecimalFormat("#,###").format((long) price * quantity)).append("đ\n");
            String note = item.get("note") != null ? String.valueOf(item.get("note")).trim() : "";
            if (!note.isEmpty()) {
                sb.append("  (Ghi chú: ").append(note).append(")\n");
            }
        }
        return sb.toString().trim();
    }

    private int calculateTotal(ArrayList<Map<String, Object>> items) {
        if (items == null) return 0;
        int sum = 0;
        for (Map<String, Object> item : items) {
            if (item == null) continue;
            int quantity = 0, price = 0;
            Object q = item.get("quantity");
            if (q instanceof Number) quantity = ((Number) q).intValue();
            else if (q != null) { try { quantity = Integer.parseInt(String.valueOf(q)); } catch (Exception ignored) {} }
            Object p = item.get("price");
            if (p instanceof Number) price = ((Number) p).intValue();
            else if (p != null) { try { price = Integer.parseInt(String.valueOf(p)); } catch (Exception ignored) {} }
            sum += price * quantity;
        }
        return sum;
    }

    private String normalizeText(String input) {
        if (input == null) return "";
        return Normalizer.normalize(input, Normalizer.Form.NFD).replaceAll("\\p{M}", "").toLowerCase().trim();
    }

    private TableEntity findMatchingTable(String tableName, String tableZone) {
        if (tableName == null || tableName.trim().isEmpty()) return null;
        String nt = normalizeText(tableName), nz = normalizeText(tableZone);
        List<TableEntity> all = tableDao.getAllTables();
        for (TableEntity t : all) {
            if (t == null || t.name == null) continue;
            if (normalizeText(t.name).equals(nt) && t.zone != null && normalizeText(t.zone).equals(nz)) return t;
        }
        for (TableEntity t : all) {
            if (t == null || t.name == null) continue;
            if (normalizeText(t.name).equals(nt)) return t;
        }
        return null;
    }

    private ProductEntity findLocalProductByName(String name) {
        if (name == null || name.trim().isEmpty()) return null;
        String target = normalizeText(name);
        for (ProductEntity product : localProducts) {
            if (product == null || product.name == null) continue;
            if (normalizeText(product.name).equals(target)) return product;
        }
        return null;
    }

    private String mapFirebaseItemsToLocalProducts(String itemsJson) {
        if (itemsJson == null || itemsJson.trim().isEmpty() || "null".equalsIgnoreCase(itemsJson.trim())) return itemsJson;
        try {
            Gson gson = new Gson();
            Type type = new TypeToken<ArrayList<HashMap<String, Object>>>() {}.getType();
            ArrayList<HashMap<String, Object>> items = gson.fromJson(itemsJson, type);
            if (items == null || items.isEmpty()) return itemsJson;

            ArrayList<Product> mappedProducts = new ArrayList<>();
            for (HashMap<String, Object> item : items) {
                if (item == null) continue;
                String itemName = item.get("name") == null ? "" : String.valueOf(item.get("name"));
                int quantity = 0;
                Object q = item.get("quantity");
                if (q instanceof Number) quantity = ((Number) q).intValue();
                else if (q != null) { try { quantity = Integer.parseInt(String.valueOf(q)); } catch (Exception ignored) {} }

                String note = item.get("note") != null ? String.valueOf(item.get("note")) : "";

                ProductEntity lp = findLocalProductByName(itemName);
                if (lp != null) {
                    Product p = new Product(String.valueOf(lp.id), lp.name, lp.price,
                            lp.unit == null ? "" : lp.unit, lp.category == null ? "" : lp.category,
                            lp.imageResourceName == null ? "" : lp.imageResourceName,
                            lp.imageBase64 == null ? "" : lp.imageBase64);
                    p.setQuantity(quantity);
                    p.setNote(note);
                    mappedProducts.add(p);
                } else {
                    int price = 0;
                    Object pv = item.get("price");
                    if (pv instanceof Number) price = ((Number) pv).intValue();
                    Product fb = new Product("", itemName, price, "", "", "", "");
                    fb.setQuantity(quantity);
                    fb.setNote(note);
                    mappedProducts.add(fb);
                }
            }
            return gson.toJson(mappedProducts);
        } catch (Exception e) {
            Log.e(TAG, "Map items error", e);
            return itemsJson;
        }
    }
}

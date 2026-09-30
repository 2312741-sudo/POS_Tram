package com.example.tramapp;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.tabs.TabLayout;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.ValueEventListener;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.lang.reflect.Type;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

public class OnlineOrderActivity extends AppCompatActivity {

    private static final String TAG = "OnlineOrderActivity";

    private Toolbar toolbar;
    private RecyclerView rvOrders;
    private View emptyStateView;
    private TabLayout tabOrderStatus;

    private OnlineOrderDao onlineOrderDao;
    private ProductDao productDao;
    private List<ProductEntity> localProducts = new ArrayList<>();
    private OnlineOrderAdapter adapter;
    private final List<OnlineOrderEntity> allOrders = new ArrayList<>();
    private final List<OnlineOrderEntity> displayedOrders = new ArrayList<>();
    private DatabaseReference firebaseOnlineOrders;
    private KitchenOrderDao kitchenOrderDao;
    private TableDao tableDao;
    private ValueEventListener firebaseListener;

    // 0 = Đang chờ (PENDING), 1 = Đã xử lý (CONFIRMED/CANCELLED)
    private int currentTab = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_online_order);

        AppDatabase db = AppDatabase.getInstance(this);
        onlineOrderDao = db.onlineOrderDao();
        productDao = db.productDao();
        kitchenOrderDao = db.kitchenOrderDao();
        tableDao = db.tableDao();
        localProducts = productDao.getAllProducts();

        firebaseOnlineOrders = FirebaseHelper.getOnlineOrdersRef();

        initViews();
        setupToolbar();
        setupTabs();
        setupRecyclerView();
        loadOrders();
        setupFirebaseListener();
    }

    private void initViews() {
        toolbar = findViewById(R.id.toolbar_online_order);
        rvOrders = findViewById(R.id.rv_online_orders);
        emptyStateView = findViewById(R.id.empty_state_container);
        tabOrderStatus = findViewById(R.id.tab_order_status);
    }

    private void setupToolbar() {
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Đơn hàng QR / Online");
        }
        toolbar.setNavigationOnClickListener(v -> onBackPressed());
    }

    private void setupTabs() {
        if (tabOrderStatus.getTabCount() == 0) {
            tabOrderStatus.addTab(tabOrderStatus.newTab().setText("⏳ Đang chờ"));
            tabOrderStatus.addTab(tabOrderStatus.newTab().setText("✅ Đã xử lý"));
        }
        tabOrderStatus.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override public void onTabSelected(TabLayout.Tab tab) {
                currentTab = tab.getPosition();
                applyFilter();
            }
            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });
    }

    private void setupRecyclerView() {
        adapter = new OnlineOrderAdapter(displayedOrders, new OnlineOrderAdapter.OnlineOrderInteractionListener() {
            @Override
            public void onConfirmOrder(OnlineOrderEntity order) {
                handleConfirmOrder(order);
            }

            @Override
            public void onCancelOrder(OnlineOrderEntity order) {
                handleCancelOrder(order);
            }

            @Override
            public void onViewDetails(OnlineOrderEntity order) {
                handleViewDetails(order);
            }
        });

        rvOrders.setLayoutManager(new LinearLayoutManager(this));
        rvOrders.setAdapter(adapter);
    }

    private void applyFilter() {
        displayedOrders.clear();
        for (OnlineOrderEntity order : allOrders) {
            boolean isPending = isPendingStatus(order.status);
            if (currentTab == 0 && isPending) {
                displayedOrders.add(order);
            } else if (currentTab == 1 && !isPending) {
                displayedOrders.add(order);
            }
        }
        adapter.updateData(new ArrayList<>(displayedOrders));

        // Update tab labels with counts
        int pendingCount = 0, doneCount = 0;
        for (OnlineOrderEntity o : allOrders) {
            if (isPendingStatus(o.status)) pendingCount++;
            else doneCount++;
        }
        TabLayout.Tab t0 = tabOrderStatus.getTabAt(0);
        TabLayout.Tab t1 = tabOrderStatus.getTabAt(1);
        if (t0 != null) t0.setText(pendingCount > 0 ? "⏳ Đang chờ (" + pendingCount + ")" : "⏳ Đang chờ");
        if (t1 != null) t1.setText("✅ Đã xử lý" + (doneCount > 0 ? " (" + doneCount + ")" : ""));

        if (emptyStateView != null) {
            emptyStateView.setVisibility(displayedOrders.isEmpty() ? View.VISIBLE : View.GONE);
        }
    }

    private boolean isPendingStatus(String status) {
        if (status == null) return true;
        String norm = status.toLowerCase().trim();
        return norm.equals("pending") || norm.isEmpty() || norm.equals("null");
    }

    private String normalizeText(String input) {
        if (input == null) return "";
        String normalized = Normalizer.normalize(input, Normalizer.Form.NFD);
        return normalized.replaceAll("\\p{M}", "").toLowerCase().trim();
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
        if (itemsJson == null || itemsJson.trim().isEmpty() || "null".equalsIgnoreCase(itemsJson.trim())) {
            return itemsJson;
        }
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
                else if (q != null) {
                    try { quantity = Integer.parseInt(String.valueOf(q)); } catch (Exception ignored) {}
                }

                String note = item.get("note") != null ? String.valueOf(item.get("note")) : "";

                ProductEntity localProduct = findLocalProductByName(itemName);
                if (localProduct != null) {
                    Product product = new Product(String.valueOf(localProduct.id), localProduct.name, localProduct.price,
                            localProduct.unit == null ? "" : localProduct.unit,
                            localProduct.category == null ? "" : localProduct.category,
                            localProduct.imageResourceName == null ? "" : localProduct.imageResourceName,
                            localProduct.imageBase64 == null ? "" : localProduct.imageBase64);
                    product.setQuantity(quantity);
                    product.setNote(note);
                    mappedProducts.add(product);
                } else {
                    int price = 0;
                    Object p = item.get("price");
                    if (p instanceof Number) price = ((Number) p).intValue();
                    else if (p != null) { try { price = Integer.parseInt(String.valueOf(p)); } catch (Exception ignored) {} }
                    Product fallback = new Product("", itemName, price, "", "", "", "");
                    fallback.setQuantity(quantity);
                    fallback.setNote(note);
                    mappedProducts.add(fallback);
                }
            }
            return gson.toJson(mappedProducts);
        } catch (Exception e) {
            Log.e(TAG, "Failed to map Firebase items", e);
            return itemsJson;
        }
    }

    private TableEntity findMatchingTable(String tableName, String tableZone) {
        if (tableName == null || tableName.trim().isEmpty()) return null;
        String normalizedTable = normalizeText(tableName);
        String normalizedZone = normalizeText(tableZone);

        List<TableEntity> allTables = tableDao.getAllTables();
        for (TableEntity table : allTables) {
            if (table == null || table.name == null) continue;
            if (normalizeText(table.name).equals(normalizedTable)) {
                if (table.zone != null && normalizeText(table.zone).equals(normalizedZone)) return table;
            }
        }
        for (TableEntity table : allTables) {
            if (table == null || table.name == null) continue;
            if (normalizeText(table.name).equals(normalizedTable)) return table;
        }
        return null;
    }

    private String mapFirebaseOrderItems(OnlineOrderEntity order) {
        if (order == null || "CALL_WAITER".equalsIgnoreCase(order.type)) {
            return order == null ? null : order.itemsJson;
        }
        String mapped = mapFirebaseItemsToLocalProducts(order.itemsJson);
        return mapped == null ? order.itemsJson : mapped;
    }

    private void loadOrders() {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                Log.d(TAG, "Fetching from Firebase...");
                DataSnapshot snapshot = com.google.android.gms.tasks.Tasks.await(firebaseOnlineOrders.get());

                int syncedCount = 0;
                for (DataSnapshot orderSnapshot : snapshot.getChildren()) {
                    try {
                        String fbKey = orderSnapshot.getKey();
                        OnlineOrderEntity order = orderSnapshot.getValue(OnlineOrderEntity.class);
                        if (order == null) continue;
                        order.firebaseKey = fbKey;
                        order.itemsJson = mapFirebaseOrderItems(order);

                        OnlineOrderEntity existing = onlineOrderDao.getOrderByFirebaseKey(fbKey);
                        if (existing == null) {
                            onlineOrderDao.insert(order);
                        } else {
                            order.id = existing.id;
                            onlineOrderDao.update(order);
                        }
                        syncedCount++;
                    } catch (Exception e) {
                        Log.e(TAG, "Error syncing single order: " + orderSnapshot.getKey(), e);
                    }
                }
                Log.d(TAG, "Synced " + syncedCount + " orders");
            } catch (Exception e) {
                Log.e(TAG, "Fetch online_orders failed", e);
            }

            // Load all orders from DB
            try {
                List<OnlineOrderEntity> dbOrders = onlineOrderDao.getAllOnlineOrders();
                if (dbOrders == null) dbOrders = new ArrayList<>();
                List<OnlineOrderEntity> result = new ArrayList<>(dbOrders);
                Log.d(TAG, "Loaded " + result.size() + " total orders from DB");
                runOnUiThread(() -> {
                    allOrders.clear();
                    allOrders.addAll(result);
                    applyFilter();
                });
            } catch (Exception e) {
                Log.e(TAG, "Error loading orders from database", e);
                runOnUiThread(() -> { allOrders.clear(); applyFilter(); });
            }
        });
    }

    private void setupFirebaseListener() {
        firebaseListener = firebaseOnlineOrders.addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    for (DataSnapshot orderSnapshot : snapshot.getChildren()) {
                        String fbKey = orderSnapshot.getKey();
                        if (fbKey == null) continue;
                        try {
                            OnlineOrderEntity order = orderSnapshot.getValue(OnlineOrderEntity.class);
                            if (order == null) continue;
                            order.firebaseKey = fbKey;
                            order.itemsJson = mapFirebaseOrderItems(order);

                            OnlineOrderEntity existing = onlineOrderDao.getOrderByFirebaseKey(fbKey);
                            if (existing == null) {
                                onlineOrderDao.insert(order);
                            } else {
                                order.id = existing.id;
                                onlineOrderDao.update(order);
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "Error syncing order onDataChange", e);
                        }
                    }

                    List<OnlineOrderEntity> dbOrders = onlineOrderDao.getAllOnlineOrders();
                    if (dbOrders == null) dbOrders = new ArrayList<>();
                    List<OnlineOrderEntity> result = new ArrayList<>(dbOrders);
                    runOnUiThread(() -> {
                        allOrders.clear();
                        allOrders.addAll(result);
                        applyFilter();
                    });
                });
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {
                Log.e(TAG, "Firebase error: " + error.getMessage());
            }
        });
    }

    private void handleConfirmOrder(OnlineOrderEntity order) {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                if ("CALL_WAITER".equalsIgnoreCase(order.type)) {
                    order.status = "CONFIRMED";
                    onlineOrderDao.update(order);
                    if (order.firebaseKey != null) {
                        firebaseOnlineOrders.child(order.firebaseKey).child("status").setValue("CONFIRMED");
                    }
                    runOnUiThread(() -> {
                        Toast.makeText(this, "✅ Đã xác nhận gọi nhân viên", Toast.LENGTH_SHORT).show();
                        loadOrders();
                    });
                    return;
                }

                // ORDER case
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

                DatabaseReference ref = FirebaseHelper.getKitchenOrdersRef().push();
                kitchenOrder.firebaseKey = ref.getKey();
                ref.setValue(kitchenOrder);

                order.status = "CONFIRMED";
                onlineOrderDao.update(order);
                if (order.firebaseKey != null) {
                    firebaseOnlineOrders.child(order.firebaseKey).child("status").setValue("CONFIRMED");
                }

                FirebaseHelper.getTablesRef().child(table.zone + "_" + table.name).setValue(table);

                runOnUiThread(() -> {
                    Toast.makeText(this, "✅ Đã xác nhận - Gửi đến bếp thành công!", Toast.LENGTH_SHORT).show();
                    loadOrders();
                });

            } catch (Exception e) {
                Log.e(TAG, "Error confirming order", e);
                runOnUiThread(() -> Toast.makeText(this, "Lỗi: " + e.getMessage(), Toast.LENGTH_SHORT).show());
            }
        });
    }

    private void handleCancelOrder(OnlineOrderEntity order) {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            order.status = "CANCELLED";
            onlineOrderDao.update(order);
            if (order.firebaseKey != null) {
                firebaseOnlineOrders.child(order.firebaseKey).child("status").setValue("CANCELLED");
            }
            runOnUiThread(() -> {
                Toast.makeText(this, "Đã hủy đơn hàng", Toast.LENGTH_SHORT).show();
                loadOrders();
            });
        });
    }

    private void handleViewDetails(OnlineOrderEntity order) {
        Intent intent = new Intent(this, OnlineOrderDetailActivity.class);
        intent.putExtra("ORDER_ID", order.id);
        intent.putExtra("FIREBASE_KEY", order.firebaseKey);
        intent.putExtra("TABLE_NAME", order.tableName);
        intent.putExtra("TABLE_ZONE", order.tableZone);
        intent.putExtra("ITEMS_JSON", order.itemsJson);
        intent.putExtra("NOTES", order.notes);
        intent.putExtra("TIMESTAMP", order.timestamp);
        intent.putExtra("ORDER_TYPE", order.type);
        intent.putExtra("ORDER_STATUS", order.status);
        startActivityForResult(intent, 100);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 100 && resultCode == RESULT_OK) {
            // Reload nếu có thay đổi từ detail
            loadOrders();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (firebaseListener != null && firebaseOnlineOrders != null) {
            firebaseOnlineOrders.removeEventListener(firebaseListener);
        }
    }
}
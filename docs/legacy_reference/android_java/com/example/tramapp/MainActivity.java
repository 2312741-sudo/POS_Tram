package com.example.tramapp;

import android.content.Intent;
import android.content.SharedPreferences;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import android.app.AlertDialog;
import com.google.firebase.database.ChildEventListener;
import androidx.annotation.Nullable;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;
import com.google.android.material.navigation.NavigationView;
import com.google.android.material.tabs.TabLayout;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends AppCompatActivity {

    private TabLayout tabLayoutStatus;
    private ChipGroup chipGroupZones;
    private RecyclerView rvTables;
    private ImageButton btnMenuSettings, btnOpenMenuManage;
    
    private DrawerLayout drawerLayout;
    private NavigationView navigationView;
    
    private ZoneDao zoneDao;
    private TableAdapter adapter;
    
    private final List<TableEntity> allTables = new ArrayList<>();
    private final List<TableEntity> displayedTables = new ArrayList<>();
    private List<ZoneEntity> allZones = new ArrayList<>();
    
    private String currentZoneFilter = "";
    private int currentTabFilter = 0;
    private String userRole = "MANAGER";
    private final Set<String> knownOnlineOrderKeys = new HashSet<>();
    private boolean onlineOrderFirstLoad = true;
    private boolean kitchenNotifFirstLoad = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_table_list);

        // Lấy role, xóa khoảng trắng và chuyển thành chữ hoa
        String roleExtra = getIntent().getStringExtra("USER_ROLE");
        userRole = (roleExtra != null) ? roleExtra.trim().toUpperCase() : "MANAGER";

        AppDatabase db = AppDatabase.getInstance(this);
        zoneDao = db.zoneDao();

        initViews();
        setupNavigationDrawer();
        setupRecyclerView();
        setupTabs();
        handleEvents();
        setupFirebaseSync();
        setupOnlineOrderNotificationSync();
        setupKitchenNotificationSync();
        refreshZones();
    }

    private void initViews() {
        tabLayoutStatus = findViewById(R.id.tabLayout_status);
        chipGroupZones = findViewById(R.id.chipGroup_zones); 
        rvTables = findViewById(R.id.rv_tables);
        btnMenuSettings = findViewById(R.id.btn_menu_settings);
        btnOpenMenuManage = findViewById(R.id.btn_open_menu_manage);
        
        drawerLayout = findViewById(R.id.drawer_layout);
        navigationView = findViewById(R.id.nav_view);
        
        // Chỉ Quản lý mới thấy nút thêm bàn và quản lý menu nhanh
        if (!"MANAGER".equals(userRole)) {
            btnOpenMenuManage.setVisibility(View.GONE);
            View fab = findViewById(R.id.fab_add_table);
            if (fab != null) fab.setVisibility(View.GONE);
        }
    }

    private void setupNavigationDrawer() {
        if (navigationView == null) return;

        // Lấy Header View từ NavigationView
        View headerView = navigationView.getHeaderView(0);
        if (headerView == null) {
            headerView = navigationView.inflateHeaderView(R.layout.nav_header);
        }

        TextView tvUserName = headerView.findViewById(R.id.tv_user_name);
        TextView tvUserRole = headerView.findViewById(R.id.tv_user_role);

        // Thiết lập thông tin dựa trên userRole (đã được toUpperCase)
        if (userRole.contains("STAFF") || userRole.contains("NHÂN VIÊN")) {
            if (tvUserName != null) tvUserName.setText("Nguyên Thanh Tâm");
            if (tvUserRole != null) tvUserRole.setText("Nhân viên");
            navigationView.getMenu().setGroupVisible(R.id.group_manager, false);
        } 
        else if (userRole.contains("KITCHEN") || userRole.contains("BẾP")) {
            if (tvUserName != null) tvUserName.setText("Võ Công Vinh");
            if (tvUserRole != null) tvUserRole.setText("Đầu bếp");
            navigationView.getMenu().setGroupVisible(R.id.group_manager, false);
        } 
        else {
            // Mặc định là MANAGER
            if (tvUserName != null) tvUserName.setText("Nguyễn Đức Tín");
            if (tvUserRole != null) tvUserRole.setText("Quản lý");
            navigationView.getMenu().setGroupVisible(R.id.group_manager, true);
        }

        navigationView.setNavigationItemSelectedListener(item -> {
            int id = item.getItemId();
            if (id == R.id.nav_manage_user) {
                // startActivity(new Intent(this, UserManagementActivity.class));
            } else if (id == R.id.nav_manage_zone) {
                startActivity(new Intent(this, ZoneManagementActivity.class));
            } else if (id == R.id.nav_manage_menu) {
                startActivity(new Intent(this, MenuManagementActivity.class));
            } else if (id == R.id.nav_manage_category) {
                startActivity(new Intent(this, CategoryManagementActivity.class));
            } else if (id == R.id.nav_online_orders) {
                startActivity(new Intent(this, OnlineOrderActivity.class));
            } else if (id == R.id.nav_order_history) {
                Intent h = new Intent(this, OrderHistoryActivity.class);
                h.putExtra("USER_ROLE", userRole);
                startActivity(h);
            } else if (id == R.id.nav_logout) {
                performLogout();
            }
            drawerLayout.closeDrawer(GravityCompat.START);
            return true;
        });
    }

    private void performLogout() {
        SharedPreferences.Editor editor = getSharedPreferences("TramAppPrefs", MODE_PRIVATE).edit();
        editor.clear(); editor.apply();
        startActivity(new Intent(this, LoginActivity.class));
        finish();
    }

    private void setupRecyclerView() {
        adapter = new TableAdapter(displayedTables, new TableAdapter.OnTableInteractionListener() {
            @Override
            public void onTableClick(TableEntity table) {
                Intent intent = new Intent(MainActivity.this, table.inUse ? OrderActivity.class : OrderListActivity.class);
                intent.putExtra("TABLE_DATA", table);
                intent.putExtra("USER_ROLE", userRole);
                startActivity(intent);
            }
            @Override public void onTableLongClick(TableEntity table) {}
            @Override public void onQRCodeClick(TableEntity table) {
                Intent intent = new Intent(MainActivity.this, QRCodeActivity.class);
                intent.putExtra("TABLE_NAME", table.name);
                intent.putExtra("TABLE_ZONE", table.zone);
                startActivity(intent);
            }
            @Override public void onPrintQRClick(TableEntity table) {
                android.content.SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
                String printerIp = prefs.getString("BILL_PRINTER_IP", "");
                if (printerIp.isEmpty()) {
                    Toast.makeText(MainActivity.this, "Chưa cài đặt IP máy in!", Toast.LENGTH_SHORT).show();
                    return;
                }
                String qrUrl = "https://ungdungdidong-94edd.web.app/?table=" +
                        android.net.Uri.encode(table.name) + "&zone=" + android.net.Uri.encode(table.zone);
                EscPosPrinter.printTableQRDirect(printerIp, new EscPosPrinter.TableQRData(table.name, table.zone, qrUrl));
                Toast.makeText(MainActivity.this, "Đang in QR bàn " + table.name + "...", Toast.LENGTH_SHORT).show();
            }
            @Override public void onDeleteClick(TableEntity table) {}
        });
        rvTables.setLayoutManager(new GridLayoutManager(this, 2));
        rvTables.setAdapter(adapter);
    }

    private void setupTabs() {
        if (tabLayoutStatus.getTabCount() == 0) {
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("Tất cả"));
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("Đang dùng"));
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("Trống"));
        }
    }

    private void handleEvents() {
        tabLayoutStatus.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override public void onTabSelected(TabLayout.Tab tab) {
                currentTabFilter = tab.getPosition();
                applyFilters();
            }
            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });

        btnMenuSettings.setOnClickListener(v -> {
            if (drawerLayout != null) {
                drawerLayout.openDrawer(GravityCompat.START);
            }
        });

        btnOpenMenuManage.setOnClickListener(v -> {
            Intent intent = new Intent(this, MenuManagementActivity.class);
            intent.putExtra("USER_ROLE", userRole);
            startActivity(intent);
        });
    }

    private void setupFirebaseSync() {
        FirebaseHelper.getTablesRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                List<TableEntity> fbTables = new ArrayList<>();
                for (DataSnapshot ds : snapshot.getChildren()) {
                    TableEntity table = ds.getValue(TableEntity.class);
                    if (table != null) fbTables.add(table);
                }
                sortTables(fbTables);
                runOnUiThread(() -> {
                    allTables.clear();
                    allTables.addAll(fbTables);
                    applyFilters();
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError error) {}
        });
    }

    private void setupOnlineOrderNotificationSync() {
        if (!userRole.contains("STAFF") && !userRole.contains("NHÂN VIÊN")) return;

        FirebaseHelper.getOnlineOrdersRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<String> newPendingMessages = new ArrayList<>();
                    AppDatabase db = AppDatabase.getInstance(MainActivity.this);
                    OnlineOrderDao onlineOrderDao = db.onlineOrderDao();
                    
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        String key = ds.getKey();
                        if (key == null) continue;

                        try {
                            OnlineOrderEntity order = ds.getValue(OnlineOrderEntity.class);
                            if (order == null) {
                                android.util.Log.w("setupOnlineOrderSync", "Order is null for key: " + key);
                                continue;
                            }
                            
                            order.firebaseKey = key;
                            
                            if (!knownOnlineOrderKeys.contains(key)) {
                                knownOnlineOrderKeys.add(key);
                                
                                // Sync to Room database
                                OnlineOrderEntity existing = onlineOrderDao.getOrderByFirebaseKey(key);
                                if (existing == null) {
                                    onlineOrderDao.insert(order);
                                    android.util.Log.d("setupOnlineOrderSync", "New order synced: " + key);
                                } else {
                                    order.id = existing.id;
                                    // Preserve the already mapped itemsJson from existing order if present
                                    if (existing.itemsJson != null && !existing.itemsJson.isEmpty() && !existing.itemsJson.equals(order.itemsJson)) {
                                        order.itemsJson = existing.itemsJson;
                                    }
                                    onlineOrderDao.update(order);
                                    android.util.Log.d("setupOnlineOrderSync", "Order updated: " + key);
                                }
                                
                                if (!onlineOrderFirstLoad && "PENDING".equalsIgnoreCase(order.status)) {
                                    if ("CALL_WAITER".equalsIgnoreCase(order.type)) {
                                        newPendingMessages.add("Thông báo NV: " + (order.tableName == null ? "không rõ bàn" : order.tableName) + " đang gọi nhân viên");
                                    } else {
                                        newPendingMessages.add("Đơn mới từ " + (order.tableName == null ? "không rõ bàn" : order.tableName));
                                    }
                                }
                            }
                        } catch (Exception e) {
                            android.util.Log.e("setupOnlineOrderSync", "Error processing order " + key, e);
                        }
                    }

                    if (onlineOrderFirstLoad) {
                        onlineOrderFirstLoad = false;
                        return;
                    }

                    if (!newPendingMessages.isEmpty()) {
                        runOnUiThread(() -> {
                            playOnlineOrderSound();
                            Toast.makeText(MainActivity.this, newPendingMessages.get(0), Toast.LENGTH_LONG).show();
                        });
                    }
                });
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {
                android.util.Log.e("setupOnlineOrderSync", "Firebase error: " + error.getMessage());
            }
        });
    }

    private void setupKitchenNotificationSync() {
        FirebaseHelper.getKitchenOrdersRef().addChildEventListener(new ChildEventListener() {
            @Override public void onChildAdded(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override
            public void onChildChanged(@NonNull DataSnapshot snapshot, @Nullable String p) {
                if (kitchenNotifFirstLoad) return;
                try {
                    KitchenOrderEntity order = snapshot.getValue(KitchenOrderEntity.class);
                    if (order != null && order.isDone) {
                        android.util.Log.d("KitchenNotification", "Order completed for table: " + order.tableName);
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            playOnlineOrderSound();
                            new AlertDialog.Builder(MainActivity.this)
                                    .setTitle("Bếp báo xong món")
                                    .setMessage("Bếp đã hoàn thành đơn bàn: " + order.tableName)
                                    .setPositiveButton("Xác nhận", (dialog, which) -> {
                                        dialog.dismiss();
                                    })
                                    .setIcon(android.R.drawable.ic_dialog_info)
                                    .setCancelable(false)
                                    .show();
                        });
                    }
                } catch (Exception e) {
                    android.util.Log.e("KitchenNotification", "Error processing kitchen notification", e);
                }
            }
            @Override public void onChildRemoved(@NonNull DataSnapshot s) {}
            @Override public void onChildMoved(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });
        
        FirebaseHelper.getKitchenOrdersRef().addListenerForSingleValueEvent(new ValueEventListener() {
            @Override public void onDataChange(@NonNull DataSnapshot s) { kitchenNotifFirstLoad = false; }
            @Override public void onCancelled(@NonNull DatabaseError e) { kitchenNotifFirstLoad = false; }
        });
    }

    private void playOnlineOrderSound() {
        try {
            Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            Ringtone ringtone = RingtoneManager.getRingtone(getApplicationContext(), notification);
            ringtone.play();
        } catch (Exception ignored) {}
    }

    private void refreshZones() {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            String[] defaultZones = {"Khu A", "Khu B", "Khu C", "Khu D", "Khu E"};
            for (String zoneName : defaultZones) {
                if (zoneDao.countZoneByName(zoneName) == 0) {
                    zoneDao.insertZone(new ZoneEntity(zoneName));
                }
            }
            List<ZoneEntity> zones = zoneDao.getAllZones();
            sortZones(zones);
            runOnUiThread(() -> {
                allZones = zones;
                updateZoneChips();
            });
        });
    }

    private void updateZoneChips() {
        if (chipGroupZones == null) return;
        chipGroupZones.removeAllViews();
        addZoneChip("Tất cả", currentZoneFilter.isEmpty());
        for (ZoneEntity zone : allZones) {
            addZoneChip(zone.name, currentZoneFilter.equals(zone.name));
        }
    }

    private void addZoneChip(String title, boolean isChecked) {
        Chip chip = new Chip(this);
        chip.setText(title);
        chip.setCheckable(true);
        chip.setChecked(isChecked);
        chip.setOnClickListener(v -> { 
            currentZoneFilter = title.equals("Tất cả") ? "" : title; 
            updateZoneChips(); 
            applyFilters(); 
        });
        chipGroupZones.addView(chip);
    }

    private void applyFilters() {
        displayedTables.clear();
        for (TableEntity table : allTables) {
            boolean matchStatus = (currentTabFilter == 0) || (currentTabFilter == 1 && table.inUse) || (currentTabFilter == 2 && !table.inUse);
            boolean matchZone = currentZoneFilter.isEmpty() || (table.zone != null && table.zone.equals(currentZoneFilter));
            if (matchStatus && matchZone) displayedTables.add(table);
        }
        if (adapter != null) adapter.notifyDataSetChanged();
    }

    private void sortTables(List<TableEntity> list) {
        list.sort((t1, t2) -> compareNatural(t1.name, t2.name));
    }

    private void sortZones(List<ZoneEntity> list) {
        list.sort((z1, z2) -> compareNatural(z1.name, z2.name));
    }

    private int compareNatural(String s1, String s2) {
        if (s1 == null || s2 == null) return 0;
        Pattern p = Pattern.compile("(\\d+)|(\\D+)");
        Matcher m1 = p.matcher(s1);
        Matcher m2 = p.matcher(s2);
        while (m1.find() && m2.find()) {
            String g1 = m1.group();
            String g2 = m2.group();
            if (Character.isDigit(g1.charAt(0)) && Character.isDigit(g2.charAt(0))) {
                int i1 = Integer.parseInt(g1);
                int i2 = Integer.parseInt(g2);
                if (i1 != i2) return i1 - i2;
            } else {
                int res = g1.compareToIgnoreCase(g2);
                if (res != 0) return res;
            }
        }
        return s1.length() - s2.length();
    }
}

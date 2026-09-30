package com.example.tramapp;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.navigation.NavigationView;
import com.google.android.material.tabs.TabLayout;
import com.google.firebase.database.ChildEventListener;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class TableListActivity extends AppCompatActivity {

    private TabLayout tabLayoutStatus;
    private ChipGroup chipGroupZones;
    private RecyclerView rvTables;
    private FloatingActionButton btnAddTable;
    private ImageButton btnOpenMenuManage, btnMenuSettings;
    private DrawerLayout drawerLayout;
    private NavigationView navigationView;

    private TableDao tableDao;
    private ZoneDao zoneDao;
    private ProductDao productDao;
    private OnlineOrderDao onlineOrderDao;

    private final List<TableEntity> allTables = new ArrayList<>();
    private final List<TableEntity> displayedTables = new ArrayList<>();
    private List<ZoneEntity> allZones = new ArrayList<>();
    private TableAdapter adapter;

    private int currentTabFilter = 0;
    private String currentZoneFilter = "";
    private String userRole = "MANAGER";
    private String fullName = "";
    private boolean isFirstLoad = true;
    private final Set<String> knownOnlineOrderKeys = new HashSet<>();
    private boolean onlineOrderFirstLoad = true;

    // Cài đặt hệ thống
    private String kitchenPrinterIp, billPrinterIp, bankId, bankAccount, accountName;
    private boolean autoPrintKitchen;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_table_list);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "MANAGER");
        fullName = prefs.getString("FULL_NAME", "Nhân viên");
        loadSystemSettings();

        AppDatabase db = AppDatabase.getInstance(this);
        tableDao = db.tableDao();
        zoneDao = db.zoneDao();
        productDao = db.productDao();
        onlineOrderDao = db.onlineOrderDao();

        initViews();
        setupNavigationDrawer();
        setupTabs();
        setupRecyclerView();
        applyPermissions();
        
        refreshDataFromDb();
        
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                if (zoneDao.getAllZones().isEmpty()) seedDefaultZonesAndTables();
                if (productDao.countProducts() == 0) seedDefaultMenuData();
                ensureTakeawayTable();
            } catch (Exception e) {
                Log.e("TableListActivity", "Error seeding data", e);
            }
        });
        
        handleEvents();
        setupFirebaseSync();
        setupKitchenNotificationSync();
        setupOnlineOrderNotificationSync();
    }

    private void loadSystemSettings() {
        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
        kitchenPrinterIp = prefs.getString("KITCHEN_PRINTER_IP", "192.168.1.100");
        billPrinterIp = prefs.getString("BILL_PRINTER_IP", "192.168.1.100");
        autoPrintKitchen = prefs.getBoolean("AUTO_PRINT_KITCHEN", true);
        bankId = prefs.getString("BANK_ID", "MB");
        bankAccount = prefs.getString("BANK_ACCOUNT", "123456789");
        accountName = prefs.getString("ACCOUNT_NAME", "TRAM APP");
    }

    private void showSystemSettingsDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("Cấu hình hệ thống");

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(60, 40, 60, 10);

        final EditText inputKitchenIp = new EditText(this);
        inputKitchenIp.setHint("IP Máy in Bếp");
        inputKitchenIp.setText(kitchenPrinterIp);
        layout.addView(inputKitchenIp);

        final EditText inputBillIp = new EditText(this);
        inputBillIp.setHint("IP Máy in Hóa đơn");
        inputBillIp.setText(billPrinterIp);
        layout.addView(inputBillIp);

        final CheckBox cbAuto = new CheckBox(this);
        cbAuto.setText("Tự động in báo bếp khi Lưu bàn");
        cbAuto.setChecked(autoPrintKitchen);
        layout.addView(cbAuto);

        TextView tvBank = new TextView(this);
        tvBank.setText("\nCấu hình QR Chuyển khoản:");
        tvBank.setTypeface(null, android.graphics.Typeface.BOLD);
        layout.addView(tvBank);

        final EditText inputBankId = new EditText(this);
        inputBankId.setHint("Mã Ngân hàng (MB, VCB, VTB...)");
        inputBankId.setText(bankId);
        layout.addView(inputBankId);

        final EditText inputAcc = new EditText(this);
        inputAcc.setHint("Số tài khoản");
        inputAcc.setText(bankAccount);
        layout.addView(inputAcc);

        final EditText inputName = new EditText(this);
        inputName.setHint("Tên chủ tài khoản");
        inputName.setText(accountName);
        layout.addView(inputName);

        builder.setView(layout);

        builder.setPositiveButton("Lưu", (dialog, which) -> {
            kitchenPrinterIp = inputKitchenIp.getText().toString();
            billPrinterIp = inputBillIp.getText().toString();
            autoPrintKitchen = cbAuto.isChecked();
            bankId = inputBankId.getText().toString().toUpperCase();
            bankAccount = inputAcc.getText().toString();
            accountName = inputName.getText().toString().toUpperCase();
            
            SharedPreferences.Editor editor = getSharedPreferences("TramAppPrefs", MODE_PRIVATE).edit();
            editor.putString("KITCHEN_PRINTER_IP", kitchenPrinterIp);
            editor.putString("BILL_PRINTER_IP", billPrinterIp);
            editor.putBoolean("AUTO_PRINT_KITCHEN", autoPrintKitchen);
            editor.putString("BANK_ID", bankId);
            editor.putString("BANK_ACCOUNT", bankAccount);
            editor.putString("ACCOUNT_NAME", accountName);
            editor.apply();
            
            Toast.makeText(this, "Đã lưu cấu hình!", Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("Hủy", null);
        builder.show();
    }

    private void setupNavigationDrawer() {
        if (navigationView == null) return;

        View headerView = navigationView.getHeaderView(0);
        if (headerView == null) {
            headerView = navigationView.inflateHeaderView(R.layout.nav_header);
        }
        
        TextView tvUserName = headerView.findViewById(R.id.tv_user_name);
        TextView tvUserRole = headerView.findViewById(R.id.tv_user_role);
        
        if (tvUserName != null) tvUserName.setText(fullName);
        if (tvUserRole != null) {
            String roleDisplayName = "Nhân viên";
            if ("MANAGER".equals(userRole)) roleDisplayName = "Quản lý";
            else if ("KITCHEN".equals(userRole)) roleDisplayName = "Bếp";
            tvUserRole.setText(roleDisplayName);
        }

        navigationView.setNavigationItemSelectedListener(item -> {
            int id = item.getItemId();
            if (id == R.id.nav_manage_user) {
                startActivity(new Intent(this, UserManagementActivity.class));
            } else if (id == R.id.nav_manage_zone) {
                startActivity(new Intent(this, ZoneManagementActivity.class));
            } else if (id == R.id.nav_manage_menu) {
                startActivity(new Intent(this, MenuManagementActivity.class));
            } else if (id == R.id.nav_manage_category) {
                startActivity(new Intent(this, CategoryManagementActivity.class));
            } else if (id == R.id.nav_app_settings) {
                showSystemSettingsDialog();
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

    private void playNotificationSound() {
        try {
            Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            Ringtone r = RingtoneManager.getRingtone(getApplicationContext(), notification);
            r.play();
        } catch (Exception e) {
            Log.e("TableListActivity", "Error playing sound", e);
        }
    }

    private void setupKitchenNotificationSync() {
        FirebaseHelper.getKitchenOrdersRef().addChildEventListener(new ChildEventListener() {
            @Override public void onChildAdded(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override
            public void onChildChanged(@NonNull DataSnapshot snapshot, @Nullable String p) {
                if (isFirstLoad) return;
                try {
                    KitchenOrderEntity order = snapshot.getValue(KitchenOrderEntity.class);
                    if (order != null && order.isDone) {
                        Log.d("KitchenNotification", "Order completed for table: " + order.tableName);
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            playNotificationSound();
                            new AlertDialog.Builder(TableListActivity.this)
                                    .setTitle(R.string.kitchen_notif_title)
                                    .setMessage(getString(R.string.kitchen_notif_msg, order.tableName))
                                    .setPositiveButton(R.string.confirm, (dialog, which) -> {
                                        Log.d("KitchenNotification", "Staff confirmed order for: " + order.tableName);
                                        dialog.dismiss();
                                    })
                                    .setIcon(android.R.drawable.ic_dialog_info)
                                    .setCancelable(false)
                                    .show();
                        });
                    }
                } catch (Exception e) {
                    Log.e("KitchenNotification", "Error processing kitchen notification", e);
                }
            }
            @Override public void onChildRemoved(@NonNull DataSnapshot s) {}
            @Override public void onChildMoved(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override public void onCancelled(@NonNull DatabaseError e) {
                Log.e("KitchenNotification", "Firebase error: " + e.getMessage());
            }
        });
        
        FirebaseHelper.getKitchenOrdersRef().addListenerForSingleValueEvent(new ValueEventListener() {
            @Override public void onDataChange(@NonNull DataSnapshot s) { isFirstLoad = false; }
            @Override public void onCancelled(@NonNull DatabaseError e) { isFirstLoad = false; }
        });
    }

    private void setupOnlineOrderNotificationSync() {
        boolean canReceiveOnlineOrder = "STAFF".equalsIgnoreCase(userRole) || "MANAGER".equalsIgnoreCase(userRole);
        if (!canReceiveOnlineOrder) return;

        FirebaseHelper.getOnlineOrdersRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                OnlineOrderEntity firstNewPendingOrder = null;

                for (DataSnapshot ds : snapshot.getChildren()) {
                    String key = ds.getKey();
                    if (key == null) continue;

                    OnlineOrderEntity order = ds.getValue(OnlineOrderEntity.class);
                    if (order == null) continue;
                    order.firebaseKey = key;

                    try {
                        OnlineOrderEntity existing = onlineOrderDao.getOrderByFirebaseKey(key);
                        if (existing == null) {
                            onlineOrderDao.insert(order);
                        } else {
                            order.id = existing.id;
                            onlineOrderDao.update(order);
                        }
                    } catch (Exception e) {
                        Log.e("OnlineOrderNotif", "Sync local online_orders failed", e);
                    }

                    if (!knownOnlineOrderKeys.contains(key)) {
                        knownOnlineOrderKeys.add(key);
                        if (!onlineOrderFirstLoad && "PENDING".equalsIgnoreCase(order.status) && firstNewPendingOrder == null) {
                            firstNewPendingOrder = order;
                        }
                    }
                }

                if (onlineOrderFirstLoad) {
                    onlineOrderFirstLoad = false;
                    return;
                }

                if (firstNewPendingOrder != null) {
                    OnlineOrderEntity notifyOrder = firstNewPendingOrder;
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        playNotificationSound();

                        String message;
                        if ("CALL_WAITER".equalsIgnoreCase(notifyOrder.type)) {
                            message = "Thông báo NV: " + (notifyOrder.tableName == null ? "không rõ bàn" : notifyOrder.tableName) + " đang gọi nhân viên";
                        } else {
                            message = "Đơn mới từ " + (notifyOrder.tableName == null ? "không rõ bàn" : notifyOrder.tableName);
                        }

                        new AlertDialog.Builder(TableListActivity.this)
                                .setTitle("Đơn online mới")
                                .setMessage(message)
                                .setPositiveButton("Xem đơn", (dialog, which) -> {
                                    startActivity(new Intent(TableListActivity.this, OnlineOrderActivity.class));
                                    dialog.dismiss();
                                })
                                .setNegativeButton("Đóng", null)
                                .show();
                    });
                }
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {
                Log.e("OnlineOrderNotif", "Firebase error: " + error.getMessage());
            }
        });
    }

    private void setupFirebaseSync() {
        // Đồng bộ Bàn
        FirebaseHelper.getTablesRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<TableEntity> fbTables = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        try {
                            TableEntity table = ds.getValue(TableEntity.class);
                            if (table != null && table.name != null && table.zone != null) {
                                TableEntity local = tableDao.getTableByNameInZone(table.name, table.zone);
                                if (local == null) tableDao.insertTable(table);
                                else { table.id = local.id; tableDao.updateTable(table); }
                                fbTables.add(table);
                            }
                        } catch (Exception ignored) {}
                    }
                    sortTables(fbTables);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        allTables.clear();
                        allTables.addAll(fbTables);
                        applyFilters();
                    });
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });

        // Đồng bộ Khu vực
        FirebaseHelper.getZonesRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<ZoneEntity> fbZones = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        try {
                            ZoneEntity zone = ds.getValue(ZoneEntity.class);
                            if (zone != null && zone.name != null) {
                                ZoneEntity local = zoneDao.getZoneByName(zone.name);
                                if (local == null) zoneDao.insertZone(zone);
                                else { zone.id = local.id; zoneDao.updateZone(zone); }
                                fbZones.add(zone);
                            }
                        } catch (Exception ignored) {}
                    }
                    sortZones(fbZones);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        allZones = fbZones;
                        updateZoneChips();
                        applyFilters();
                    });
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });
    }

    private void applyPermissions() {
        boolean isManager = "MANAGER".equals(userRole);
        btnAddTable.setVisibility(isManager ? View.VISIBLE : View.GONE);
        btnOpenMenuManage.setVisibility(isManager ? View.VISIBLE : View.GONE);
        if (navigationView != null) {
            navigationView.getMenu().setGroupVisible(R.id.group_manager, isManager);
        }
    }

    private void seedDefaultMenuData() {
        // Logic seed data...
    }

    private void seedDefaultZonesAndTables() {
        // Logic seed data...
    }

    /** Đảm bảo bàn "Mang về" luôn tồn tại trong zone "Mang về" */
    private void ensureTakeawayTable() {
        final String ZONE_NAME  = "Mang về";
        final String TABLE_NAME = "Mang về";

        // Tạo zone nếu chưa có
        if (zoneDao.countZoneByName(ZONE_NAME) == 0) {
            zoneDao.insertZone(new ZoneEntity(ZONE_NAME));
            FirebaseHelper.getZonesRef().child(ZONE_NAME).setValue(new ZoneEntity(ZONE_NAME));
            Log.d("TakeawayTable", "Created zone: " + ZONE_NAME);
        }

        // Tạo bàn nếu chưa có
        if (tableDao.countTableByNameInZone(TABLE_NAME, ZONE_NAME) == 0) {
            TableEntity takeaway = new TableEntity(TABLE_NAME, ZONE_NAME, false);
            tableDao.insertTable(takeaway);
            FirebaseHelper.getTablesRef()
                    .child(ZONE_NAME + "_" + TABLE_NAME)
                    .setValue(takeaway);
            Log.d("TakeawayTable", "Created table: " + TABLE_NAME);

            runOnUiThread(() -> refreshDataFromDb());
        }
    }

    private void initViews() {
        tabLayoutStatus = findViewById(R.id.tabLayout_status);
        chipGroupZones = findViewById(R.id.chipGroup_zones);
        rvTables = findViewById(R.id.rv_tables);
        btnAddTable = findViewById(R.id.fab_add_table);
        btnOpenMenuManage = findViewById(R.id.btn_open_menu_manage);
        btnMenuSettings = findViewById(R.id.btn_menu_settings);
        drawerLayout = findViewById(R.id.drawer_layout);
        navigationView = findViewById(R.id.nav_view);
    }

    private void setupTabs() {
        if (tabLayoutStatus.getTabCount() == 0) {
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("📑 " + getString(R.string.status_all)));
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("🔥 " + getString(R.string.status_in_use)));
            tabLayoutStatus.addTab(tabLayoutStatus.newTab().setText("✨ " + getString(R.string.status_empty)));
        }
    }

    private void setupRecyclerView() {
        adapter = new TableAdapter(displayedTables, new TableAdapter.OnTableInteractionListener() {
            @Override public void onTableClick(TableEntity table) { handleTableClick(table); }
            @Override public void onTableLongClick(TableEntity table) { /* handled by popup */ }
            @Override public void onQRCodeClick(TableEntity table) {
                Intent intent = new Intent(TableListActivity.this, QRCodeActivity.class);
                intent.putExtra("TABLE_NAME", table.name);
                intent.putExtra("TABLE_ZONE", table.zone);
                startActivity(intent);
            }
            @Override public void onPrintQRClick(TableEntity table) {
                SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
                String printerIp = prefs.getString("BILL_PRINTER_IP", "");
                if (printerIp.isEmpty()) {
                    Toast.makeText(TableListActivity.this, "Chưa cài đặt IP máy in! Vào Cấu hình hệ thống để cài.", Toast.LENGTH_LONG).show();
                    return;
                }
                String qrUrl = "https://ungdungdidong-94edd.web.app/?table=" +
                        android.net.Uri.encode(table.name) + "&zone=" + android.net.Uri.encode(table.zone);
                EscPosPrinter.TableQRData tableQRData = new EscPosPrinter.TableQRData(table.name, table.zone, qrUrl);
                EscPosPrinter.printTableQRDirect(printerIp, tableQRData);
                Toast.makeText(TableListActivity.this, "Đang in QR bàn " + table.name + "...", Toast.LENGTH_SHORT).show();
            }
            @Override public void onDeleteClick(TableEntity table) {
                if ("MANAGER".equals(userRole)) showDeleteConfirmDialog(table);
                else Toast.makeText(TableListActivity.this, "Không có quyền xóa bàn!", Toast.LENGTH_SHORT).show();
            }
        });
        rvTables.setLayoutManager(new GridLayoutManager(this, 2));
        rvTables.setAdapter(adapter);
    }

    private void handleEvents() {
        tabLayoutStatus.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override public void onTabSelected(TabLayout.Tab t) { currentTabFilter = t.getPosition(); applyFilters(); }
            @Override public void onTabUnselected(TabLayout.Tab t) {}
            @Override public void onTabReselected(TabLayout.Tab t) {}
        });

        btnAddTable.setOnClickListener(v -> showAddTableDialog());
        btnOpenMenuManage.setOnClickListener(v -> {
            Intent intent = new Intent(this, MenuManagementActivity.class);
            intent.putExtra("USER_ROLE", userRole);
            startActivity(intent);
        });
        btnMenuSettings.setOnClickListener(v -> {
            if (drawerLayout != null) drawerLayout.openDrawer(GravityCompat.START);
        });
    }

    private void performLogout() {
        SharedPreferences.Editor editor = getSharedPreferences("TramAppPrefs", MODE_PRIVATE).edit();
        editor.clear(); editor.apply();
        startActivity(new Intent(this, LoginActivity.class));
        finish();
    }

    @Override protected void onResume() { super.onResume(); refreshDataFromDb(); }

    private void refreshDataFromDb() {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                List<ZoneEntity> zonesFromDb = zoneDao.getAllZones();
                sortZones(zonesFromDb);
                List<TableEntity> tablesFromDb = tableDao.getAllTables();
                sortTables(tablesFromDb);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    allZones = zonesFromDb;
                    updateZoneChips();
                    allTables.clear();
                    allTables.addAll(tablesFromDb);
                    applyFilters();
                });
            } catch (Exception ignored) {}
        });
    }

    private void sortZones(List<ZoneEntity> list) {
        list.sort((z1, z2) -> {
            boolean isZ1Takeaway = "Mang về".equalsIgnoreCase(z1.name);
            boolean isZ2Takeaway = "Mang về".equalsIgnoreCase(z2.name);
            if (isZ1Takeaway && !isZ2Takeaway) return -1;
            if (!isZ1Takeaway && isZ2Takeaway) return 1;
            return compareNatural(z1.name, z2.name);
        });
    }

    private void sortTables(List<TableEntity> list) {
        list.sort((t1, t2) -> {
            boolean isT1Takeaway = "Mang về".equalsIgnoreCase(t1.name);
            boolean isT2Takeaway = "Mang về".equalsIgnoreCase(t2.name);
            if (isT1Takeaway && !isT2Takeaway) return -1;
            if (!isT1Takeaway && isT2Takeaway) return 1;
            return compareNatural(t1.name, t2.name);
        });
    }

    private int compareNatural(String s1, String s2) {
        if (s1 == null || s2 == null) return 0;
        Pattern p = Pattern.compile("(\\d+)|(\\D+)");
        Matcher m1 = p.matcher(s1); Matcher m2 = p.matcher(s2);
        while (m1.find() && m2.find()) {
            String g1 = m1.group(); String g2 = m2.group();
            if (Character.isDigit(g1.charAt(0)) && Character.isDigit(g2.charAt(0))) {
                int i1 = Integer.parseInt(g1); int i2 = Integer.parseInt(g2);
                if (i1 != i2) return i1 - i2;
            } else {
                int res = g1.compareToIgnoreCase(g2); if (res != 0) return res;
            }
        }
        return s1.length() - s2.length();
    }

    private void updateZoneChips() {
        chipGroupZones.removeAllViews();
        Chip allChip = new Chip(this);
        allChip.setText(R.string.all_zones);
        allChip.setCheckable(true);
        allChip.setChecked(currentZoneFilter.isEmpty());
        allChip.setOnClickListener(v -> { currentZoneFilter = ""; applyFilters(); });
        chipGroupZones.addView(allChip);

        for (ZoneEntity zone : allZones) {
            Chip chip = new Chip(this);
            chip.setText(zone.name);
            chip.setCheckable(true);
            chip.setChecked(currentZoneFilter.equals(zone.name));
            chip.setOnClickListener(v -> { currentZoneFilter = zone.name; applyFilters(); });
            chipGroupZones.addView(chip);
        }
    }

    private void handleTableClick(TableEntity table) {
        Intent intent = new Intent(this, table.inUse ? OrderActivity.class : OrderListActivity.class);
        intent.putExtra("TABLE_DATA", table);
        intent.putExtra("USER_ROLE", userRole);
        startActivity(intent);
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

    private void showAddTableDialog() {
        if (!"MANAGER".equals(userRole)) return;
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_add_table);
        if (dialog.getWindow() != null) dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);

        EditText edtName = dialog.findViewById(R.id.edt_table_name);
        Spinner spinnerZone = dialog.findViewById(R.id.spinner_zone);
        Button btnSave = dialog.findViewById(R.id.btn_save_table);

        List<String> zoneNames = new ArrayList<>();
        for (ZoneEntity z : allZones) zoneNames.add(z.name);
        spinnerZone.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, zoneNames));

        btnSave.setOnClickListener(v -> {
            String name = edtName.getText().toString().trim();
            if (name.isEmpty() || spinnerZone.getSelectedItem() == null) return;
            String zone = spinnerZone.getSelectedItem().toString();

            for (TableEntity t : allTables) {
                if (t.name.equalsIgnoreCase(name) && t.zone.equals(zone)) {
                    Toast.makeText(this, R.string.error_table_exists, Toast.LENGTH_SHORT).show();
                    return;
                }
            }

            AppExecutors.getInstance().getDiskIO().execute(() -> {
                TableEntity table = new TableEntity(name, zone, false);
                tableDao.insertTable(table);
                FirebaseHelper.getTablesRef().child(zone + "_" + name).setValue(table);
                refreshDataFromDb();
            });
            dialog.dismiss();
        });
        dialog.show();
    }

    private void showDeleteConfirmDialog(TableEntity table) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.delete_table_title)
                .setMessage(getString(R.string.delete_table_msg, table.name))
                .setPositiveButton(R.string.delete, (d, w) -> AppExecutors.getInstance().getDiskIO().execute(() -> {
                    tableDao.deleteTable(table);
                    FirebaseHelper.getTablesRef().child(table.zone + "_" + table.name).removeValue();
                    refreshDataFromDb();
                }))
                .setNegativeButton(R.string.cancel, null).show();
    }
}
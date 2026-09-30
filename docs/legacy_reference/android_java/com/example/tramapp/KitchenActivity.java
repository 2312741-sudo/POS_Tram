package com.example.tramapp;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.navigation.NavigationView;
import com.google.firebase.database.ChildEventListener;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;
import java.util.ArrayList;
import java.util.List;

public class KitchenActivity extends AppCompatActivity {

    private RecyclerView rvKitchenOrders;
    private KitchenOrderAdapter adapter;
    private final List<KitchenOrderEntity> orderList = new ArrayList<>();
    private KitchenOrderDao kitchenOrderDao;
    
    private DrawerLayout drawerLayout;
    private NavigationView navigationView;
    private ImageButton btnMenu, btnSettings;
    private String userRole = "KITCHEN";
    private String fullName = "";
    private boolean isFirstLoad = true;
    private String printerIp = "192.168.1.100"; // IP mặc định

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_kitchen);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "KITCHEN");
        fullName = prefs.getString("FULL_NAME", "Đầu bếp");
        printerIp = prefs.getString("PRINTER_IP", "192.168.1.100");

        rvKitchenOrders = findViewById(R.id.rv_kitchen_orders);
        kitchenOrderDao = AppDatabase.getInstance(this).kitchenOrderDao();

        initViews();
        setupNavigationDrawer();
        
        adapter = new KitchenOrderAdapter(orderList, new KitchenOrderAdapter.OnOrderActionListener() {
            @Override
            public void onDone(KitchenOrderEntity order) {
                if (order.firebaseKey != null) {
                    Log.d("KitchenOrder", "Marking order done for: " + order.tableName + ", FirebaseKey: " + order.firebaseKey);
                    FirebaseHelper.getKitchenOrdersRef().child(order.firebaseKey).child("isDone").setValue(true)
                            .addOnSuccessListener(aVoid -> {
                                order.isDone = true;
                                AppExecutors.getInstance().getDiskIO().execute(() -> kitchenOrderDao.updateKitchenOrder(order));
                                Log.d("KitchenOrder", "Order marked done successfully: " + order.tableName);
                                Toast.makeText(KitchenActivity.this, "Đã xong món cho: " + order.tableName, Toast.LENGTH_SHORT).show();
                            })
                            .addOnFailureListener(e -> {
                                Log.e("KitchenOrder", "Error marking order done: " + e.getMessage(), e);
                                Toast.makeText(KitchenActivity.this, "Lỗi khi đánh dấu xong: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                            });
                } else {
                    Log.w("KitchenOrder", "Cannot mark done: FirebaseKey is null for order: " + order.tableName);
                    Toast.makeText(KitchenActivity.this, "Lỗi: Không tìm thấy khóa Firebase", Toast.LENGTH_SHORT).show();
                }
            }

            @Override
            public void onPrint(KitchenOrderEntity order) {
                // In trực tiếp không hỏi
                Log.d("KitchenOrder", "Printing order for: " + order.tableName);
                EscPosPrinter.printKitchenOrderDirect(printerIp, order);
                Toast.makeText(KitchenActivity.this, "Đang gửi lệnh in tới " + printerIp, Toast.LENGTH_SHORT).show();
            }
        });

        rvKitchenOrders.setLayoutManager(new LinearLayoutManager(this));
        rvKitchenOrders.setAdapter(adapter);

        setupFirebaseKitchenSync();
    }

    private void initViews() {
        drawerLayout = findViewById(R.id.drawer_layout_kitchen);
        navigationView = findViewById(R.id.nav_view_kitchen);
        btnMenu = findViewById(R.id.btn_menu_kitchen);
        
        // Thêm nút cài đặt IP (Tận dụng một nút có sẵn hoặc bạn có thể thêm vào layout)
        btnSettings = findViewById(R.id.btn_settings_kitchen); // Giả định có nút này trong layout
        if (btnSettings != null) {
            btnSettings.setOnClickListener(v -> showIpSettingsDialog());
        }

        btnMenu.setOnClickListener(v -> {
            if (drawerLayout != null) {
                drawerLayout.openDrawer(GravityCompat.START);
            }
        });
    }

    private void showIpSettingsDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("Cấu hình IP Máy in Bếp");
        final EditText input = new EditText(this);
        input.setText(printerIp);
        input.setHint("Ví dụ: 192.168.1.100");
        builder.setView(input);

        builder.setPositiveButton("Lưu", (dialog, which) -> {
            printerIp = input.getText().toString();
            getSharedPreferences("TramAppPrefs", MODE_PRIVATE).edit().putString("PRINTER_IP", printerIp).apply();
            Toast.makeText(this, "Đã lưu IP: " + printerIp, Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("Hủy", null);
        builder.show();
    }

    private void setupFirebaseKitchenSync() {
        FirebaseHelper.getKitchenOrdersRef().addChildEventListener(new ChildEventListener() {
            @Override
            public void onChildAdded(@NonNull DataSnapshot snapshot, @Nullable String previousChildName) {
                try {
                    KitchenOrderEntity order = snapshot.getValue(KitchenOrderEntity.class);
                    if (order != null && !order.isDone) {
                        order.firebaseKey = snapshot.getKey();
                        runOnUiThread(() -> {
                            orderList.add(0, order);
                            adapter.notifyItemInserted(0);
                            rvKitchenOrders.scrollToPosition(0);
                            
                            if (!isFirstLoad) {
                                playOrderSound();
                                // TỰ ĐỘNG IN TRỰC TIẾP QUA MẠNG KHÔNG HỎI
                                EscPosPrinter.printKitchenOrderDirect(printerIp, order);
                            }
                        });
                    }
                } catch (Exception e) { e.printStackTrace(); }
            }
            @Override public void onChildChanged(@NonNull DataSnapshot snapshot, @Nullable String previousChildName) {
                try {
                    KitchenOrderEntity updated = snapshot.getValue(KitchenOrderEntity.class);
                    if (updated != null && updated.isDone) {
                        runOnUiThread(() -> {
                            for (int i = 0; i < orderList.size(); i++) {
                                if (snapshot.getKey().equals(orderList.get(i).firebaseKey)) {
                                    orderList.remove(i);
                                    adapter.notifyItemRemoved(i);
                                    break;
                                }
                            }
                        });
                    }
                } catch (Exception e) { e.printStackTrace(); }
            }
            @Override public void onChildRemoved(@NonNull DataSnapshot snapshot) {}
            @Override public void onChildMoved(@NonNull DataSnapshot snapshot, @Nullable String previousChildName) {}
            @Override public void onCancelled(@NonNull DatabaseError error) {}
        });

        FirebaseHelper.getKitchenOrdersRef().addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) { isFirstLoad = false; }
            @Override public void onCancelled(@NonNull DatabaseError error) { isFirstLoad = false; }
        });
    }

    private void setupNavigationDrawer() {
        if (navigationView == null) return;
        navigationView.getMenu().setGroupVisible(R.id.group_manager, false);
        View headerView = navigationView.getHeaderView(0);
        if (headerView != null) {
            TextView tvUserName = headerView.findViewById(R.id.tv_user_name);
            if (tvUserName != null) tvUserName.setText(fullName);
        }
        navigationView.setNavigationItemSelectedListener(item -> {
            if (item.getItemId() == R.id.nav_logout) performLogout();
            drawerLayout.closeDrawer(GravityCompat.START);
            return true;
        });
    }

    private void performLogout() {
        getSharedPreferences("TramAppPrefs", MODE_PRIVATE).edit().clear().apply();
        startActivity(new Intent(this, LoginActivity.class));
        finish();
    }

    private void playOrderSound() {
        try {
            Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            Ringtone r = RingtoneManager.getRingtone(getApplicationContext(), notification);
            r.play();
        } catch (Exception e) {}
    }
}
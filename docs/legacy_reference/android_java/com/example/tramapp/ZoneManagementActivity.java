package com.example.tramapp;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;
import java.util.ArrayList;
import java.util.List;

public class ZoneManagementActivity extends AppCompatActivity {

    private RecyclerView rvZones;
    private ZoneDao zoneDao;
    private final List<ZoneEntity> zoneList = new ArrayList<>();
    private ZoneAdapter adapter;
    private String userRole = "STAFF";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_zone_management);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "STAFF");

        Toolbar toolbar = findViewById(R.id.toolbar_zone);
        if (toolbar != null) {
            setSupportActionBar(toolbar);
            if (getSupportActionBar() != null) {
                getSupportActionBar().setDisplayHomeAsUpEnabled(true);
                toolbar.setNavigationOnClickListener(v -> finish());
            }
        }

        rvZones = findViewById(R.id.rv_manage_zones);
        FloatingActionButton fabAdd = findViewById(R.id.fab_add_zone);
        zoneDao = AppDatabase.getInstance(this).zoneDao();

        if (!"MANAGER".equalsIgnoreCase(userRole)) {
            if (fabAdd != null) fabAdd.setVisibility(View.GONE);
        }

        setupRecyclerView();
        setupFirebaseSync();

        if (fabAdd != null) {
            fabAdd.setOnClickListener(v -> showAddZoneDialog());
        }
    }

    private void setupRecyclerView() {
        adapter = new ZoneAdapter();
        if (rvZones != null) {
            rvZones.setLayoutManager(new LinearLayoutManager(this));
            rvZones.setAdapter(adapter);
        }
    }

    private void setupFirebaseSync() {
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
                                if (local == null) {
                                    zoneDao.insertZone(zone);
                                } else {
                                    zone.id = local.id;
                                    zoneDao.updateZone(zone);
                                }
                                fbZones.add(zone);
                            }
                        } catch (Exception ignored) {}
                    }
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        zoneList.clear();
                        zoneList.addAll(fbZones);
                        adapter.notifyDataSetChanged();
                    });
                });
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {}
        });
    }

    private void showAddZoneDialog() {
        if (isFinishing() || isDestroyed()) return;
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_add_zone);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }

        EditText edtName = dialog.findViewById(R.id.edt_zone_name);
        Button btnSave = dialog.findViewById(R.id.btn_save_zone);

        if (btnSave != null) {
            btnSave.setOnClickListener(v -> {
                if (edtName == null) return;
                String name = edtName.getText().toString().trim();
                if (name.isEmpty()) {
                    Toast.makeText(getApplicationContext(), "Vui lòng nhập tên khu vực!", Toast.LENGTH_SHORT).show();
                    return;
                }

                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    try {
                        if (zoneDao.countZoneByName(name) > 0) {
                            runOnUiThread(() -> Toast.makeText(getApplicationContext(), "Tên khu vực đã tồn tại!", Toast.LENGTH_LONG).show());
                            return;
                        }

                        ZoneEntity newZone = new ZoneEntity(name);
                        zoneDao.insertZone(newZone);
                        // Lưu lên Firebase
                        FirebaseHelper.getZonesRef().child(name).setValue(newZone);

                        runOnUiThread(() -> {
                            dialog.dismiss();
                            Toast.makeText(getApplicationContext(), "Đã thêm khu vực " + name, Toast.LENGTH_SHORT).show();
                        });
                    } catch (Exception ignored) {}
                });
            });
        }
        dialog.show();
    }

    private class ZoneAdapter extends RecyclerView.Adapter<ZoneAdapter.VH> {
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup p, int t) {
            View v = LayoutInflater.from(p.getContext()).inflate(R.layout.item_zone, p, false);
            return new VH(v);
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            ZoneEntity z = zoneList.get(pos);
            h.tvName.setText(z.name);
            
            if ("MANAGER".equalsIgnoreCase(userRole)) {
                h.btnDelete.setVisibility(View.VISIBLE);
                h.btnDelete.setOnClickListener(v -> {
                    new AlertDialog.Builder(ZoneManagementActivity.this)
                            .setTitle("Xóa khu vực")
                            .setMessage("Xóa khu vực '" + z.name + "'? Các bàn thuộc khu vực này sẽ bị ảnh hưởng.")
                            .setPositiveButton("Xóa", (d, w) -> AppExecutors.getInstance().getDiskIO().execute(() -> {
                                try {
                                    zoneDao.deleteZone(z);
                                    FirebaseHelper.getZonesRef().child(z.name).removeValue();
                                } catch (Exception ignored) {}
                            }))
                            .setNegativeButton("Hủy", null)
                            .show();
                });
            } else {
                h.btnDelete.setVisibility(View.GONE);
            }
        }
        @Override public int getItemCount() { return zoneList.size(); }
        class VH extends RecyclerView.ViewHolder {
            TextView tvName;
            ImageButton btnDelete;
            VH(View v) { 
                super(v); 
                tvName = v.findViewById(R.id.tv_zone_name); 
                btnDelete = v.findViewById(R.id.btn_delete_zone);
            }
        }
    }
}

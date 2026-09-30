package com.example.tramapp;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
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

public class UserManagementActivity extends AppCompatActivity {

    private RecyclerView rvUsers;
    private UserDao userDao;
    private List<UserEntity> userList = new ArrayList<>();
    private UserAdapter adapter;
    private String currentUserRole = "STAFF";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_user_management);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        currentUserRole = prefs.getString("USER_ROLE", "STAFF");

        Toolbar toolbar = findViewById(R.id.toolbar_users);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            toolbar.setNavigationOnClickListener(v -> finish());
        }

        rvUsers = findViewById(R.id.rv_users);
        FloatingActionButton fabAdd = findViewById(R.id.fab_add_user);
        userDao = AppDatabase.getInstance(this).userDao();

        // Chỉ MANAGER mới có quyền thêm nhân viên
        if (!"MANAGER".equals(currentUserRole)) {
            fabAdd.setVisibility(View.GONE);
        }

        adapter = new UserAdapter();
        rvUsers.setLayoutManager(new LinearLayoutManager(this));
        rvUsers.setAdapter(adapter);

        setupFirebaseUserSync();

        fabAdd.setOnClickListener(v -> showUserDialog(null));
    }

    private void setupFirebaseUserSync() {
        FirebaseHelper.getUsersRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                List<UserEntity> fbUsers = new ArrayList<>();
                for (DataSnapshot ds : snapshot.getChildren()) {
                    try {
                        UserEntity u = ds.getValue(UserEntity.class);
                        if (u != null) fbUsers.add(u);
                    } catch (Exception e) { e.printStackTrace(); }
                }
                
                runOnUiThread(() -> {
                    if (isFinishing()) return;
                    userList.clear();
                    userList.addAll(fbUsers);
                    adapter.notifyDataSetChanged();
                });
                
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    try {
                        for (UserEntity u : fbUsers) {
                            userDao.insertUser(u);
                        }
                    } catch (Exception ignored) {}
                });
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {}
        });
    }

    private void showUserDialog(UserEntity userToEdit) {
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_user);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }

        TextView txtTitle = dialog.findViewById(R.id.txt_dialog_title);
        EditText edtFullName = dialog.findViewById(R.id.edt_full_name);
        EditText edtUsername = dialog.findViewById(R.id.edt_username);
        EditText edtPassword = dialog.findViewById(R.id.edt_password);
        Spinner spinnerRole = dialog.findViewById(R.id.spinner_role);
        Button btnSave = dialog.findViewById(R.id.btn_save_user);
        Button btnCancel = dialog.findViewById(R.id.btn_cancel);

        String[] roles = {"STAFF", "MANAGER", "KITCHEN"};
        ArrayAdapter<String> roleAdapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, roles);
        spinnerRole.setAdapter(roleAdapter);

        if (userToEdit != null) {
            txtTitle.setText("Sửa thông tin nhân viên");
            edtFullName.setText(userToEdit.fullName);
            edtUsername.setText(userToEdit.username);
            edtUsername.setEnabled(false); 
            edtPassword.setText(userToEdit.password);
            for (int i = 0; i < roles.length; i++) {
                if (roles[i].equals(userToEdit.role)) {
                    spinnerRole.setSelection(i);
                    break;
                }
            }
        }

        btnCancel.setOnClickListener(v -> dialog.dismiss());

        btnSave.setOnClickListener(v -> {
            String fullName = edtFullName.getText().toString().trim();
            String username = edtUsername.getText().toString().trim();
            String password = edtPassword.getText().toString().trim();
            String role = spinnerRole.getSelectedItem().toString();

            if (fullName.isEmpty() || username.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Vui lòng nhập đầy đủ thông tin", Toast.LENGTH_SHORT).show();
                return;
            }

            UserEntity user = userToEdit != null ? userToEdit : new UserEntity();
            user.fullName = fullName;
            user.username = username;
            user.password = password;
            user.role = role;

            AppExecutors.getInstance().getDiskIO().execute(() -> {
                try {
                    userDao.insertUser(user);
                    FirebaseHelper.getUsersRef().child(user.username).setValue(user);
                    runOnUiThread(() -> {
                        if (isFinishing()) return;
                        dialog.dismiss();
                        Toast.makeText(this, "Đã lưu thông tin!", Toast.LENGTH_SHORT).show();
                    });
                } catch (Exception ignored) {}
            });
        });
        dialog.show();
    }

    private void showDeleteConfirm(UserEntity user) {
        if (user.username.equals("admin") || user.username.equals("ql")) {
            Toast.makeText(this, "Không thể xóa tài khoản hệ thống", Toast.LENGTH_SHORT).show();
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("Xóa tài khoản")
                .setMessage("Bạn có chắc muốn xóa nhân viên '" + user.fullName + "'?")
                .setPositiveButton("Xóa", (d, w) -> {
                    AppExecutors.getInstance().getDiskIO().execute(() -> {
                        try {
                            userDao.deleteUser(user);
                            FirebaseHelper.getUsersRef().child(user.username).removeValue();
                        } catch (Exception ignored) {}
                    });
                    Toast.makeText(this, "Đã xóa", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Hủy", null)
                .show();
    }

    private class UserAdapter extends RecyclerView.Adapter<UserAdapter.VH> {
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup p, int t) {
            View v = LayoutInflater.from(p.getContext()).inflate(R.layout.item_user, p, false);
            return new VH(v);
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            UserEntity user = userList.get(pos);
            h.txtName.setText(user.fullName);
            h.txtUser.setText("Tên đăng nhập: " + user.username);
            h.txtRole.setText("Chức vụ: " + user.role + " | MK: " + user.password);
            
            // Chỉ MANAGER mới thấy nút sửa/xóa
            if ("MANAGER".equals(currentUserRole)) {
                h.btnEdit.setVisibility(View.VISIBLE);
                h.btnDelete.setVisibility(View.VISIBLE);
                h.btnEdit.setOnClickListener(v -> showUserDialog(user));
                h.btnDelete.setOnClickListener(v -> showDeleteConfirm(user));
            } else {
                h.btnEdit.setVisibility(View.GONE);
                h.btnDelete.setVisibility(View.GONE);
            }
        }
        @Override public int getItemCount() { return userList.size(); }
        class VH extends RecyclerView.ViewHolder {
            TextView txtName, txtUser, txtRole;
            ImageButton btnEdit, btnDelete;
            VH(View v) { 
                super(v); 
                txtName = v.findViewById(R.id.txt_full_name);
                txtUser = v.findViewById(R.id.txt_username);
                txtRole = v.findViewById(R.id.txt_role);
                btnEdit = v.findViewById(R.id.btn_edit_user);
                btnDelete = v.findViewById(R.id.btn_delete_user);
            }
        }
    }
}

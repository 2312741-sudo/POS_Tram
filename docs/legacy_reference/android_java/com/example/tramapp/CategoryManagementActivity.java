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

public class CategoryManagementActivity extends AppCompatActivity {

    private RecyclerView rvCategories;
    private FloatingActionButton fabAdd;
    private CategoryDao categoryDao;
    private final List<CategoryEntity> categoryList = new ArrayList<>();
    private CategoryAdapter adapter;
    private String userRole = "STAFF";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_category_management);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "STAFF");

        Toolbar toolbar = findViewById(R.id.toolbar_category);
        if (toolbar != null) {
            setSupportActionBar(toolbar);
            if (getSupportActionBar() != null) {
                getSupportActionBar().setTitle("Quản lý Menu - Danh mục");
                getSupportActionBar().setDisplayHomeAsUpEnabled(true);
                toolbar.setNavigationOnClickListener(v -> finish());
            }
        }

        rvCategories = findViewById(R.id.rv_manage_categories);
        fabAdd = findViewById(R.id.fab_add_category);
        categoryDao = AppDatabase.getInstance(this).categoryDao();

        if (!"MANAGER".equals(userRole)) {
            fabAdd.setVisibility(View.GONE);
        }

        setupRecyclerView();
        setupFirebaseSync();

        fabAdd.setOnClickListener(v -> showAddCategoryDialog());
    }

    private void setupRecyclerView() {
        adapter = new CategoryAdapter();
        rvCategories.setLayoutManager(new LinearLayoutManager(this));
        rvCategories.setAdapter(adapter);
    }

    private void setupFirebaseSync() {
        FirebaseHelper.getCategoriesRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<CategoryEntity> fbCategories = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        try {
                            CategoryEntity cat = ds.getValue(CategoryEntity.class);
                            if (cat != null && cat.name != null) {
                                CategoryEntity local = categoryDao.getCategoryByName(cat.name);
                                if (local == null) {
                                    categoryDao.insertCategory(cat);
                                } else {
                                    cat.id = local.id;
                                    categoryDao.updateCategory(cat);
                                }
                                fbCategories.add(cat);
                            }
                        } catch (Exception ignored) {}
                    }
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        categoryList.clear();
                        categoryList.addAll(fbCategories);
                        adapter.notifyDataSetChanged();
                    });
                });
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {}
        });
    }

    private void showAddCategoryDialog() {
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_add_category);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }

        EditText edtName = dialog.findViewById(R.id.edt_category_name);
        Button btnSave = dialog.findViewById(R.id.btn_save_category);

        btnSave.setOnClickListener(v -> {
            String name = edtName.getText().toString().trim();
            if (name.isEmpty()) {
                Toast.makeText(this, "Vui lòng nhập tên danh mục!", Toast.LENGTH_SHORT).show();
                return;
            }

            AppExecutors.getInstance().getDiskIO().execute(() -> {
                if (categoryDao.countCategoryByName(name) > 0) {
                    runOnUiThread(() -> Toast.makeText(this, "Danh mục này đã tồn tại!", Toast.LENGTH_LONG).show());
                    return;
                }
                CategoryEntity newCat = new CategoryEntity(name);
                categoryDao.insertCategory(newCat);
                // Lưu lên Firebase
                FirebaseHelper.getCategoriesRef().child(name).setValue(newCat);
                
                runOnUiThread(() -> {
                    dialog.dismiss();
                    Toast.makeText(this, "Đã thêm danh mục " + name, Toast.LENGTH_SHORT).show();
                });
            });
        });
        dialog.show();
    }

    private class CategoryAdapter extends RecyclerView.Adapter<CategoryAdapter.VH> {
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup p, int t) {
            View v = LayoutInflater.from(p.getContext()).inflate(R.layout.item_category, p, false);
            return new VH(v);
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            CategoryEntity c = categoryList.get(pos);
            h.tvName.setText(c.name);

            if ("MANAGER".equals(userRole)) {
                h.btnDelete.setVisibility(View.VISIBLE);
                h.btnDelete.setOnClickListener(v -> {
                    new AlertDialog.Builder(CategoryManagementActivity.this)
                            .setTitle("Xóa danh mục")
                            .setMessage("Bạn có chắc chắn muốn xóa danh mục '" + c.name + "'? Các món ăn thuộc danh mục này có thể bị ảnh hưởng.")
                            .setPositiveButton("Xóa", (d, w) -> {
                                AppExecutors.getInstance().getDiskIO().execute(() -> {
                                    categoryDao.deleteCategory(c);
                                    FirebaseHelper.getCategoriesRef().child(c.name).removeValue();
                                });
                            })
                            .setNegativeButton("Hủy", null)
                            .show();
                });
            } else {
                h.btnDelete.setVisibility(View.GONE);
            }
        }
        @Override public int getItemCount() { return categoryList.size(); }
        class VH extends RecyclerView.ViewHolder {
            TextView tvName;
            ImageButton btnDelete;
            VH(View v) { 
                super(v); 
                tvName = v.findViewById(R.id.tv_category_name); 
                btnDelete = v.findViewById(R.id.btn_delete_category);
            }
        }
    }
}
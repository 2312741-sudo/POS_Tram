package com.example.tramapp;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import android.app.AlertDialog;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import androidx.annotation.Nullable;
import com.google.firebase.database.ChildEventListener;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;
import java.util.ArrayList;
import java.util.List;

public class OrderListActivity extends AppCompatActivity {

    private RecyclerView rvProductList;
    private TextView txtCartBadge;
    private ChipGroup chipGroupMenu;
    private ProductListAdapter adapter;
    private final List<Product> allProducts = new ArrayList<>(); // Danh sách gốc
    private final List<Product> displayedProducts = new ArrayList<>(); // Danh sách hiển thị sau khi lọc
    private TableEntity currentTable;
    private ProductDao productDao;
    private CategoryDao categoryDao;
    private ImageView btnQuickAdd, btnBack;
    private String currentSelectedCategory = "";
    private boolean kitchenNotifFirstLoad = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_order_list);

        productDao = AppDatabase.getInstance(this).productDao();
        categoryDao = AppDatabase.getInstance(this).categoryDao();
        currentTable = (TableEntity) getIntent().getSerializableExtra("TABLE_DATA");
        currentSelectedCategory = getString(R.string.category_all);

        initViews();
        setupRecyclerView();
        handleEvents();
        setupFirebaseSync();
        setupKitchenNotificationSync();
    }

    private void initViews() {
        rvProductList = findViewById(R.id.rv_product_list);
        txtCartBadge = findViewById(R.id.txt_cart_badge);
        TextView txtTableTitle = findViewById(R.id.txt_table_title);
        btnQuickAdd = findViewById(R.id.btn_quick_add_product);
        btnBack = findViewById(R.id.btn_back);
        chipGroupMenu = findViewById(R.id.chipGroup_menu);
        
        if (currentTable != null) {
            txtTableTitle.setText(getString(R.string.table_title_format, currentTable.name));
        }
        txtCartBadge.setVisibility(View.GONE);
    }

    private void setupFirebaseSync() {
        // 1. Đồng bộ Danh mục (Categories)
        FirebaseHelper.getCategoriesRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<CategoryEntity> fbCats = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        CategoryEntity cat = ds.getValue(CategoryEntity.class);
                        if (cat != null && cat.name != null) {
                            CategoryEntity local = categoryDao.getCategoryByName(cat.name);
                            if (local == null) categoryDao.insertCategory(cat);
                            fbCats.add(cat);
                        }
                    }
                    runOnUiThread(() -> updateCategoryChips(fbCats));
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });

        // 2. Đồng bộ Sản phẩm (Products)
        FirebaseHelper.getProductsRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    List<Product> fbProducts = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        ProductEntity entity = ds.getValue(ProductEntity.class);
                        if (entity != null) {
                            // Cập nhật SQLite
                            ProductEntity local = productDao.getProductById(entity.id);
                            if (local == null) productDao.insertProduct(entity);
                            else productDao.updateProduct(entity);
                            
                            fbProducts.add(new Product(
                                String.valueOf(entity.id), 
                                entity.name, 
                                entity.price, 
                                entity.unit, 
                                entity.category, 
                                entity.imageResourceName,
                                entity.imageBase64
                            ));
                        }
                    }
                    runOnUiThread(() -> {
                        allProducts.clear();
                        allProducts.addAll(fbProducts);
                        filterMenuByCategory(currentSelectedCategory);
                    });
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });
    }

    private void updateCategoryChips(List<CategoryEntity> categories) {
        chipGroupMenu.removeAllViews();
        
        // Thêm chip "Tất cả"
        addCategoryChip(getString(R.string.category_all), currentSelectedCategory.equals(getString(R.string.category_all)));

        for (CategoryEntity cat : categories) {
            addCategoryChip(cat.name, currentSelectedCategory.equals(cat.name));
        }
    }

    private void addCategoryChip(String name, boolean isSelected) {
        Chip chip = new Chip(this);
        chip.setText(name);
        chip.setCheckable(true);
        chip.setChecked(isSelected);
        chip.setOnClickListener(v -> {
            currentSelectedCategory = name;
            filterMenuByCategory(name);
        });
        chipGroupMenu.addView(chip);
    }

    private void filterMenuByCategory(String categoryName) {
        displayedProducts.clear();
        if (categoryName.equals(getString(R.string.category_all))) {
            displayedProducts.addAll(allProducts);
        } else {
            for (Product p : allProducts) {
                if (p.getCategory() != null && p.getCategory().equals(categoryName)) {
                    displayedProducts.add(p);
                }
            }
        }
        if (adapter != null) {
            adapter.notifyDataSetChanged();
        }
    }

    private void setupRecyclerView() {
        adapter = new ProductListAdapter(displayedProducts, (product, totalCount) -> {
            int grandTotal = 0;
            for (Product p : allProducts) grandTotal += p.getQuantity();
            
            txtCartBadge.setVisibility(grandTotal > 0 ? View.VISIBLE : View.GONE);
            txtCartBadge.setText(String.valueOf(grandTotal));
        });
        rvProductList.setLayoutManager(new LinearLayoutManager(this));
        rvProductList.setAdapter(adapter);
    }

    private void handleEvents() {
        findViewById(R.id.btn_view_cart).setOnClickListener(v -> {
            ArrayList<Product> selected = new ArrayList<>();
            for (Product p : allProducts) if (p.getQuantity() > 0) selected.add(p);
            if (selected.isEmpty()) {
                Toast.makeText(this, getString(R.string.no_item_selected), Toast.LENGTH_SHORT).show();
                return;
            }

            Intent intent = new Intent(this, OrderActivity.class);
            intent.putExtra("TABLE_DATA", currentTable);
            intent.putExtra("SELECTED_PRODUCTS", selected);
            startActivity(intent);
        });

        btnQuickAdd.setOnClickListener(v -> startActivity(new Intent(this, MenuManagementActivity.class)));
        btnBack.setOnClickListener(v -> finish());
        
        findViewById(R.id.btn_clear_cart).setOnClickListener(v -> {
            for (Product p : allProducts) p.setQuantity(0);
            if (adapter != null) {
                adapter.notifyDataSetChanged();
            }
            txtCartBadge.setVisibility(View.GONE);
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
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            playOnlineOrderSound();
                            new AlertDialog.Builder(OrderListActivity.this)
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
                } catch (Exception e) {}
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
}

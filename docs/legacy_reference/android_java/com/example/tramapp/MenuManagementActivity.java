package com.example.tramapp;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.util.Base64;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.Spinner;
import android.widget.Toast;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

public class MenuManagementActivity extends AppCompatActivity {

    private RecyclerView rvMenu;
    private ChipGroup chipGroupCategories;
    private ProductDao productDao;
    private CategoryDao categoryDao;
    private MenuManageAdapter adapter;
    private final List<ProductEntity> allProducts = new ArrayList<>();
    private final List<ProductEntity> displayedProducts = new ArrayList<>();
    private final List<CategoryEntity> allCategories = new ArrayList<>();
    private String currentCategoryFilter = "Tất cả";
    private String userRole = "STAFF";

    private String selectedImageBase64 = null;
    private ImageView imgPreview;
    private View layoutAddImage;
    private ImageButton btnChangeImage;

    private final ActivityResultLauncher<Intent> pickImageLauncher = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(),
            result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    try {
                        Uri imageUri = result.getData().getData();
                        if (imageUri != null) {
                            processSelectedImage(imageUri);
                        } else if (result.getData().getExtras() != null) {
                            Bitmap photo = (Bitmap) result.getData().getExtras().get("data");
                            if (photo != null) processBitmap(photo);
                        }
                    } catch (Exception e) {
                        Toast.makeText(this, "Lỗi tải ảnh!", Toast.LENGTH_SHORT).show();
                    }
                }
            }
    );

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_menu_management);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "STAFF");

        Toolbar toolbar = findViewById(R.id.toolbar_menu);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            toolbar.setNavigationOnClickListener(v -> finish());
        }

        rvMenu = findViewById(R.id.rv_manage_menu);
        chipGroupCategories = findViewById(R.id.chipGroup_manage_categories);
        FloatingActionButton fabAdd = findViewById(R.id.fab_add_product);
        
        productDao = AppDatabase.getInstance(this).productDao();
        categoryDao = AppDatabase.getInstance(this).categoryDao();

        fabAdd.setVisibility("MANAGER".equals(userRole) ? View.VISIBLE : View.GONE);

        setupRecyclerView();
        setupFirebaseCategorySync(); // Thêm đồng bộ Danh mục từ Firebase
        setupFirebaseProductSync();

        fabAdd.setOnClickListener(v -> showCustomProductDialog(null));
        
        // Long press to show menu options
        fabAdd.setOnLongClickListener(v -> {
            if ("MANAGER".equals(userRole)) {
                showFabOptionsDialog();
                return true;
            }
            return false;
        });
    }

    private void showFabOptionsDialog() {
        CharSequence[] options = {"Khôi phục từ menu mẫu", "Đồng bộ từ Firebase"};
        new AlertDialog.Builder(this)
                .setTitle("Tùy chọn menu")
                .setItems(options, (dialog, which) -> {
                    if (which == 0) {
                        // Seed from template
                        new AlertDialog.Builder(this)
                                .setTitle("Khôi phục menu")
                                .setMessage("Tạo lại danh sách sản phẩm từ menu mẫu?")
                                .setPositiveButton("Có", (d, w) -> {
                                    ProductSeeder.seedProductsToFirebase(this);
                                    Toast.makeText(this, "Đang tạo lại sản phẩm...", Toast.LENGTH_SHORT).show();
                                })
                                .setNegativeButton("Không", null)
                                .show();
                    } else if (which == 1) {
                        // Sync from Firebase
                        new AlertDialog.Builder(this)
                                .setTitle("Đồng bộ từ Firebase")
                                .setMessage("Xóa dữ liệu local và lấy từ Firebase làm gốc?")
                                .setPositiveButton("Có", (d, w) -> {
                                    ProductSeeder.clearAndSyncFromFirebase(this);
                                    Toast.makeText(this, "Đang đồng bộ từ Firebase...", Toast.LENGTH_SHORT).show();
                                })
                                .setNegativeButton("Không", null)
                                .show();
                    }
                })
                .show();
    }

    private void setupFirebaseCategorySync() {
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
                    runOnUiThread(() -> {
                        allCategories.clear();
                        allCategories.addAll(fbCats);
                        updateCategoryChips();
                    });
                });
            }
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });
    }

    private void updateCategoryChips() {
        chipGroupCategories.removeAllViews();
        addCategoryChip("Tất cả");
        for (CategoryEntity cat : allCategories) {
            addCategoryChip(cat.name);
        }
    }

    private void setupFirebaseProductSync() {
        FirebaseHelper.getProductsRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                if (isFinishing()) return;
                try {
                    List<ProductEntity> fbProducts = new ArrayList<>();
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        try {
                            ProductEntity p = ds.getValue(ProductEntity.class);
                            if (p != null && p.id > 0) {
                                // Incremental sync: check if product exists by ID
                                ProductEntity local = productDao.getProductById(p.id);
                                if (local == null) {
                                    // New product - insert
                                    productDao.insertProduct(p);
                                    Log.d("MenuManagement", "Product inserted: " + p.name);
                                } else if (!p.name.equals(local.name) || p.price != local.price || 
                                           !p.category.equals(local.category) || !p.unit.equals(local.unit)) {
                                    // Product changed - update
                                    productDao.updateProduct(p);
                                    Log.d("MenuManagement", "Product updated: " + p.name);
                                }
                                fbProducts.add(p);
                            }
                        } catch (Exception e) {
                            Log.e("MenuManagement", "Error processing product: " + e.getMessage(), e);
                        }
                    }
                    
                    runOnUiThread(() -> {
                        allProducts.clear();
                        allProducts.addAll(fbProducts);
                        filterProducts();
                        Log.d("MenuManagement", "Product sync complete. Total: " + fbProducts.size());
                    });
                } catch (Exception e) {
                    Log.e("MenuManagement", "Error syncing products: " + e.getMessage(), e);
                }
            }
            @Override public void onCancelled(@NonNull DatabaseError error) {
                Log.e("MenuManagement", "Products sync error: " + error.getMessage());
            }
        });
    }

    private void setupRecyclerView() {
        adapter = new MenuManageAdapter(displayedProducts, new MenuManageAdapter.OnProductClickListener() {
            @Override
            public void onProductClick(ProductEntity product) {
                if ("MANAGER".equals(userRole)) showCustomProductDialog(product);
            }
            @Override
            public void onProductLongClick(ProductEntity product) {
                if ("MANAGER".equals(userRole)) showDeleteConfirm(product);
            }
        });
        rvMenu.setLayoutManager(new LinearLayoutManager(this));
        rvMenu.setAdapter(adapter);
    }

    private void addCategoryChip(String name) {
        Chip chip = new Chip(this);
        chip.setText(name);
        chip.setCheckable(true);
        chip.setChecked(name.equals(currentCategoryFilter));
        chip.setOnClickListener(v -> {
            currentCategoryFilter = name;
            filterProducts();
        });
        chipGroupCategories.addView(chip);
    }

    private void filterProducts() {
        displayedProducts.clear();
        if (currentCategoryFilter.equals("Tất cả")) {
            displayedProducts.addAll(allProducts);
        } else {
            for (ProductEntity p : allProducts) {
                if (p.category != null && p.category.equals(currentCategoryFilter)) {
                    displayedProducts.add(p);
                }
            }
        }
        if (adapter != null) adapter.notifyDataSetChanged();
    }

    private void showCustomProductDialog(ProductEntity product) {
        if (allCategories.isEmpty()) {
            Toast.makeText(this, "Vui lòng thêm danh mục trước!", Toast.LENGTH_SHORT).show();
            return;
        }

        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_product);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }

        EditText edtName = dialog.findViewById(R.id.edt_product_name);
        EditText edtPrice = dialog.findViewById(R.id.edt_product_price);
        EditText edtUnit = dialog.findViewById(R.id.edt_product_unit);
        Spinner spinnerCategory = dialog.findViewById(R.id.spinner_product_category);
        Button btnSave = dialog.findViewById(R.id.btn_save_product);
        
        imgPreview = dialog.findViewById(R.id.img_product_preview);
        layoutAddImage = dialog.findViewById(R.id.layout_add_image);
        btnChangeImage = dialog.findViewById(R.id.btn_change_image);

        List<String> categoryNames = new ArrayList<>();
        for (CategoryEntity cat : allCategories) categoryNames.add(cat.name);
        spinnerCategory.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, categoryNames));

        selectedImageBase64 = null;

        if (product != null) {
            edtName.setText(product.name);
            edtPrice.setText(String.valueOf(product.price));
            edtUnit.setText(product.unit);
            selectedImageBase64 = product.imageBase64;
            
            if (selectedImageBase64 != null && !selectedImageBase64.isEmpty()) {
                try {
                    byte[] decodedString = Base64.decode(selectedImageBase64, Base64.DEFAULT);
                    Bitmap decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.length);
                    imgPreview.setImageBitmap(decodedByte);
                    layoutAddImage.setVisibility(View.GONE);
                    btnChangeImage.setVisibility(View.VISIBLE);
                } catch (Exception ignored) {}
            }

            for (int i = 0; i < categoryNames.size(); i++) {
                if (categoryNames.get(i).equals(product.category)) {
                    spinnerCategory.setSelection(i);
                    break;
                }
            }
            btnSave.setText("CẬP NHẬT");
        }

        View.OnClickListener selectImgClick = v -> {
            Intent galleryIntent = new Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI);
            Intent cameraIntent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            Intent chooser = Intent.createChooser(galleryIntent, "Chọn ảnh món ăn");
            chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Intent[] { cameraIntent });
            pickImageLauncher.launch(chooser);
        };

        layoutAddImage.setOnClickListener(selectImgClick);
        imgPreview.setOnClickListener(selectImgClick);
        btnChangeImage.setOnClickListener(selectImgClick);

        btnSave.setOnClickListener(v -> {
            String name = edtName.getText().toString().trim();
            String priceStr = edtPrice.getText().toString().trim();
            String unit = edtUnit.getText().toString().trim();
            String category = spinnerCategory.getSelectedItem().toString();

            if (name.isEmpty() || priceStr.isEmpty()) {
                Toast.makeText(this, "Vui lòng nhập tên và giá!", Toast.LENGTH_SHORT).show();
                return;
            }

            try {
                int price = Integer.parseInt(priceStr);
                String fbKey = name.replaceAll("[.#$\\[\\]]", "_");
                
                ProductEntity newP = (product == null) ? new ProductEntity() : product;
                newP.name = name;
                newP.price = price;
                newP.unit = unit;
                newP.category = category;
                newP.imageBase64 = selectedImageBase64;
                
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    try {
                        // Save locally first
                        if (product != null) {
                            productDao.updateProduct(newP);
                            Log.d("MenuManagement", "Product updated locally: " + name);
                        } else {
                            productDao.insertProduct(newP);
                            Log.d("MenuManagement", "Product inserted locally: " + name);
                        }
                        
                        // Then sync to Firebase with error handling
                        FirebaseHelper.getProductsRef().child(fbKey).setValue(newP, (error, ref) -> {
                            if (error == null) {
                                Log.d("MenuManagement", "Product synced to Firebase: " + name);
                                runOnUiThread(() -> {
                                    dialog.dismiss();
                                    Toast.makeText(this, "Đã lưu món ăn!", Toast.LENGTH_SHORT).show();
                                });
                            } else {
                                Log.e("MenuManagement", "Firebase error: " + error.getMessage());
                                runOnUiThread(() -> 
                                    Toast.makeText(this, "Lỗi đồng bộ Firebase: " + error.getMessage(), Toast.LENGTH_SHORT).show()
                                );
                            }
                        });
                    } catch (Exception e) {
                        Log.e("MenuManagement", "Error saving product: " + e.getMessage(), e);
                        runOnUiThread(() -> 
                            Toast.makeText(this, "Lỗi lưu sản phẩm: " + e.getMessage(), Toast.LENGTH_SHORT).show()
                        );
                    }
                });
            } catch (Exception e) {
                Toast.makeText(this, "Giá tiền không hợp lệ!", Toast.LENGTH_SHORT).show();
            }
        });
        dialog.show();
    }

    private void processSelectedImage(Uri uri) {
        try {
            InputStream inputStream = getContentResolver().openInputStream(uri);
            Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
            if (bitmap != null) processBitmap(bitmap);
        } catch (Exception e) {
            Toast.makeText(this, "Không thể tải ảnh!", Toast.LENGTH_SHORT).show();
        }
    }

    private void processBitmap(Bitmap bitmap) {
        Bitmap resized = getResizedBitmap(bitmap, 400);
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        resized.compress(Bitmap.CompressFormat.JPEG, 60, outputStream);
        byte[] byteArray = outputStream.toByteArray();
        selectedImageBase64 = Base64.encodeToString(byteArray, Base64.DEFAULT);
        
        runOnUiThread(() -> {
            if (imgPreview != null) {
                imgPreview.setImageBitmap(resized);
                layoutAddImage.setVisibility(View.GONE);
                btnChangeImage.setVisibility(View.VISIBLE);
            }
        });
    }

    private Bitmap getResizedBitmap(Bitmap image, int maxSize) {
        int width = image.getWidth();
        int height = image.getHeight();
        float bitmapRatio = (float) width / (float) height;
        if (bitmapRatio > 1) {
            width = maxSize;
            height = (int) (width / bitmapRatio);
        } else {
            height = maxSize;
            width = (int) (height * bitmapRatio);
        }
        return Bitmap.createScaledBitmap(image, width, height, true);
    }

    private void showDeleteConfirm(ProductEntity product) {
        new AlertDialog.Builder(this)
                .setTitle("Xóa món")
                .setMessage("Xóa '" + product.name + "'?")
                .setPositiveButton("Xóa", (d, w) -> {
                    AppExecutors.getInstance().getDiskIO().execute(() -> {
                        try {
                            // Delete from local database first
                            productDao.deleteProduct(product);
                            Log.d("MenuManagement", "Product deleted locally: " + product.name);
                            
                            // Then remove from Firebase
                            String fbKey = product.name.replaceAll("[.#$\\[\\]]", "_");
                            FirebaseHelper.getProductsRef().child(fbKey).removeValue((error, ref) -> {
                                if (error == null) {
                                    Log.d("MenuManagement", "Product deleted from Firebase: " + product.name);
                                    runOnUiThread(() -> {
                                        Toast.makeText(this, "Đã xóa món ăn!", Toast.LENGTH_SHORT).show();
                                    });
                                } else {
                                    Log.e("MenuManagement", "Firebase delete error: " + error.getMessage());
                                    runOnUiThread(() -> 
                                        Toast.makeText(this, "Lỗi xóa từ Firebase: " + error.getMessage(), Toast.LENGTH_SHORT).show()
                                    );
                                }
                            });
                        } catch (Exception e) {
                            Log.e("MenuManagement", "Error deleting product: " + e.getMessage(), e);
                            runOnUiThread(() -> 
                                Toast.makeText(this, "Lỗi xóa sản phẩm: " + e.getMessage(), Toast.LENGTH_SHORT).show()
                            );
                        }
                    });
                })
                .setNegativeButton("Hủy", null)
                .show();
    }
}

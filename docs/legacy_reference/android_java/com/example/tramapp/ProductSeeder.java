package com.example.tramapp;

import android.content.Context;
import android.util.Log;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.ValueEventListener;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Helper class to seed product data to Firebase
 * Products based on the Tram menu
 */
public class ProductSeeder {
    private static final String TAG = "ProductSeeder";
    private static int nextId = 1;

    public static void seedProductsToFirebase(Context context) {
        // Seed categories first
        seedCategoriesToFirebase(context);
        
        // Then seed products
        List<ProductEntity> products = createMenuProducts();
        
        AppDatabase db = AppDatabase.getInstance(context);
        ProductDao productDao = db.productDao();
        
        // Save to local database
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                for (ProductEntity product : products) {
                    productDao.insertProduct(product);
                    Log.d(TAG, "Inserted locally: " + product.name);
                }
                Log.d(TAG, "All products inserted to local database: " + products.size() + " products");
            } catch (Exception e) {
                Log.e(TAG, "Error inserting to local DB: " + e.getMessage(), e);
            }
        });
        
        // Save to Firebase
        DatabaseReference productsRef = FirebaseHelper.getProductsRef();
        for (ProductEntity product : products) {
            String fbKey = product.name.replaceAll("[.#$\\[\\]]", "_");
            productsRef.child(fbKey).setValue(product, (error, ref) -> {
                if (error == null) {
                    Log.d(TAG, "Firebase synced: " + product.name);
                } else {
                    Log.e(TAG, "Firebase error for " + product.name + ": " + error.getMessage());
                }
            });
        }
        Log.d(TAG, "Product seeding started: " + products.size() + " products");
    }

    /**
     * Clear local database and sync all products/categories from Firebase
     * This makes Firebase the source of truth
     */
    public static void clearAndSyncFromFirebase(Context context) {
        AppDatabase db = AppDatabase.getInstance(context);
        ProductDao productDao = db.productDao();
        CategoryDao categoryDao = db.categoryDao();
        
        // Clear local database
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                productDao.deleteAllProducts();
                categoryDao.deleteAllCategories();
                Log.d(TAG, "Local database cleared");
            } catch (Exception e) {
                Log.e(TAG, "Error clearing local DB: " + e.getMessage(), e);
            }
        });
        
        // Sync categories from Firebase
        DatabaseReference categoriesRef = FirebaseHelper.getCategoriesRef();
        categoriesRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    try {
                        for (DataSnapshot categorySnap : snapshot.getChildren()) {
                            CategoryEntity category = categorySnap.getValue(CategoryEntity.class);
                            if (category != null) {
                                categoryDao.insertCategory(category);
                                Log.d(TAG, "Synced category from Firebase: " + category.name);
                            }
                        }
                        Log.d(TAG, "All categories synced from Firebase");
                    } catch (Exception e) {
                        Log.e(TAG, "Error syncing categories: " + e.getMessage(), e);
                    }
                });
            }

            @Override
            public void onCancelled(DatabaseError error) {
                Log.e(TAG, "Firebase error loading categories: " + error.getMessage());
            }
        });
        
        // Sync products from Firebase
        DatabaseReference productsRef = FirebaseHelper.getProductsRef();
        productsRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot snapshot) {
                AppExecutors.getInstance().getDiskIO().execute(() -> {
                    try {
                        int count = 0;
                        for (DataSnapshot productSnap : snapshot.getChildren()) {
                            ProductEntity product = productSnap.getValue(ProductEntity.class);
                            if (product != null) {
                                productDao.insertProduct(product);
                                Log.d(TAG, "Synced product from Firebase: " + product.name);
                                count++;
                            }
                        }
                        Log.d(TAG, "All products synced from Firebase: " + count + " products");
                    } catch (Exception e) {
                        Log.e(TAG, "Error syncing products: " + e.getMessage(), e);
                    }
                });
            }

            @Override
            public void onCancelled(DatabaseError error) {
                Log.e(TAG, "Firebase error loading products: " + error.getMessage());
            }
        });
        
        Log.d(TAG, "Clear and sync from Firebase started");
    }

    private static void seedCategoriesToFirebase(Context context) {
        List<CategoryEntity> categories = new ArrayList<>();
        categories.add(createCategory("Sữa Hạt Tươi"));
        categories.add(createCategory("Trà Olong Trái Cây"));
        categories.add(createCategory("Trà Sữa Tươi"));
        categories.add(createCategory("Bánh Tam Giác Nướng"));
        categories.add(createCategory("Topping"));
        categories.add(createCategory("Bánh Lăn Nướng"));
        categories.add(createCategory("Bánh Tart"));
        categories.add(createCategory("CAFE Việt Nam"));
        categories.add(createCategory("Bơ Coco"));
        categories.add(createCategory("Bánh Waffle"));

        AppDatabase db = AppDatabase.getInstance(context);
        CategoryDao categoryDao = db.categoryDao();
        
        // Save to local database
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                for (CategoryEntity category : categories) {
                    categoryDao.insertCategory(category);
                    Log.d(TAG, "Inserted category locally: " + category.name);
                }
                Log.d(TAG, "All categories inserted to local database");
            } catch (Exception e) {
                Log.e(TAG, "Error inserting categories to local DB: " + e.getMessage(), e);
            }
        });
        
        // Save to Firebase
        DatabaseReference categoriesRef = FirebaseHelper.getCategoriesRef();
        for (CategoryEntity category : categories) {
            String fbKey = category.name.replaceAll("[.#$\\[\\]]", "_");
            categoriesRef.child(fbKey).setValue(category, (error, ref) -> {
                if (error == null) {
                    Log.d(TAG, "Firebase category synced: " + category.name);
                } else {
                    Log.e(TAG, "Firebase error for category " + category.name + ": " + error.getMessage());
                }
            });
        }
    }

    private static CategoryEntity createCategory(String name) {
        CategoryEntity category = new CategoryEntity();
        category.name = name;
        return category;
    }

    private static List<ProductEntity> createMenuProducts() {
        List<ProductEntity> products = new ArrayList<>();

        // ===== SỮA HẠT TƯƠI (Fresh Milk) =====
        products.add(createProduct("Sữa bò tươi - Đậu nành hạt điều", 18000, "Ly", "Sữa Hạt Tươi", "suadaunanhhanhnhan"));
        products.add(createProduct("Sữa bò tươi - Bí đỏ Đậu phộng", 18000, "Ly", "Sữa Hạt Tươi", "suabido"));
        products.add(createProduct("Sữa bò tươi - Cốm rang", 25000, "Ly", "Sữa Hạt Tươi", "suacomrang"));
        products.add(createProduct("Sữa bò tươi - Bắp non", 18000, "Ly", "Sữa Hạt Tươi", "anhapp"));

        // ===== TRÀ OLONG TRÁI CÂY (Oolong Tea with Fruits) =====
        products.add(createProduct("Trà Olong - Chanh tươi", 20000, "Ly", "Trà Olong Trái Cây", "trachanh"));
        products.add(createProduct("Trà Olong - Hoài", 30000, "Ly", "Trà Olong Trái Cây", "traxoai"));
        products.add(createProduct("Trà Olong - Chanh dây", 30000, "Ly", "Trà Olong Trái Cây", "trachanhday"));
        products.add(createProduct("Trà Olong - Quả mọng", 30000, "Ly", "Trà Olong Trái Cây", "traquamong"));
        products.add(createProduct("Trà Olong - Măng cau", 30000, "Ly", "Trà Olong Trái Cây", "tramangcau"));
        products.add(createProduct("Trà Olong - Đào", 30000, "Ly", "Trà Olong Trái Cây", "tradao"));

        // ===== TRÀ SỮA TƯƠI (Fresh Milk Tea) =====
        products.add(createProduct("Trà sữa tươi - Olong matcha", 30000, "Ly", "Trà Sữa Tươi", "tsmatcha"));
        products.add(createProduct("Trà sữa tươi - Olong gạo rang", 35000, "Ly", "Trà Sữa Tươi", "tsgaorang"));

        // ===== BÁNH TAM GIÁC NƯỚNG (Toasted Triangle Bread) =====
        products.add(createProduct("Tam giác - nhân sữa", 20000, "Cái", "Bánh Tam Giác Nướng", "banhtamgiac"));
        products.add(createProduct("Tam giác - nhân phô mai", 20000, "Cái", "Bánh Tam Giác Nướng", "banhtamgiac"));
        products.add(createProduct("Tam giác - nhân trứng muối", 20000, "Cái", "Bánh Tam Giác Nướng", "banhtamgiac"));

        // ===== TOPPING =====
        products.add(createProduct("Thạch dừa / Thạch chanh", 5000, "Ly", "Topping", "bochoco"));

        // ===== BÁNH LĂN NƯỚNG (Rolled Toasted Bread) =====
        products.add(createProduct("Bánh lăn truyền thống - Size 15", 15000, "Cái", "Bánh Lăn Nướng", "banhlannho"));
        products.add(createProduct("Bánh lăn truyền thống - Size 30", 30000, "Cái", "Bánh Lăn Nướng", "banhlanlon"));
        products.add(createProduct("Bánh lăn phô mai chảy - Size 15", 15000, "Cái", "Bánh Lăn Nướng", "banhlannho"));
        products.add(createProduct("Bánh lăn phô mai chảy - Size 30", 30000, "Cái", "Bánh Lăn Nướng", "banhlanvua"));
        products.add(createProduct("Bánh lăn phô mai chảy - Size 50", 50000, "Cái", "Bánh Lăn Nướng", "banhlanlon"));
        products.add(createProduct("Bánh lăn choco chip - Size 15", 15000, "Cái", "Bánh Lăn Nướng", "banhlannho"));
        products.add(createProduct("Bánh lăn choco chip - Size 30", 30000, "Cái", "Bánh Lăn Nướng", "banhlanvua"));
        products.add(createProduct("Bánh lăn choco chip - Size 50", 50000, "Cái", "Bánh Lăn Nướng", "banhlanlon"));
        products.add(createProduct("Bánh lăn cốm déo - Size 15", 15000, "Cái", "Bánh Lăn Nướng", "banhlannho"));
        products.add(createProduct("Bánh lăn cốm déo - Size 30", 30000, "Cái", "Bánh Lăn Nướng", "banhlanvua"));
        products.add(createProduct("Bánh lăn cốm déo - Size 50", 50000, "Cái", "Bánh Lăn Nướng", "banhlanlon"));

        // ===== BÁNH TART =====
        products.add(createProduct("Bánh tart trứng", 18000, "Cái", "Bánh Tart", "tartchuoichoco"));
        products.add(createProduct("Bánh tart chuối choco", 20000, "Cái", "Bánh Tart", "tartchuoichoco"));

        // ===== CAFE VIỆT NAM =====
        products.add(createProduct("Cà phê đen", 18000, "Ly", "CAFE Việt Nam", "cfden"));
        products.add(createProduct("Cà phê sữa", 20000, "Ly", "CAFE Việt Nam", "cfsua"));
        products.add(createProduct("Bạc xỉu", 25000, "Ly", "CAFE Việt Nam", "bacxiu"));
        products.add(createProduct("Cà phê kem trứng", 30000, "Ly", "CAFE Việt Nam", "cfkemtrung"));

        // ===== BƠ COCO =====
        products.add(createProduct("Bơ coco", 35000, "Ly", "Bơ Coco", "bochoco"));

        // ===== BÁNH WAFFLE =====
        products.add(createProduct("Bánh waffle bơ cay chà bông", 25000, "Cái", "Bánh Waffle", "banhwafflebocaychabong"));
        products.add(createProduct("Bánh waffle cốm dẻo", 25000, "Cái", "Bánh Waffle", "banhwafflecomdeo"));
        products.add(createProduct("Bánh waffle kem choco", 25000, "Cái", "Bánh Waffle", "banhwafflekemchoco"));

        return products;
    }

    /**
     * Convert product name to image resource name (no diacritics, no spaces)
     * Example: "Sữa bò tươi - Đậu nành hạt điều" → "sua_bo_tuoi_dau_nanh_hat_dieu"
     */
    private static String toImageResourceName(String productName) {
        if (productName == null || productName.isEmpty()) {
            return "default_product";
        }
        
        // Remove diacritics using NFD normalization
        String nfd = Normalizer.normalize(productName, Normalizer.Form.NFD);
        Pattern pattern = Pattern.compile("\\p{InCombiningDiacriticalMarks}+");
        String normalized = pattern.matcher(nfd).replaceAll("");
        
        // Convert to lowercase, replace spaces and special chars with underscore
        String resourceName = normalized
            .toLowerCase()
            .replaceAll("[^a-z0-9]+", "_")
            .replaceAll("^_|_$", ""); // Remove leading/trailing underscores
        
        return resourceName;
    }

    private static ProductEntity createProduct(String name, int price, String unit, String category, String imageResourceName) {
        ProductEntity product = new ProductEntity();
        product.id = nextId++;
        product.name = name;
        product.price = price;
        product.unit = unit;
        product.category = category;
        product.imageBase64 = null;
        product.imageResourceName = imageResourceName;
        return product;
    }
}

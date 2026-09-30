package com.example.tramapp;

import android.content.Context;
import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;

@Database(entities = {
    TableEntity.class,
    ProductEntity.class,
    ZoneEntity.class,
    CategoryEntity.class,
    OrderHistoryEntity.class,
    UserEntity.class,
    KitchenOrderEntity.class,
    OnlineOrderEntity.class
}, version = 27)
public abstract class AppDatabase extends RoomDatabase {

    private static AppDatabase instance;

    public abstract TableDao tableDao();
    public abstract ProductDao productDao();
    public abstract ZoneDao zoneDao();
    public abstract CategoryDao categoryDao();
    public abstract OrderHistoryDao orderHistoryDao();
    public abstract UserDao userDao();
    public abstract KitchenOrderDao kitchenOrderDao();
    public abstract OnlineOrderDao onlineOrderDao();

    public static synchronized AppDatabase getInstance(Context context) {
        if (instance == null) {
            instance = Room.databaseBuilder(context.getApplicationContext(),
                            AppDatabase.class, "tram_app_db_v27")                    .allowMainThreadQueries()
                    .fallbackToDestructiveMigration()
                    .build();
            
            // Khởi tạo tài khoản mặc định trong luồng riêng để tránh treo UI
            AppExecutors.getInstance().getDiskIO().execute(() -> {
                try {
                    if (instance.userDao().countUsers() == 0) {
                        instance.userDao().insertUser(new UserEntity("Nhân viên", "nv", "1", "STAFF"));
                        instance.userDao().insertUser(new UserEntity("Quản lý", "ql", "1", "MANAGER"));
                        instance.userDao().insertUser(new UserEntity("Đầu bếp", "bep", "1", "KITCHEN"));
                    }
                } catch (Exception ignored) {}
            });
        }
        return instance;
    }
}
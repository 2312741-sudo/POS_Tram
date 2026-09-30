package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface OnlineOrderDao {
    @Query("SELECT * FROM online_orders ORDER BY timestamp DESC")
    List<OnlineOrderEntity> getAllOnlineOrders();

    @Query("SELECT * FROM online_orders WHERE status = :status ORDER BY timestamp DESC")
    List<OnlineOrderEntity> getOrdersByStatus(String status);

    @Query("SELECT * FROM online_orders WHERE tableName = :tableName ORDER BY timestamp DESC")
    List<OnlineOrderEntity> getOrdersByTable(String tableName);

    @Query("SELECT * FROM online_orders WHERE id = :id LIMIT 1")
    OnlineOrderEntity getOrderById(int id);

    @Query("SELECT * FROM online_orders WHERE firebaseKey = :firebaseKey LIMIT 1")
    OnlineOrderEntity getOrderByFirebaseKey(String firebaseKey);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertOnlineOrder(OnlineOrderEntity order);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    long insert(OnlineOrderEntity order);

    @Update
    void updateOnlineOrder(OnlineOrderEntity order);

    @Update
    void update(OnlineOrderEntity order);

    @Delete
    void deleteOnlineOrder(OnlineOrderEntity order);

    @Query("DELETE FROM online_orders WHERE firebaseKey = :firebaseKey")
    void deleteByFirebaseKey(String firebaseKey);

    @Query("DELETE FROM online_orders")
    void deleteAllOnlineOrders();

    @Query("SELECT COUNT(*) FROM online_orders WHERE status = 'PENDING'")
    int countPendingOrders();
}

package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface KitchenOrderDao {
    @Query("SELECT * FROM kitchen_orders WHERE isDone = 0 ORDER BY timestamp ASC")
    List<KitchenOrderEntity> getActiveOrders();

    @Insert
    void insertKitchenOrder(KitchenOrderEntity order);

    @Update
    void updateKitchenOrder(KitchenOrderEntity order);

    @Query("DELETE FROM kitchen_orders WHERE isDone = 1")
    void clearFinishedOrders();
}
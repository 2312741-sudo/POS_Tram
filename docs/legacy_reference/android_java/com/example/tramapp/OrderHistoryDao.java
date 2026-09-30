package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.Query;
import java.util.List;

@Dao
public interface OrderHistoryDao {
    @Query("SELECT * FROM order_history ORDER BY timestamp DESC")
    List<OrderHistoryEntity> getAllHistory();

    @Insert
    void insertHistory(OrderHistoryEntity history);

    @Delete
    void deleteHistory(OrderHistoryEntity history);

    @Query("DELETE FROM order_history")
    void deleteAllHistory();
}
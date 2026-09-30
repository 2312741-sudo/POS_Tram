package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;

@Entity(tableName = "kitchen_orders")
public class KitchenOrderEntity {
    @PrimaryKey(autoGenerate = true)
    public int id;
    
    public String tableName;
    public String itemsJson; // JSON string of items and quantities
    public long timestamp;
    public boolean isDone;
    
    @Ignore
    public String firebaseKey; // Dùng để update trên Firebase

    public KitchenOrderEntity() {
        // Constructor mặc định cho Firebase
    }

    @Ignore
    public KitchenOrderEntity(String tableName, String itemsJson, long timestamp) {
        this.tableName = tableName;
        this.itemsJson = itemsJson;
        this.timestamp = timestamp;
        this.isDone = false;
    }
}
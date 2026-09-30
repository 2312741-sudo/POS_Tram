package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;
import java.io.Serializable;

@com.google.firebase.database.IgnoreExtraProperties
@Entity(tableName = "online_orders")
public class OnlineOrderEntity implements Serializable {
    @PrimaryKey(autoGenerate = true)
    public int id;
    
    public String firebaseKey; // Firebase key để track
    public String tableName; // Tên bàn (A1, A2, ...)
    public String tableZone; // Khu vực (Khu A, Khu B, ...)
    public String itemsJson; // JSON danh sách món (item1, item2, ...)
    public String status; // PENDING, CONFIRMED, COMPLETED, CANCELLED
    public String type; // ORDER, CALL_WAITER
    public long timestamp; // Thời gian tạo
    public String notes; // Ghi chú thêm

    public OnlineOrderEntity() {
    }

    @Ignore
    public OnlineOrderEntity(String firebaseKey, String tableName, String tableZone, String itemsJson, String status, String type, long timestamp) {
        this.firebaseKey = firebaseKey;
        this.tableName = tableName;
        this.tableZone = tableZone;
        this.itemsJson = itemsJson;
        this.status = status;
        this.type = type;
        this.timestamp = timestamp;
    }

    @Ignore
    public OnlineOrderEntity(String tableName, String tableZone, String itemsJson, String status, String type, long timestamp) {
        this.tableName = tableName;
        this.tableZone = tableZone;
        this.itemsJson = itemsJson;
        this.status = status;
        this.type = type;
        this.timestamp = timestamp;
    }
}

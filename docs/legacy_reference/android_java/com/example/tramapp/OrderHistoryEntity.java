package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;
import java.io.Serializable;

@Entity(tableName = "order_history")
public class OrderHistoryEntity implements Serializable {
    @PrimaryKey(autoGenerate = true)
    public int id;

    public String orderCode; // Mã hóa đơn duy nhất (VD: HD171500123)
    public String tableName;
    public int totalAmount;
    public String itemsJson; // Danh sách món dưới dạng JSON
    public String paymentMethod; // Tiền mặt, Chuyển khoản, Đã đặt (Chưa thanh toán)
    public long timestamp; // Thời gian
    public String status; // "Đã đặt", "Đã thanh toán"

    @Ignore
    public String firebaseKey; // Dùng để xóa trên Firebase

    public OrderHistoryEntity() {
    }

    @Ignore
    public OrderHistoryEntity(String orderCode, String tableName, int totalAmount, String itemsJson, String paymentMethod, long timestamp, String status) {
        this.orderCode = orderCode;
        this.tableName = tableName;
        this.totalAmount = totalAmount;
        this.itemsJson = itemsJson;
        this.paymentMethod = paymentMethod;
        this.timestamp = timestamp;
        this.status = status;
    }
}
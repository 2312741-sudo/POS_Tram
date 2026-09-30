package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;
import java.io.Serializable;

@Entity(tableName = "products")
public class ProductEntity implements Serializable {
    @PrimaryKey(autoGenerate = true)
    public int id;
    
    public String name;
    public int price;
    public String unit; 
    public String category; 
    public String imageResourceName; // Tên resource cũ
    public String imageBase64; // Dữ liệu ảnh dạng chuỗi Base64 để đồng bộ

    public ProductEntity() {
    }

    @Ignore
    public ProductEntity(String name, int price, String unit, String category, String imageBase64) {
        this.name = name;
        this.price = price;
        this.unit = unit;
        this.category = category;
        this.imageBase64 = imageBase64;
    }
}
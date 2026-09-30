package com.example.tramapp;
import java.io.Serializable;

public class Product implements Serializable {
    private String id;
    private String name;
    private int price;
    private String unit;
    private String category;
    private String imageResourceName;
    private String imageBase64;
    private int quantity;
    private String note;

    public Product() {
    }

    public Product(String id, String name, int price, String unit, String category, String imageResourceName, String imageBase64) {
        this.id = id;
        this.name = name;
        this.price = price;
        this.unit = unit;
        this.category = category;
        this.imageResourceName = imageResourceName;
        this.imageBase64 = imageBase64;
        this.quantity = 0;
        this.note = "";
    }

    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }
    public int getPrice() { return price; }
    public String getName() { return name; }
    public String getUnit() { return unit; }
    public String getCategory() { return category; }
    public String getImageResourceName() { return imageResourceName; }
    public String getImageBase64() { return imageBase64; }
    public void setImageBase64(String imageBase64) { this.imageBase64 = imageBase64; }
    public String getNote() { return note; }
    public void setNote(String note) { this.note = note; }
}
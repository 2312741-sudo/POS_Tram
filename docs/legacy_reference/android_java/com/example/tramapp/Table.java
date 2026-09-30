package com.example.tramapp;

public class Table {
    private String name;
    private boolean inUse; // true = Sử dụng, false = Còn trống
    private String zone;   // "Bitis", "Khu quầy"... dùng cho bộ lọc sau

    public Table(String name, boolean inUse, String zone) {
        this.name = name;
        this.inUse = inUse;
        this.zone = zone;
    }

    public String getName() { return name; }
    public boolean isInUse() { return inUse; }
    public String getZone() { return zone; }
}
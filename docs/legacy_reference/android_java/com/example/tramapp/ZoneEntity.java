package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;

@Entity(tableName = "zones")
public class ZoneEntity {
    @PrimaryKey(autoGenerate = true)
    public int id;
    public String name;

    public ZoneEntity() {
    }

    @Ignore
    public ZoneEntity(String name) {
        this.name = name;
    }
}
package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;

@Entity(tableName = "categories")
public class CategoryEntity {
    @PrimaryKey(autoGenerate = true)
    public int id;
    public String name;

    public CategoryEntity() {
    }

    @Ignore
    public CategoryEntity(String name) {
        this.name = name;
    }
}
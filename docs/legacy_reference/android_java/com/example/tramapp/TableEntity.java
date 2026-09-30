package com.example.tramapp;

import androidx.room.ColumnInfo;
import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;
import java.io.Serializable;

@Entity(tableName = "tables")
public class TableEntity implements Serializable {

    // Removed @PrimaryKey(autoGenerate = true) from here
    @ColumnInfo(name = "current_order_json")
    public String currentOrderJson;

    @PrimaryKey(autoGenerate = true)
    public int id;

    @ColumnInfo(name = "table_name")
    public String name;

    @ColumnInfo(name = "table_zone")
    public String zone;

    @ColumnInfo(name = "is_in_use")
    public boolean inUse;

    public TableEntity() {
    }

    @Ignore
    public TableEntity(String name, String zone, boolean inUse) {
        this.name = name;
        this.zone = zone;
        this.inUse = inUse;
    }
}

package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface TableDao {
    @Query("SELECT * FROM tables")
    List<TableEntity> getAllTables();

    @Query("SELECT COUNT(*) FROM tables WHERE table_name = :name AND table_zone = :zone")
    int countTableByNameInZone(String name, String zone);

    @Query("SELECT * FROM tables WHERE table_name = :name AND table_zone = :zone LIMIT 1")
    TableEntity getTableByNameInZone(String name, String zone);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    long insertTable(TableEntity table);

    @Delete
    void deleteTable(TableEntity table);

    @Update
    void updateTable(TableEntity table);
}
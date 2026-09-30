package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface ZoneDao {
    @Query("SELECT * FROM zones")
    List<ZoneEntity> getAllZones();

    @Query("SELECT COUNT(*) FROM zones WHERE name = :name")
    int countZoneByName(String name);

    @Query("SELECT * FROM zones WHERE name = :name LIMIT 1")
    ZoneEntity getZoneByName(String name);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertZone(ZoneEntity zone);

    @Update
    void updateZone(ZoneEntity zone);

    @Delete
    void deleteZone(ZoneEntity zone);
}
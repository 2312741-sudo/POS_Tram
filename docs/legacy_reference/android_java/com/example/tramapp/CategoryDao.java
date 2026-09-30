package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface CategoryDao {
    @Query("SELECT * FROM categories")
    List<CategoryEntity> getAllCategories();

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertCategory(CategoryEntity category);

    @Update
    void updateCategory(CategoryEntity category);

    @Delete
    void deleteCategory(CategoryEntity category);

    @Query("SELECT COUNT(*) FROM categories WHERE name = :name")
    int countCategoryByName(String name);

    @Query("SELECT * FROM categories WHERE name = :name LIMIT 1")
    CategoryEntity getCategoryByName(String name);

    @Query("DELETE FROM categories")
    void deleteAllCategories();
}
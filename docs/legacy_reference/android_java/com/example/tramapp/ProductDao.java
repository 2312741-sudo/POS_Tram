package com.example.tramapp;

import androidx.room.Dao;
import androidx.room.Delete;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Update;
import java.util.List;

@Dao
public interface ProductDao {
    @Query("SELECT * FROM products")
    List<ProductEntity> getAllProducts();

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertProduct(ProductEntity product);

    @Update
    void updateProduct(ProductEntity product);

    @Delete
    void deleteProduct(ProductEntity product);
    
    @Query("DELETE FROM products")
    void deleteAllProducts();

    @Query("SELECT COUNT(*) FROM products")
    int countProducts();

    @Query("SELECT * FROM products WHERE id = :id LIMIT 1")
    ProductEntity getProductById(int id);
}
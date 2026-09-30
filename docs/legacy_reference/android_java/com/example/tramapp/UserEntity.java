package com.example.tramapp;

import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;

@Entity(tableName = "users")
public class UserEntity {
    @PrimaryKey(autoGenerate = true)
    public int id;
    public String fullName;
    public String username;
    public String password;
    public String role; // "STAFF", "MANAGER", "KITCHEN"

    public UserEntity() {
    }

    @Ignore
    public UserEntity(String fullName, String username, String password, String role) {
        this.fullName = fullName;
        this.username = username;
        this.password = password;
        this.role = role;
    }
}
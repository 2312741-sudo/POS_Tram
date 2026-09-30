package com.example.tramapp;

import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;

public class FirebaseHelper {
    private static DatabaseReference mDatabase;

    public static DatabaseReference getRef() {
        if (mDatabase == null) {
            mDatabase = FirebaseDatabase
                    .getInstance("https://ungdungdidong-94edd-default-rtdb.firebaseio.com")
                    .getReference();
        }
        return mDatabase;
    }

    public static DatabaseReference getTablesRef() {
        return getRef().child("tables");
    }

    public static DatabaseReference getKitchenOrdersRef() {
        return getRef().child("kitchen_orders");
    }

    public static DatabaseReference getOnlineOrdersRef() {
        return getRef().child("online_orders");
    }

    public static DatabaseReference getHistoryRef() {
        return getRef().child("history");
    }

    public static DatabaseReference getUsersRef() {
        return getRef().child("users");
    }
    
    public static DatabaseReference getProductsRef() {
        return getRef().child("products");
    }

    public static DatabaseReference getZonesRef() {
        return getRef().child("zones");
    }

    public static DatabaseReference getCategoriesRef() {
        return getRef().child("categories");
    }
}
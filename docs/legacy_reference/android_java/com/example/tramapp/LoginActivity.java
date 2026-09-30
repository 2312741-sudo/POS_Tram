package com.example.tramapp;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;

public class LoginActivity extends AppCompatActivity {

    private EditText edtUsername, edtPassword;
    private Button btnLogin;
    private UserDao userDao;
    private SharedPreferences sharedPreferences;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        sharedPreferences = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        
        // Auto sync from Firebase on app startup
        ProductSeeder.clearAndSyncFromFirebase(this);
        
        // KIỂM TRA NẾU ĐÃ ĐĂNG NHẬP TRƯỚC ĐÓ
        String savedRole = sharedPreferences.getString("USER_ROLE", null);
        String savedUser = sharedPreferences.getString("USERNAME", null);
        
        if (savedRole != null && savedUser != null) {
            performLogin(savedUser, savedRole);
            return;
        }

        setContentView(R.layout.activity_login);

        edtUsername = findViewById(R.id.edt_username);
        edtPassword = findViewById(R.id.edt_password);
        btnLogin = findViewById(R.id.btn_login);
        userDao = AppDatabase.getInstance(this).userDao();

        btnLogin.setOnClickListener(v -> {
            String user = edtUsername.getText().toString().trim();
            String pass = edtPassword.getText().toString().trim();

            if (user.isEmpty() || pass.isEmpty()) {
                Toast.makeText(this, "Vui lòng nhập tài khoản và mật khẩu", Toast.LENGTH_SHORT).show();
                return;
            }

            FirebaseHelper.getUsersRef().addListenerForSingleValueEvent(new ValueEventListener() {
                @Override
                public void onDataChange(@NonNull DataSnapshot snapshot) {
                    boolean found = false;
                    for (DataSnapshot ds : snapshot.getChildren()) {
                        UserEntity u = ds.getValue(UserEntity.class);
                        if (u != null && u.username.equals(user) && u.password.equals(pass)) {
                            found = true;
                            saveLoginState(u.username, u.role, u.fullName);
                            if (userDao.countUsers() < 100) {
                                AppExecutors.getInstance().getDiskIO().execute(() -> userDao.insertUser(u));
                            }
                            performLogin(u.username, u.role);
                            break;
                        }
                    }
                    
                    if (!found) {
                        AppExecutors.getInstance().getDiskIO().execute(() -> {
                            UserEntity localUser = userDao.login(user, pass);
                            runOnUiThread(() -> {
                                if (localUser != null) {
                                    saveLoginState(localUser.username, localUser.role, localUser.fullName);
                                    performLogin(localUser.username, localUser.role);
                                } else {
                                    Toast.makeText(LoginActivity.this, "Sai tài khoản hoặc mật khẩu", Toast.LENGTH_SHORT).show();
                                }
                            });
                        });
                    }
                }

                @Override
                public void onCancelled(@NonNull DatabaseError error) {
                    AppExecutors.getInstance().getDiskIO().execute(() -> {
                        UserEntity localUser = userDao.login(user, pass);
                        runOnUiThread(() -> {
                            if (localUser != null) {
                                saveLoginState(localUser.username, localUser.role, localUser.fullName);
                                performLogin(localUser.username, localUser.role);
                            }
                        });
                    });
                }
            });
        });
    }

    private void saveLoginState(String username, String role, String fullName) {
        SharedPreferences.Editor editor = sharedPreferences.edit();
        editor.putString("USERNAME", username);
        editor.putString("USER_ROLE", role);
        editor.putString("FULL_NAME", fullName != null ? fullName : username);
        editor.apply();
    }

    private void performLogin(String username, String role) {
        Intent intent;
        if ("KITCHEN".equals(role)) {
            intent = new Intent(this, KitchenActivity.class);
        } else {
            intent = new Intent(this, TableListActivity.class);
            intent.putExtra("USER_ROLE", role);
        }
        startActivity(intent);
        finish();
    }
}
package com.example.tramapp;

import android.app.Dialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.AsyncTask;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;
import android.app.AlertDialog;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import com.google.firebase.database.ChildEventListener;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.io.InputStream;
import java.lang.reflect.Type;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Random;

public class OrderActivity extends AppCompatActivity {

    private RecyclerView rvCart;
    private TextView tvSelectedTable, tvTotalPrice;
    private Button btnSaveTable, btnPayment, btnAddMoreFood;
    private ImageButton btnBack;

    private TableEntity currentTable;
    private TableDao tableDao;
    private OrderHistoryDao orderHistoryDao;
    private KitchenOrderDao kitchenOrderDao;

    private final ArrayList<Product> cartList = new ArrayList<>();
    private String userRole = "MANAGER";
    
    private String kitchenPrinterIp, billPrinterIp, bankId, bankAccount, accountName;
    private boolean autoPrintKitchen;
    private boolean kitchenNotifFirstLoad = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_order);

        AppDatabase db = AppDatabase.getInstance(this);
        tableDao = db.tableDao();
        orderHistoryDao = db.orderHistoryDao();
        kitchenOrderDao = db.kitchenOrderDao();

        initViews();
        loadSettings();
        
        currentTable = (TableEntity) getIntent().getSerializableExtra("TABLE_DATA");
        userRole = getIntent().getStringExtra("USER_ROLE");
        if (userRole == null) userRole = "MANAGER";
        
        if (currentTable != null) {
            tvSelectedTable.setText(String.format("Bàn: %s", currentTable.name));
            if (currentTable.currentOrderJson != null && !currentTable.currentOrderJson.isEmpty()) {
                try {
                    Gson gson = new Gson();
                    Type type = new TypeToken<ArrayList<Product>>() {}.getType();
                    ArrayList<Product> existingOrder = gson.fromJson(currentTable.currentOrderJson, type);
                    if (existingOrder != null) cartList.addAll(existingOrder);
                } catch (Exception ignored) {}
            }

            @SuppressWarnings("unchecked")
            ArrayList<Product> newItems = (ArrayList<Product>) getIntent().getSerializableExtra("SELECTED_PRODUCTS");
            if (newItems != null) {
                mergeNewItems(newItems);
            }
        }

        setupRecyclerView();
        handleEvents();
        updateTotalDisplay();
        setupKitchenNotificationSync();
    }

    private void loadSettings() {
        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
        kitchenPrinterIp = prefs.getString("KITCHEN_PRINTER_IP", "192.168.1.100");
        billPrinterIp = prefs.getString("BILL_PRINTER_IP", "192.168.1.100");
        autoPrintKitchen = prefs.getBoolean("AUTO_PRINT_KITCHEN", true);
        bankId = prefs.getString("BANK_ID", "MB");
        bankAccount = prefs.getString("BANK_ACCOUNT", "123456789");
        accountName = prefs.getString("ACCOUNT_NAME", "TRAM APP");
    }

    private void initViews() {
        rvCart = findViewById(R.id.rv_cart);
        tvSelectedTable = findViewById(R.id.tv_selected_table);
        tvTotalPrice = findViewById(R.id.tv_total_price);
        btnSaveTable = findViewById(R.id.btn_notify); 
        btnPayment = findViewById(R.id.btn_payment);
        btnAddMoreFood = findViewById(R.id.btn_add_more_food);
        btnBack = findViewById(R.id.btn_back_order);
    }

    private void handleEvents() {
        btnBack.setOnClickListener(v -> finish());

        btnAddMoreFood.setOnClickListener(v -> {
            saveCurrentOrderToFirebase();
            Intent intent = new Intent(this, OrderListActivity.class);
            intent.putExtra("TABLE_DATA", currentTable);
            intent.putExtra("USER_ROLE", userRole);
            startActivity(intent);
            finish();
        });

        btnSaveTable.setOnClickListener(v -> {
            loadSettings();
            saveCurrentOrderToFirebase();
            sendToKitchenDirect(); 
            Toast.makeText(this, "Đã order và gửi bếp thành công!", Toast.LENGTH_SHORT).show();
            returnToMain();
        });

        btnPayment.setOnClickListener(v -> {
            loadSettings();
            showPaymentDialog(calculateTotal());
        });
    }

    private void sendToKitchenDirect() {
        if (cartList.isEmpty()) return;
        String itemsJson = new Gson().toJson(cartList);
        KitchenOrderEntity kitchenOrder = new KitchenOrderEntity(currentTable.name, itemsJson, System.currentTimeMillis());
        
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                // Insert vào local database
                kitchenOrderDao.insertKitchenOrder(kitchenOrder);
                
                // Push tới Firebase và capture Firebase key
                FirebaseHelper.getKitchenOrdersRef().push().setValue(kitchenOrder, (error, ref) -> {
                    if (error == null) {
                        // Lấy firebase key từ ref
                        String firebaseKey = ref.getKey();
                        
                        // Update kitchen order với firebase key
                        kitchenOrder.firebaseKey = firebaseKey;
                        kitchenOrderDao.updateKitchenOrder(kitchenOrder);
                        
                        runOnUiThread(() -> {
                            Log.d("KitchenOrder", "Order sent successfully to kitchen: " + firebaseKey);
                        });
                    } else {
                        runOnUiThread(() -> {
                            Log.e("KitchenOrder", "Error sending order to kitchen: " + error.getMessage());
                            Toast.makeText(OrderActivity.this, "Lỗi khi gửi đơn tới bếp!", Toast.LENGTH_SHORT).show();
                        });
                    }
                });
                
                // In trực tiếp ngay tức thì
                if (autoPrintKitchen) {
                    EscPosPrinter.printKitchenOrderDirect(kitchenPrinterIp, kitchenOrder);
                }
            } catch (Exception e) {
                Log.e("KitchenOrder", "Exception: " + e.getMessage(), e);
            }
        });
    }

    private void showPaymentDialog(int totalAmount) {
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_payment);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }

        TextView txtTotal = dialog.findViewById(R.id.txt_total_amount);
        RadioGroup rgMethod = dialog.findViewById(R.id.rg_payment_method);
        LinearLayout layoutSplit = dialog.findViewById(R.id.layout_split_payment);
        LinearLayout layoutQR = dialog.findViewById(R.id.layout_qr_code);
        ImageView imgQR = dialog.findViewById(R.id.img_qr_code);
        EditText edtCashAmount = dialog.findViewById(R.id.edt_cash_amount);
        TextView txtTransferHint = dialog.findViewById(R.id.txt_transfer_hint);
        Button btnConfirm = dialog.findViewById(R.id.btn_confirm_payment);
        CheckBox cbPrintBill = dialog.findViewById(R.id.cb_print_bill);
        CheckBox cbIncludeQR = dialog.findViewById(R.id.cb_include_qr);

        txtTotal.setText(new DecimalFormat("#,### đ").format(totalAmount));

        rgMethod.setOnCheckedChangeListener((group, checkedId) -> {
            boolean isSplit = checkedId == R.id.rb_split;
            boolean isTransfer = checkedId == R.id.rb_transfer;
            layoutSplit.setVisibility(isSplit ? View.VISIBLE : View.GONE);
            layoutQR.setVisibility((isTransfer || isSplit) ? View.VISIBLE : View.GONE);
            
            if (isTransfer || isSplit) {
                int amountToTransfer = totalAmount;
                if (isSplit) {
                    try {
                        String s = edtCashAmount.getText().toString();
                        int cashGiven = s.isEmpty() ? 0 : Integer.parseInt(s);
                        amountToTransfer = Math.max(0, totalAmount - cashGiven);
                    } catch (Exception ignored) {}
                }
                loadRealQRCode(imgQR, amountToTransfer);
            }
        });

        edtCashAmount.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
            @Override
            public void afterTextChanged(Editable s) {
                try {
                    int cashGiven = s.toString().isEmpty() ? 0 : Integer.parseInt(s.toString());
                    int transferNeeded = totalAmount - cashGiven;
                    txtTransferHint.setText(transferNeeded < 0 ? String.format("Tiền thừa: %s", new DecimalFormat("#,###").format(Math.abs(transferNeeded))) : String.format("Còn lại: %s", new DecimalFormat("#,###").format(transferNeeded)));
                    
                    if (rgMethod.getCheckedRadioButtonId() == R.id.rb_split) {
                        loadRealQRCode(imgQR, Math.max(0, transferNeeded));
                    }
                } catch (Exception ignored) {}
            }
        });

        btnConfirm.setOnClickListener(v -> {
            String method = "Tiền mặt";
            int checkedId = rgMethod.getCheckedRadioButtonId();
            if (checkedId == R.id.rb_transfer) method = "Chuyển khoản";
            else if (checkedId == R.id.rb_split) method = "Tiền mặt + CK";

            OrderHistoryEntity history = new OrderHistoryEntity(
                    generateOrderCode(),
                    currentTable.name,
                    totalAmount,
                    new Gson().toJson(new ArrayList<>(cartList)),
                    method,
                    System.currentTimeMillis(),
                    "Đã thanh toán"
            );

            boolean shouldPrint = cbPrintBill.isChecked();
            boolean includeQR = cbIncludeQR.isChecked();

            AppExecutors.getInstance().getDiskIO().execute(() -> {
                try {
                    orderHistoryDao.insertHistory(history);
                    FirebaseHelper.getHistoryRef().push().setValue(history);
                    
                    currentTable.inUse = false;
                    currentTable.currentOrderJson = "";
                    tableDao.updateTable(currentTable);
                    FirebaseHelper.getTablesRef().child(currentTable.zone + "_" + currentTable.name).setValue(currentTable);

                    runOnUiThread(() -> {
                        dialog.dismiss();
                        if (shouldPrint) {
                            doSilentPrintBill(history, includeQR);
                        } else {
                            Toast.makeText(this, "Thanh toán thành công!", Toast.LENGTH_SHORT).show();
                            returnToMain();
                        }
                    });
                } catch (Exception ignored) {}
            });
        });
        dialog.show();
    }

    private void loadRealQRCode(ImageView imageView, int amount) {
        String encodedName = accountName.replace(" ", "%20");
        String qrUrl = "https://img.vietqr.io/image/" + bankId + "-" + bankAccount + "-compact2.png" +
                "?amount=" + amount +
                "&addInfo=" + EscPosPrinter.removeAccent(currentTable.name) + "%20THANH%20TOAN" +
                "&accountName=" + encodedName;
        new DownloadImageTask(imageView).execute(qrUrl);
    }

    private static class DownloadImageTask extends AsyncTask<String, Void, Bitmap> {
        ImageView bmImage;
        public DownloadImageTask(ImageView bmImage) { this.bmImage = bmImage; }
        protected Bitmap doInBackground(String... urls) {
            String urldisplay = urls[0];
            Bitmap mIcon11 = null;
            try {
                InputStream in = new java.net.URL(urldisplay).openStream();
                mIcon11 = BitmapFactory.decodeStream(in);
            } catch (Exception e) { e.printStackTrace(); }
            return mIcon11;
        }
        protected void onPostExecute(Bitmap result) { if (result != null) bmImage.setImageBitmap(result); }
    }

    private void doSilentPrintBill(OrderHistoryEntity history, boolean includeQR) {
        String qrData = null;
        if (includeQR) {
            qrData = EscPosPrinter.generateVietQRText(
                    bankId, 
                    bankAccount, 
                    accountName,
                    history.totalAmount, 
                    EscPosPrinter.removeAccent(history.tableName) + " THANH TOAN"
            );
        }
        EscPosPrinter.printBillDirect(billPrinterIp, history, includeQR, qrData);
        new android.os.Handler().postDelayed(this::returnToMain, 1000);
    }

    private void saveCurrentOrderToFirebase() {
        if (cartList.isEmpty()) {
            currentTable.inUse = false;
            currentTable.currentOrderJson = "";
        } else {
            currentTable.inUse = true;
            currentTable.currentOrderJson = new Gson().toJson(cartList);
        }
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            try {
                tableDao.updateTable(currentTable);
                FirebaseHelper.getTablesRef().child(currentTable.zone + "_" + currentTable.name).setValue(currentTable, (error, ref) -> {
                    if (error == null) {
                        Log.d("Table", "Table saved successfully: " + currentTable.name + ", inUse=" + currentTable.inUse);
                    } else {
                        Log.e("Table", "Error saving table: " + error.getMessage());
                    }
                });
            } catch (Exception e) {
                Log.e("Table", "Exception saving table: " + e.getMessage(), e);
            }
        });
    }

    private void mergeNewItems(List<Product> newItems) {
        for (Product newItem : newItems) {
            boolean found = false;
            for (Product cartItem : cartList) {
                String cartNote = cartItem.getNote() != null ? cartItem.getNote().trim() : "";
                String newNote = newItem.getNote() != null ? newItem.getNote().trim() : "";
                if (cartItem.getName().equals(newItem.getName()) && cartNote.equalsIgnoreCase(newNote)) {
                    cartItem.setQuantity(cartItem.getQuantity() + newItem.getQuantity());
                    found = true;
                    break;
                }
            }
            if (!found) cartList.add(newItem);
        }
    }

    private void setupRecyclerView() {
        CartAdapter cartAdapter = new CartAdapter(cartList);
        cartAdapter.setOnCartChangeListener(this::updateTotalDisplay);
        rvCart.setLayoutManager(new LinearLayoutManager(this));
        rvCart.setAdapter(cartAdapter);
    }

    private int calculateTotal() {
        int total = 0;
        for (Product p : cartList) total += (p.getPrice() * p.getQuantity());
        return total;
    }

    private void updateTotalDisplay() {
        int total = calculateTotal();
        tvTotalPrice.setText(new DecimalFormat("#,###đ").format(total));
        btnPayment.setVisibility(total > 0 ? View.VISIBLE : View.GONE);
    }

    private void returnToMain() {
        Intent intent = new Intent(this, TableListActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        intent.putExtra("USER_ROLE", userRole);
        startActivity(intent);
        finish();
    }

    private String generateOrderCode() {
        String timePart = new SimpleDateFormat("yyMMddHHmmss", Locale.getDefault()).format(new Date());
        int randomPart = new Random().nextInt(900) + 100;
        return "HD" + timePart + randomPart;
    }

    private void setupKitchenNotificationSync() {
        FirebaseHelper.getKitchenOrdersRef().addChildEventListener(new ChildEventListener() {
            @Override public void onChildAdded(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override
            public void onChildChanged(@NonNull DataSnapshot snapshot, @Nullable String p) {
                if (kitchenNotifFirstLoad) return;
                try {
                    KitchenOrderEntity order = snapshot.getValue(KitchenOrderEntity.class);
                    if (order != null && order.isDone) {
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            playOnlineOrderSound();
                            new AlertDialog.Builder(OrderActivity.this)
                                    .setTitle("Bếp báo xong món")
                                    .setMessage("Bếp đã hoàn thành đơn bàn: " + order.tableName)
                                    .setPositiveButton("Xác nhận", (dialog, which) -> {
                                        dialog.dismiss();
                                    })
                                    .setIcon(android.R.drawable.ic_dialog_info)
                                    .setCancelable(false)
                                    .show();
                        });
                    }
                } catch (Exception e) {}
            }
            @Override public void onChildRemoved(@NonNull DataSnapshot s) {}
            @Override public void onChildMoved(@NonNull DataSnapshot s, @Nullable String p) {}
            @Override public void onCancelled(@NonNull DatabaseError e) {}
        });
        
        FirebaseHelper.getKitchenOrdersRef().addListenerForSingleValueEvent(new ValueEventListener() {
            @Override public void onDataChange(@NonNull DataSnapshot s) { kitchenNotifFirstLoad = false; }
            @Override public void onCancelled(@NonNull DatabaseError e) { kitchenNotifFirstLoad = false; }
        });
    }

    private void playOnlineOrderSound() {
        try {
            Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            Ringtone ringtone = RingtoneManager.getRingtone(getApplicationContext(), notification);
            ringtone.play();
        } catch (Exception ignored) {}
    }
}

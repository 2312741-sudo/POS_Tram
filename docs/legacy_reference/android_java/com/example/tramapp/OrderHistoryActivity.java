package com.example.tramapp;

import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.tabs.TabLayout;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.ValueEventListener;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class OrderHistoryActivity extends AppCompatActivity {

    private RecyclerView rvHistory;
    private OrderHistoryDao historyDao;
    private final List<OrderHistoryEntity> allHistoryList = new ArrayList<>();
    private final List<OrderHistoryEntity> filteredHistoryList = new ArrayList<>();
    private HistoryAdapter adapter;
    private String userRole = "STAFF";

    private View scrollReport;
    private View rowInvoices, rowAvg, rowTotal, rowCash, rowTransfer;
    private TabLayout tabPeriod, tabMainType;
    
    private Calendar selectedDate = Calendar.getInstance();
    private TextView tvSelectedDate;
    private final SimpleDateFormat dayFormat = new SimpleDateFormat("dd/MM/yyyy", Locale.getDefault());
    private final SimpleDateFormat monthFormat = new SimpleDateFormat("MM/yyyy", Locale.getDefault());
    private final SimpleDateFormat yearFormat = new SimpleDateFormat("yyyy", Locale.getDefault());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_order_history);

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", Context.MODE_PRIVATE);
        userRole = prefs.getString("USER_ROLE", "STAFF");

        Toolbar toolbar = findViewById(R.id.toolbar_history);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            toolbar.setNavigationOnClickListener(v -> finish());
        }

        initViews();
        setupRecyclerView();
        setupFirebaseSync();
        loadHistory();
    }

    private void initViews() {
        rvHistory = findViewById(R.id.rv_order_history);
        historyDao = AppDatabase.getInstance(this).orderHistoryDao();
        
        tabMainType = findViewById(R.id.tab_main_type);
        tabPeriod = findViewById(R.id.tab_period);
        tvSelectedDate = findViewById(R.id.tv_selected_date);
        ImageButton btnPrev = findViewById(R.id.btn_prev_date);
        ImageButton btnNext = findViewById(R.id.btn_next_date);
        scrollReport = findViewById(R.id.scroll_report);

        tabMainType.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                if (tab.getPosition() == 0) {
                    rvHistory.setVisibility(View.VISIBLE);
                    scrollReport.setVisibility(View.GONE);
                } else {
                    if ("MANAGER".equalsIgnoreCase(userRole)) {
                        rvHistory.setVisibility(View.GONE);
                        scrollReport.setVisibility(View.VISIBLE);
                    } else {
                        Toast.makeText(OrderHistoryActivity.this, "Chỉ Quản lý mới có thể xem báo cáo!", Toast.LENGTH_SHORT).show();
                        tabMainType.getTabAt(0).select();
                    }
                }
            }
            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });

        tabPeriod.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                updateDateDisplay();
                applyFilter();
            }
            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });

        btnPrev.setOnClickListener(v -> { changeDate(-1); applyFilter(); });
        btnNext.setOnClickListener(v -> { changeDate(1); applyFilter(); });
        findViewById(R.id.layout_date_selector).setOnClickListener(v -> showDatePicker());

        rowInvoices = findViewById(R.id.row_invoice_count);
        rowAvg = findViewById(R.id.row_avg_revenue);
        rowTotal = findViewById(R.id.row_total_sales);
        rowCash = findViewById(R.id.row_cash);
        rowTransfer = findViewById(R.id.row_transfer);

        if ("MANAGER".equalsIgnoreCase(userRole)) {
            findViewById(R.id.btn_view_item_report).setOnClickListener(v -> showItemReportDialog());
            findViewById(R.id.btn_print_report).setOnClickListener(v -> printReport());
        }
        
        updateDateDisplay();
    }

    private void changeDate(int amount) {
        int pos = tabPeriod.getSelectedTabPosition();
        if (pos == 0) selectedDate.add(Calendar.DAY_OF_YEAR, amount);
        else if (pos == 1) selectedDate.add(Calendar.DAY_OF_YEAR, amount * 7);
        else if (pos == 2) selectedDate.add(Calendar.MONTH, amount);
        else if (pos == 3) selectedDate.add(Calendar.YEAR, amount);
        updateDateDisplay();
    }

    private void setupRow(View row, String label, String value, boolean showArrow) {
        if (row == null) return;
        TextView tvLabel = row.findViewById(R.id.txt_row_label);
        TextView tvValue = row.findViewById(R.id.txt_row_value);
        ImageView imgArrow = row.findViewById(R.id.img_arrow);
        if (tvLabel != null) tvLabel.setText(label);
        if (tvValue != null) tvValue.setText(value);
        if (imgArrow != null) imgArrow.setVisibility(showArrow ? View.VISIBLE : View.GONE);
    }

    private void showDatePicker() {
        new DatePickerDialog(this, (view, year, month, dayOfMonth) -> {
            selectedDate.set(Calendar.YEAR, year);
            selectedDate.set(Calendar.MONTH, month);
            selectedDate.set(Calendar.DAY_OF_MONTH, dayOfMonth);
            updateDateDisplay();
            applyFilter();
        }, selectedDate.get(Calendar.YEAR), selectedDate.get(Calendar.MONTH), selectedDate.get(Calendar.DAY_OF_MONTH)).show();
    }

    private void updateDateDisplay() {
        int pos = tabPeriod.getSelectedTabPosition();
        if (pos == 0) {
            Calendar today = Calendar.getInstance();
            if (isSameDay(selectedDate, today)) tvSelectedDate.setText("Hôm nay");
            else tvSelectedDate.setText(dayFormat.format(selectedDate.getTime()));
        } else if (pos == 1) {
            Calendar start = (Calendar) selectedDate.clone();
            start.add(Calendar.DAY_OF_YEAR, -6);
            tvSelectedDate.setText(dayFormat.format(start.getTime()) + " - " + dayFormat.format(selectedDate.getTime()));
        } else if (pos == 2) {
            tvSelectedDate.setText("Tháng " + monthFormat.format(selectedDate.getTime()));
        } else {
            tvSelectedDate.setText("Năm " + yearFormat.format(selectedDate.getTime()));
        }
    }

    private boolean isSameDay(Calendar cal1, Calendar cal2) {
        return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
               cal1.get(Calendar.DAY_OF_YEAR) == cal2.get(Calendar.DAY_OF_YEAR);
    }

    private void applyFilter() {
        filteredHistoryList.clear();
        int pos = tabPeriod.getSelectedTabPosition();
        for (OrderHistoryEntity order : allHistoryList) {
            Calendar orderCal = Calendar.getInstance();
            orderCal.setTimeInMillis(order.timestamp);
            boolean match = false;
            if (pos == 0) match = isSameDay(orderCal, selectedDate);
            else if (pos == 1) {
                long diff = selectedDate.getTimeInMillis() - orderCal.getTimeInMillis();
                long days = diff / (24 * 60 * 60 * 1000);
                match = days >= 0 && days < 7;
            } else if (pos == 2) {
                match = orderCal.get(Calendar.YEAR) == selectedDate.get(Calendar.YEAR) &&
                        orderCal.get(Calendar.MONTH) == selectedDate.get(Calendar.MONTH);
            } else if (pos == 3) {
                match = orderCal.get(Calendar.YEAR) == selectedDate.get(Calendar.YEAR);
            }
            if (match) filteredHistoryList.add(order);
        }
        runOnUiThread(() -> {
            adapter.notifyDataSetChanged();
            updateSummary();
        });
    }

    private void updateSummary() {
        if (!"MANAGER".equalsIgnoreCase(userRole)) return;
        int invoiceCount = filteredHistoryList.size();
        long totalSales = 0, cashAmount = 0, transferAmount = 0;
        for (OrderHistoryEntity order : filteredHistoryList) {
            totalSales += order.totalAmount;
            if (order.paymentMethod != null) {
                if (order.paymentMethod.contains("Chuyển khoản")) transferAmount += order.totalAmount;
                else cashAmount += order.totalAmount;
            }
        }
        long avgRevenue = (invoiceCount > 0) ? totalSales / invoiceCount : 0;
        DecimalFormat df = new DecimalFormat("#,###");
        setupRow(rowInvoices, "Số hóa đơn", String.valueOf(invoiceCount), false);
        setupRow(rowAvg, "Doanh thu TB/đơn", df.format(avgRevenue) + "đ", false);
        setupRow(rowTotal, "Thu bán hàng", df.format(totalSales) + "đ", false);
        setupRow(rowCash, "Tiền mặt", df.format(cashAmount) + "đ", false);
        setupRow(rowTransfer, "Chuyển khoản", df.format(transferAmount) + "đ", false);
    }

    private void printReport() {
        if (filteredHistoryList.isEmpty()) {
            Toast.makeText(this, "Không có dữ liệu để in!", Toast.LENGTH_SHORT).show();
            return;
        }

        SharedPreferences prefs = getSharedPreferences("TramAppPrefs", MODE_PRIVATE);
        String printerIp = prefs.getString("BILL_PRINTER_IP", "");
        if (printerIp.isEmpty()) {
            Toast.makeText(this, "Chưa cài đặt IP máy in!", Toast.LENGTH_SHORT).show();
            return;
        }

        EscPosPrinter.ReportData report = new EscPosPrinter.ReportData();
        report.period = tvSelectedDate.getText().toString();
        report.invoiceCount = filteredHistoryList.size();
        
        long total = 0, cash = 0, transfer = 0;
        Map<String, Integer> itemsMap = new HashMap<>();
        Gson gson = new Gson();
        Type type = new TypeToken<ArrayList<Product>>(){}.getType();

        for (OrderHistoryEntity order : filteredHistoryList) {
            total += order.totalAmount;
            if (order.paymentMethod != null && order.paymentMethod.contains("Chuyển khoản")) transfer += order.totalAmount;
            else cash += order.totalAmount;

            try {
                ArrayList<Product> items = gson.fromJson(order.itemsJson, type);
                for (Product p : items) {
                    itemsMap.put(p.getName(), itemsMap.getOrDefault(p.getName(), 0) + p.getQuantity());
                }
            } catch (Exception ignored) {}
        }

        report.totalSales = total;
        report.cashAmount = cash;
        report.transferAmount = transfer;
        
        List<Map.Entry<String, Integer>> sortedItems = new ArrayList<>(itemsMap.entrySet());
        Collections.sort(sortedItems, (a, b) -> b.getValue().compareTo(a.getValue()));
        report.itemStats = sortedItems;

        EscPosPrinter.printReportDirect(printerIp, report);
        Toast.makeText(this, "Đang gửi lệnh in báo cáo...", Toast.LENGTH_SHORT).show();
    }

    private void showItemReportDialog() {
        Map<String, Integer> itemMap = new HashMap<>();
        Gson gson = new Gson();
        Type type = new TypeToken<ArrayList<Product>>(){}.getType();
        for (OrderHistoryEntity order : filteredHistoryList) {
            try {
                ArrayList<Product> items = gson.fromJson(order.itemsJson, type);
                for (Product p : items) itemMap.put(p.getName(), itemMap.getOrDefault(p.getName(), 0) + p.getQuantity());
            } catch (Exception ignored) {}
        }
        View view = LayoutInflater.from(this).inflate(R.layout.dialog_item_report, null);
        LinearLayout container = view.findViewById(R.id.container_items);
        List<String> sortedNames = new ArrayList<>(itemMap.keySet());
        Collections.sort(sortedNames, (a, b) -> itemMap.get(b).compareTo(itemMap.get(a)));
        for (String name : sortedNames) {
            View row = LayoutInflater.from(this).inflate(R.layout.item_report_row, container, false);
            ((TextView)row.findViewById(R.id.txt_row_label)).setText(name);
            ((TextView)row.findViewById(R.id.txt_row_value)).setText(String.valueOf(itemMap.get(name)));
            container.addView(row);
        }
        new AlertDialog.Builder(this).setTitle("Hàng hóa đã bán").setView(view).setPositiveButton("Đóng", null).show();
    }

    private void setupRecyclerView() {
        adapter = new HistoryAdapter(filteredHistoryList);
        rvHistory.setLayoutManager(new LinearLayoutManager(this));
        rvHistory.setAdapter(adapter);
    }

    private void setupFirebaseSync() {
        FirebaseHelper.getHistoryRef().addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                List<OrderHistoryEntity> fbHistory = new ArrayList<>();
                for (DataSnapshot ds : snapshot.getChildren()) {
                    OrderHistoryEntity item = ds.getValue(OrderHistoryEntity.class);
                    if (item != null) { item.firebaseKey = ds.getKey(); fbHistory.add(item); }
                }
                allHistoryList.clear(); allHistoryList.addAll(fbHistory); Collections.reverse(allHistoryList);
                applyFilter();
            }
            @Override public void onCancelled(@NonNull DatabaseError error) {}
        });
    }

    private void loadHistory() {
        AppExecutors.getInstance().getDiskIO().execute(() -> {
            List<OrderHistoryEntity> local = historyDao.getAllHistory();
            if (local != null) runOnUiThread(() -> {
                if (allHistoryList.isEmpty()) { allHistoryList.addAll(local); Collections.reverse(allHistoryList); applyFilter(); }
            });
        });
    }

    private void showDetailDialog(OrderHistoryEntity history) {
        Dialog dialog = new Dialog(this);
        dialog.setContentView(R.layout.dialog_history_detail);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }
        TextView txtTitle = dialog.findViewById(R.id.txt_detail_title);
        TextView txtTotal = dialog.findViewById(R.id.txt_detail_total);
        RecyclerView rvItems = dialog.findViewById(R.id.rv_history_items);
        txtTitle.setText("Hóa đơn: " + (history.orderCode != null ? history.orderCode : "#" + history.id));
        txtTotal.setText("Bàn " + history.tableName + " - Tổng: " + new DecimalFormat("#,###").format(history.totalAmount) + "đ");
        try {
            ArrayList<Product> productList = new Gson().fromJson(history.itemsJson, new TypeToken<ArrayList<Product>>(){}.getType());
            CartAdapter detailAdapter = new CartAdapter(productList);
            detailAdapter.setHistoryMode(true); 
            rvItems.setLayoutManager(new LinearLayoutManager(this));
            rvItems.setAdapter(detailAdapter);
        } catch (Exception ignored) {}
        dialog.findViewById(R.id.btn_close_detail).setOnClickListener(v -> dialog.dismiss());
        dialog.show();
    }

    private void showDeleteConfirm(OrderHistoryEntity history) {
        new AlertDialog.Builder(this).setTitle("Xóa hóa đơn").setMessage("Hành động này không thể hoàn tác.")
                .setPositiveButton("Xóa", (dialog, which) -> {
                    AppExecutors.getInstance().getDiskIO().execute(() -> {
                        historyDao.deleteHistory(history);
                        if (history.firebaseKey != null) FirebaseHelper.getHistoryRef().child(history.firebaseKey).removeValue();
                        runOnUiThread(() -> { allHistoryList.remove(history); applyFilter(); });
                    });
                }).setNegativeButton("Hủy", null).show();
    }

    private class HistoryAdapter extends RecyclerView.Adapter<HistoryAdapter.VH> {
        private final List<OrderHistoryEntity> list;
        public HistoryAdapter(List<OrderHistoryEntity> list) { this.list = list; }
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup p, int t) {
            return new VH(LayoutInflater.from(p.getContext()).inflate(R.layout.item_history_invoice, p, false));
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            OrderHistoryEntity item = list.get(pos);
            h.txtCode.setText(item.orderCode != null ? item.orderCode : "#" + item.id);
            h.txtSub.setText("Bàn " + item.tableName + " - " + new DecimalFormat("#,###").format(item.totalAmount) + "đ");
            h.txtTime.setText(new SimpleDateFormat("HH:mm dd/MM", Locale.getDefault()).format(new Date(item.timestamp)) + " [" + item.paymentMethod + "]");
            h.layoutInfo.setOnClickListener(v -> showDetailDialog(item));
            h.btnDelete.setVisibility("MANAGER".equalsIgnoreCase(userRole) ? View.VISIBLE : View.GONE);
            h.btnDelete.setOnClickListener(v -> showDeleteConfirm(item));
        }
        @Override public int getItemCount() { return list.size(); }
        class VH extends RecyclerView.ViewHolder {
            TextView txtCode, txtSub, txtTime; View layoutInfo; ImageButton btnDelete;
            VH(View v) { super(v); 
                txtCode = v.findViewById(R.id.txt_invoice_code); txtSub = v.findViewById(R.id.txt_invoice_sub);
                txtTime = v.findViewById(R.id.txt_invoice_time); layoutInfo = v.findViewById(R.id.layout_info);
                btnDelete = v.findViewById(R.id.btn_delete_history_item);
            }
        }
    }
}

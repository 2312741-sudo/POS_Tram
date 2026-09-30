package com.example.tramapp;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class KitchenOrderAdapter extends RecyclerView.Adapter<KitchenOrderAdapter.KitchenVH> {

    private List<KitchenOrderEntity> orders;
    private OnOrderActionListener listener;

    public interface OnOrderActionListener {
        void onDone(KitchenOrderEntity order);
        void onPrint(KitchenOrderEntity order);
    }

    public KitchenOrderAdapter(List<KitchenOrderEntity> orders, OnOrderActionListener listener) {
        this.orders = orders;
        this.listener = listener;
    }

    @NonNull
    @Override
    public KitchenVH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_kitchen_order, parent, false);
        return new KitchenVH(v);
    }

    @Override
    public void onBindViewHolder(@NonNull KitchenVH holder, int position) {
        KitchenOrderEntity order = orders.get(position);
        if (order == null) return;

        holder.txtTable.setText("Bàn: " + (order.tableName != null ? order.tableName : "N/A"));
        
        SimpleDateFormat sdf = new SimpleDateFormat("HH:mm", Locale.getDefault());
        holder.txtTime.setText(sdf.format(order.timestamp));

        // Parse itemsJson an toàn
        StringBuilder sb = new StringBuilder();
        try {
            if (order.itemsJson != null && !order.itemsJson.isEmpty()) {
                Gson gson = new Gson();
                Type type = new TypeToken<ArrayList<Product>>() {}.getType();
                ArrayList<Product> products = gson.fromJson(order.itemsJson, type);
                
                if (products != null) {
                    for (Product p : products) {
                        sb.append("• ").append(p.getName()).append(" x").append(p.getQuantity()).append("\n");
                        if (p.getNote() != null && !p.getNote().trim().isEmpty()) {
                            sb.append("  ↳ ").append(p.getNote()).append("\n");
                        }
                    }
                }
            }
        } catch (Exception e) {
            sb.append("Lỗi dữ liệu món ăn");
        }
        
        String itemsText = sb.toString().trim();
        holder.txtItems.setText(itemsText.isEmpty() ? "Không có món" : itemsText);

        holder.btnDone.setOnClickListener(v -> {
            if (listener != null) listener.onDone(order);
        });

        holder.btnPrint.setOnClickListener(v -> {
            if (listener != null) listener.onPrint(order);
        });
    }

    @Override
    public int getItemCount() { return orders != null ? orders.size() : 0; }

    public static class KitchenVH extends RecyclerView.ViewHolder {
        TextView txtTable, txtTime, txtItems;
        Button btnDone, btnPrint;
        public KitchenVH(@NonNull View itemView) {
            super(itemView);
            txtTable = itemView.findViewById(R.id.txt_kitchen_table);
            txtTime = itemView.findViewById(R.id.txt_kitchen_time);
            txtItems = itemView.findViewById(R.id.txt_kitchen_items);
            btnDone = itemView.findViewById(R.id.btn_done_order);
            btnPrint = itemView.findViewById(R.id.btn_print_kitchen);
        }
    }
}
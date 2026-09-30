package com.example.tramapp;

import android.graphics.Color;
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
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class OnlineOrderAdapter extends RecyclerView.Adapter<OnlineOrderAdapter.OrderViewHolder> {

    private List<OnlineOrderEntity> orderList;
    private OnlineOrderInteractionListener listener;
    private static final SimpleDateFormat TIME_FMT = new SimpleDateFormat("HH:mm dd/MM", Locale.getDefault());

    public interface OnlineOrderInteractionListener {
        void onConfirmOrder(OnlineOrderEntity order);
        void onCancelOrder(OnlineOrderEntity order);
        void onViewDetails(OnlineOrderEntity order);
    }

    public OnlineOrderAdapter(List<OnlineOrderEntity> orderList, OnlineOrderInteractionListener listener) {
        this.orderList = orderList;
        this.listener = listener;
    }

    public void updateData(List<OnlineOrderEntity> newOrderList) {
        this.orderList.clear();
        this.orderList.addAll(newOrderList);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public OrderViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_online_order, parent, false);
        return new OrderViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull OrderViewHolder holder, int position) {
        OnlineOrderEntity order = orderList.get(position);

        // Bàn
        holder.txtTableInfo.setText(String.format("Bàn: %s - %s",
                order.tableName != null ? order.tableName : "?",
                order.tableZone != null ? order.tableZone : "?"));

        // Loại đơn badge
        boolean isCallWaiter = "CALL_WAITER".equalsIgnoreCase(order.type);
        if (isCallWaiter) {
            holder.txtOrderType.setText("🔔 GỌI PHỤC VỤ");
            holder.txtOrderType.setBackgroundResource(R.drawable.badge_bg_orange);
        } else {
            holder.txtOrderType.setText("📦 ĐƠN HÀNG");
            holder.txtOrderType.setBackgroundResource(R.drawable.badge_bg_green);
        }

        // Thời gian
        if (holder.txtOrderTime != null && order.timestamp > 0) {
            holder.txtOrderTime.setText(TIME_FMT.format(new Date(order.timestamp)));
        }

        // Nội dung món
        holder.txtItems.setText(formatItemsJson(order.itemsJson, isCallWaiter));

        // Xác định trạng thái
        boolean isPending = order.status == null
                || order.status.isEmpty()
                || "PENDING".equalsIgnoreCase(order.status)
                || "null".equalsIgnoreCase(order.status);

        // Hiện/ẩn nút theo trạng thái
        if (isPending) {
            holder.btnView.setVisibility(View.VISIBLE);
            holder.btnCancel.setVisibility(View.VISIBLE);
            holder.btnConfirm.setVisibility(View.VISIBLE);
            holder.btnView.setEnabled(true);
            holder.btnCancel.setEnabled(true);
            holder.btnConfirm.setEnabled(true);
            holder.btnView.setAlpha(1f);
            holder.btnCancel.setAlpha(1f);
            holder.btnConfirm.setAlpha(1f);
        } else {
            // Đơn đã xử lý - chỉ xem
            holder.btnView.setVisibility(View.VISIBLE);
            holder.btnCancel.setVisibility(View.GONE);
            holder.btnConfirm.setVisibility(View.GONE);
            holder.btnView.setEnabled(true);
            holder.btnView.setAlpha(1f);
        }

        // Text nút Xác nhận theo loại
        if (isCallWaiter) {
            holder.btnConfirm.setText("Đã nhận");
        } else {
            holder.btnConfirm.setText("Xác nhận");
        }

        holder.btnView.setOnClickListener(v -> {
            if (listener != null) listener.onViewDetails(order);
        });

        holder.btnCancel.setOnClickListener(v -> {
            if (listener != null) listener.onCancelOrder(order);
        });

        holder.btnConfirm.setOnClickListener(v -> {
            if (listener != null) listener.onConfirmOrder(order);
        });
    }

    private String formatItemsJson(String json, boolean isCallWaiter) {
        if (isCallWaiter) return "Khách đang gọi nhân viên phục vụ...";

        if (json == null || json.trim().isEmpty() || "null".equalsIgnoreCase(json.trim())) {
            return "Không có món";
        }

        try {
            Gson gson = new Gson();
            Type type = new TypeToken<ArrayList<Map<String, Object>>>() {}.getType();
            ArrayList<Map<String, Object>> items = gson.fromJson(json, type);

            if (items == null || items.isEmpty()) return "Không có món";

            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < items.size(); i++) {
                Map<String, Object> item = items.get(i);
                String name = item.get("name") == null ? "Món" : String.valueOf(item.get("name"));
                int quantity = 0;
                Object q = item.get("quantity");
                if (q instanceof Number) {
                    quantity = ((Number) q).intValue();
                } else if (q != null) {
                    try { quantity = Integer.parseInt(String.valueOf(q)); } catch (Exception ignored) {}
                }
                sb.append("• ").append(name).append(" x").append(quantity);
                String note = item.get("note") == null ? "" : String.valueOf(item.get("note")).trim();
                if (!note.isEmpty()) {
                    sb.append(" (").append(note).append(")");
                }
                if (i < items.size() - 1) sb.append("\n");
            }
            return sb.toString();
        } catch (Exception e) {
            return "Lỗi hiển thị món";
        }
    }

    @Override
    public int getItemCount() {
        return orderList.size();
    }

    public static class OrderViewHolder extends RecyclerView.ViewHolder {
        TextView txtTableInfo, txtOrderType, txtItems, txtOrderTime;
        Button btnView, btnCancel, btnConfirm;

        public OrderViewHolder(@NonNull View itemView) {
            super(itemView);
            txtTableInfo = itemView.findViewById(R.id.txt_order_table_info);
            txtOrderType = itemView.findViewById(R.id.txt_order_type);
            txtItems = itemView.findViewById(R.id.txt_order_items);
            txtOrderTime = itemView.findViewById(R.id.txt_order_time);
            btnView = itemView.findViewById(R.id.btn_order_view);
            btnCancel = itemView.findViewById(R.id.btn_order_cancel);
            btnConfirm = itemView.findViewById(R.id.btn_order_confirm);
        }
    }
}

package com.example.tramapp;

import android.content.Context;
import android.graphics.Color;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.PopupMenu;
import android.widget.TextView;
import androidx.annotation.NonNull;
import com.google.android.material.card.MaterialCardView;
import androidx.recyclerview.widget.RecyclerView;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.List;

public class TableAdapter extends RecyclerView.Adapter<TableAdapter.TableViewHolder> {

    private List<TableEntity> tableList;

    public interface OnTableInteractionListener {
        void onTableClick(TableEntity table);
        void onTableLongClick(TableEntity table);
        void onQRCodeClick(TableEntity table);
        void onPrintQRClick(TableEntity table);
        void onDeleteClick(TableEntity table);
    }

    private OnTableInteractionListener listener;

    public TableAdapter(List<TableEntity> tableList, OnTableInteractionListener listener) {
        this.tableList = tableList;
        this.listener = listener;
    }

    public void updateData(List<TableEntity> newTableList) {
        this.tableList.clear();
        this.tableList.addAll(newTableList);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public TableViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_table_card, parent, false);
        return new TableViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull TableViewHolder holder, int position) {
        TableEntity table = tableList.get(position);
        holder.txtTableName.setText(table.name);

        if (table.inUse) {
            holder.cardTable.setCardBackgroundColor(Color.parseColor("#FFF3E0"));
            holder.cardTable.setStrokeColor(Color.parseColor("#E65100"));
            holder.cardTable.setStrokeWidth(4);
            holder.statusIndicator.setBackgroundTintList(
                    android.content.res.ColorStateList.valueOf(Color.parseColor("#F44336")));

            int total = calculateTableTotal(table.currentOrderJson);
            if (total > 0) {
                holder.txtTotal.setVisibility(View.VISIBLE);
                holder.txtTotal.setText(new DecimalFormat("#,###").format(total) + "đ");
            } else {
                holder.txtTotal.setVisibility(View.GONE);
            }
        } else {
            holder.cardTable.setCardBackgroundColor(Color.WHITE);
            holder.cardTable.setStrokeColor(Color.parseColor("#E0E0E0"));
            holder.cardTable.setStrokeWidth(1);
            holder.statusIndicator.setBackgroundTintList(
                    android.content.res.ColorStateList.valueOf(Color.parseColor("#4CAF50")));
            holder.txtTotal.setVisibility(View.GONE);
        }

        // Click thường → mở order
        holder.itemView.setOnClickListener(v -> {
            if (listener != null) listener.onTableClick(table);
        });

        // Long-press → hiện popup menu
        holder.itemView.setOnLongClickListener(v -> {
            showTableContextMenu(v.getContext(), v, table);
            return true;
        });
    }

    private void showTableContextMenu(Context context, View anchorView, TableEntity table) {
        PopupMenu popup = new PopupMenu(context, anchorView);
        popup.getMenu().add(0, 1, 0, "📋 Xem mã QR bàn");
        popup.getMenu().add(0, 2, 1, "🗑️ Xóa bàn");

        popup.setOnMenuItemClickListener(item -> {
            if (listener == null) return false;
            int id = item.getItemId();
            if (id == 1) {
                listener.onQRCodeClick(table);
            } else if (id == 2) {
                listener.onDeleteClick(table);
            }
            return true;
        });
        popup.show();
    }

    private int calculateTableTotal(String json) {
        if (json == null || json.isEmpty()) return 0;
        try {
            Gson gson = new Gson();
            Type type = new TypeToken<ArrayList<Product>>() {}.getType();
            ArrayList<Product> products = gson.fromJson(json, type);
            int sum = 0;
            if (products != null) {
                for (Product p : products) {
                    sum += (p.getPrice() * p.getQuantity());
                }
            }
            return sum;
        } catch (Exception e) {
            return 0;
        }
    }

    @Override
    public int getItemCount() {
        return tableList.size();
    }

    public static class TableViewHolder extends RecyclerView.ViewHolder {
        TextView txtTableName, txtTotal;
        MaterialCardView cardTable;
        View statusIndicator;

        public TableViewHolder(@NonNull View itemView) {
            super(itemView);
            txtTableName = itemView.findViewById(R.id.txt_table_name);
            txtTotal = itemView.findViewById(R.id.txt_table_total);
            cardTable = itemView.findViewById(R.id.card_table);
            statusIndicator = itemView.findViewById(R.id.view_status_indicator);
        }
    }
}
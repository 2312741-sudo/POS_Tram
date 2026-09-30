package com.example.tramapp;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.recyclerview.widget.RecyclerView;
import java.text.DecimalFormat;
import java.util.List;

public class CartAdapter extends RecyclerView.Adapter<CartAdapter.CartViewHolder> {

    private final List<Product> cartList;
    private OnCartChangeListener listener;
    private boolean isHistoryMode = false;

    public interface OnCartChangeListener {
        void onQuantityChanged();
    }

    public CartAdapter(List<Product> cartList) {
        this.cartList = cartList;
    }

    public void setHistoryMode(boolean historyMode) {
        this.isHistoryMode = historyMode;
    }

    public void setOnCartChangeListener(OnCartChangeListener listener) {
        this.listener = listener;
    }

    @NonNull
    @Override
    public CartViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_product_list_row, parent, false);
        return new CartViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull CartViewHolder holder, int position) {
        Product product = cartList.get(position);
        Context context = holder.itemView.getContext();

        holder.tvName.setText(product.getName());
        holder.tvQuantity.setText(String.valueOf(product.getQuantity()));
        holder.tvUnit.setText("/ " + product.getUnit());

        DecimalFormat formatter = new DecimalFormat("#,###");
        int totalPrice = product.getPrice() * product.getQuantity();
        holder.tvPrice.setText(formatter.format(totalPrice) + "đ");

        if (product.getNote() != null && !product.getNote().isEmpty()) {
            holder.tvNote.setText(product.getNote());
            holder.tvNote.setVisibility(View.VISIBLE);
        } else {
            holder.tvNote.setVisibility(View.GONE);
        }

        // Load Image (Base64 first, then Resource Name)
        if (product.getImageBase64() != null && !product.getImageBase64().isEmpty()) {
            try {
                byte[] decodedString = Base64.decode(product.getImageBase64(), Base64.DEFAULT);
                Bitmap decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.length);
                holder.imgProduct.setImageBitmap(decodedByte);
            } catch (Exception e) {
                holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
            }
        } else {
            String imgName = product.getImageResourceName();
            if (imgName != null && !imgName.isEmpty()) {
                int resId = context.getResources().getIdentifier(imgName, "drawable", context.getPackageName());
                if (resId != 0) {
                    holder.imgProduct.setImageResource(resId);
                } else {
                    holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
                }
            } else {
                holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
            }
        }

        // Luôn ẩn nút thêm ban đầu và nút xóa trong Giỏ hàng/Lịch sử
        holder.btnAddInitial.setVisibility(View.GONE);
        holder.btnDelete.setVisibility(View.GONE);
        
        // Hiện bộ điều khiển số lượng
        holder.containerOrder.setVisibility(View.VISIBLE);

        if (isHistoryMode) {
            holder.btnPlus.setVisibility(View.GONE);
            holder.btnMinus.setVisibility(View.GONE);
            holder.itemView.setOnClickListener(null);
        } else {
            holder.btnPlus.setVisibility(View.VISIBLE);
            holder.btnMinus.setVisibility(View.VISIBLE);
            holder.itemView.setOnClickListener(v -> {
                showNoteDialog(context, product, holder);
            });
        }

        holder.btnPlus.setOnClickListener(v -> {
            product.setQuantity(product.getQuantity() + 1);
            notifyItemChanged(holder.getAdapterPosition());
            if (listener != null) listener.onQuantityChanged();
        });

        holder.btnMinus.setOnClickListener(v -> {
            int currentPos = holder.getAdapterPosition();
            if (currentPos == RecyclerView.NO_POSITION) return;

            if (product.getQuantity() > 1) {
                product.setQuantity(product.getQuantity() - 1);
                notifyItemChanged(currentPos);
            } else {
                cartList.remove(currentPos);
                notifyItemRemoved(currentPos);
                notifyItemRangeChanged(currentPos, cartList.size());
            }
            if (listener != null) listener.onQuantityChanged();
        });
    }

    private void showNoteDialog(Context context, Product product, CartViewHolder holder) {
        AlertDialog.Builder builder = new AlertDialog.Builder(context);
        builder.setTitle("Ghi chú cho " + product.getName());

        final EditText input = new EditText(context);
        input.setText(product.getNote());
        input.setHint("Nhập ghi chú (vd: không đá, ít đường...)");
        builder.setView(input);

        builder.setPositiveButton("Lưu", (dialog, which) -> {
            product.setNote(input.getText().toString());
            if (product.getNote() != null && !product.getNote().isEmpty()) {
                holder.tvNote.setText(product.getNote());
                holder.tvNote.setVisibility(View.VISIBLE);
            } else {
                holder.tvNote.setVisibility(View.GONE);
            }
        });
        builder.setNegativeButton("Hủy", (dialog, which) -> dialog.cancel());

        builder.show();
    }

    @Override
    public int getItemCount() { return cartList.size(); }

    public static class CartViewHolder extends RecyclerView.ViewHolder {
        TextView tvName, tvPrice, tvQuantity, tvUnit, tvNote;
        ImageButton btnPlus, btnMinus, btnAddInitial, btnDelete;
        ImageView imgProduct;
        View containerOrder;

        public CartViewHolder(@NonNull View itemView) {
            super(itemView);
            tvName = itemView.findViewById(R.id.txt_product_name);
            tvUnit = itemView.findViewById(R.id.txt_product_unit);
            tvPrice = itemView.findViewById(R.id.txt_product_price);
            tvQuantity = itemView.findViewById(R.id.txt_quantity);
            tvNote = itemView.findViewById(R.id.txt_product_note);
            btnPlus = itemView.findViewById(R.id.btn_increase);
            btnMinus = itemView.findViewById(R.id.btn_decrease);
            btnAddInitial = itemView.findViewById(R.id.btn_add_item);
            btnDelete = itemView.findViewById(R.id.btn_delete_product);
            imgProduct = itemView.findViewById(R.id.img_product);
            containerOrder = itemView.findViewById(R.id.container_order_control);
        }
    }
}
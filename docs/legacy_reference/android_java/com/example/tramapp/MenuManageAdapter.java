package com.example.tramapp;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.text.DecimalFormat;
import java.util.List;

public class MenuManageAdapter extends RecyclerView.Adapter<MenuManageAdapter.MenuVH> {

    private List<ProductEntity> productList;
    private OnProductClickListener listener;

    public interface OnProductClickListener {
        void onProductClick(ProductEntity product);
        void onProductLongClick(ProductEntity product);
    }

    public MenuManageAdapter(List<ProductEntity> productList, OnProductClickListener listener) {
        this.productList = productList;
        this.listener = listener;
    }

    @NonNull
    @Override
    public MenuVH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_product_list_row, parent, false);
        return new MenuVH(v);
    }

    @Override
    public void onBindViewHolder(@NonNull MenuVH holder, int position) {
        ProductEntity p = productList.get(position);
        Context context = holder.itemView.getContext();
        
        holder.txtName.setText(p.name);
        holder.txtPrice.setText(new DecimalFormat("#,###").format(p.price) + "đ");
        holder.txtUnit.setText("/ " + p.unit);
        
        // Load Image
        if (p.imageBase64 != null && !p.imageBase64.isEmpty()) {
            try {
                byte[] decodedString = Base64.decode(p.imageBase64, Base64.DEFAULT);
                Bitmap decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.length);
                holder.imgProduct.setImageBitmap(decodedByte);
            } catch (Exception e) {
                holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
            }
        } else if (p.imageResourceName != null && !p.imageResourceName.isEmpty()) {
            int resId = context.getResources().getIdentifier(p.imageResourceName, "drawable", context.getPackageName());
            if (resId != 0) {
                holder.imgProduct.setImageResource(resId);
            } else {
                holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
            }
        } else {
            holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
        }
        
        // Chế độ Quản lý: Ẩn tất cả các nút thêm/tăng giảm, chỉ Hiện nút xóa
        holder.orderControl.setVisibility(View.GONE);
        holder.btnAddInitial.setVisibility(View.GONE);
        holder.btnDelete.setVisibility(View.VISIBLE);

        holder.btnDelete.setOnClickListener(v -> listener.onProductLongClick(p));
        holder.itemView.setOnClickListener(v -> listener.onProductClick(p));
    }

    @Override
    public int getItemCount() { return productList.size(); }

    public static class MenuVH extends RecyclerView.ViewHolder {
        TextView txtName, txtPrice, txtUnit;
        ImageView imgProduct;
        View orderControl;
        ImageButton btnDelete, btnAddInitial;

        public MenuVH(@NonNull View itemView) {
            super(itemView);
            txtName = itemView.findViewById(R.id.txt_product_name);
            txtPrice = itemView.findViewById(R.id.txt_product_price);
            txtUnit = itemView.findViewById(R.id.txt_product_unit);
            imgProduct = itemView.findViewById(R.id.img_product);
            orderControl = itemView.findViewById(R.id.container_order_control);
            btnDelete = itemView.findViewById(R.id.btn_delete_product);
            btnAddInitial = itemView.findViewById(R.id.btn_add_item);
        }
    }
}
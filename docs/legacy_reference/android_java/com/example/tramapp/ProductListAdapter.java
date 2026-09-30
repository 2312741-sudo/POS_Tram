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

public class ProductListAdapter extends RecyclerView.Adapter<ProductListAdapter.ProductViewHolder> {

    private List<Product> productList;
    private CartListener cartListener;

    public interface CartListener {
        void onAddToCart(Product product, int updatedTotalItems);
    }

    public ProductListAdapter(List<Product> productList, CartListener cartListener) {
        this.productList = productList;
        this.cartListener = cartListener;
    }

    @NonNull
    @Override
    public ProductViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_product_list_row, parent, false);
        return new ProductViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ProductViewHolder holder, int position) {
        Product currentProduct = productList.get(position);
        Context context = holder.itemView.getContext();

        holder.txtName.setText(currentProduct.getName());
        holder.txtUnit.setText("/ " + currentProduct.getUnit());

        DecimalFormat formatter = new DecimalFormat("#,###");
        holder.txtPrice.setText(formatter.format(currentProduct.getPrice()));

        if (currentProduct.getNote() != null && !currentProduct.getNote().isEmpty()) {
            holder.txtNote.setText(currentProduct.getNote());
            holder.txtNote.setVisibility(View.VISIBLE);
        } else {
            holder.txtNote.setVisibility(View.GONE);
        }
        
        // Load Image (Base64 first, then Resource Name)
        if (currentProduct.getImageBase64() != null && !currentProduct.getImageBase64().isEmpty()) {
            try {
                byte[] decodedString = Base64.decode(currentProduct.getImageBase64(), Base64.DEFAULT);
                Bitmap decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.length);
                holder.imgProduct.setImageBitmap(decodedByte);
            } catch (Exception e) {
                holder.imgProduct.setImageResource(R.drawable.ic_restaurant_menu);
            }
        } else {
            String imgName = currentProduct.getImageResourceName();
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

        int quantity = currentProduct.getQuantity();
        holder.txtQuantity.setText("x" + quantity);

        if (quantity > 0) {
            holder.btnMinus.setVisibility(View.VISIBLE);
            holder.txtQuantity.setVisibility(View.VISIBLE);
            holder.btnPlusInCart.setVisibility(View.VISIBLE);
            holder.btnAddInitial.setVisibility(View.GONE);
        } else {
            holder.btnMinus.setVisibility(View.GONE);
            holder.txtQuantity.setVisibility(View.GONE);
            holder.btnPlusInCart.setVisibility(View.GONE);
            holder.btnAddInitial.setVisibility(View.VISIBLE);
        }

        View.OnClickListener addAction = v -> {
            currentProduct.setQuantity(currentProduct.getQuantity() + 1);
            updateRowUI(holder, currentProduct);
            notifyCartTotal();
        };
        holder.btnAddInitial.setOnClickListener(addAction);
        holder.btnPlusInCart.setOnClickListener(addAction);

        holder.btnMinus.setOnClickListener(v -> {
            if (currentProduct.getQuantity() > 0) {
                currentProduct.setQuantity(currentProduct.getQuantity() - 1);
                updateRowUI(holder, currentProduct);
                notifyCartTotal();
            }
        });

        holder.itemView.setOnClickListener(v -> {
            showNoteDialog(context, currentProduct, holder);
        });
    }

    private void showNoteDialog(Context context, Product product, ProductViewHolder holder) {
        AlertDialog.Builder builder = new AlertDialog.Builder(context);
        builder.setTitle("Ghi chú cho " + product.getName());

        final EditText input = new EditText(context);
        input.setText(product.getNote());
        input.setHint("Nhập ghi chú (vd: không đá, ít đường...)");
        builder.setView(input);

        builder.setPositiveButton("Lưu", (dialog, which) -> {
            product.setNote(input.getText().toString());
            if (product.getNote() != null && !product.getNote().isEmpty()) {
                holder.txtNote.setText(product.getNote());
                holder.txtNote.setVisibility(View.VISIBLE);
            } else {
                holder.txtNote.setVisibility(View.GONE);
            }
        });
        builder.setNegativeButton("Hủy", (dialog, which) -> dialog.cancel());

        builder.show();
    }

    private void updateRowUI(ProductViewHolder holder, Product product) {
        int qty = product.getQuantity();
        holder.txtQuantity.setText("x" + qty);
        if (qty > 0) {
            holder.btnMinus.setVisibility(View.VISIBLE);
            holder.txtQuantity.setVisibility(View.VISIBLE);
            holder.btnPlusInCart.setVisibility(View.VISIBLE);
            holder.btnAddInitial.setVisibility(View.GONE);
        } else {
            holder.btnMinus.setVisibility(View.GONE);
            holder.txtQuantity.setVisibility(View.GONE);
            holder.btnPlusInCart.setVisibility(View.GONE);
            holder.btnAddInitial.setVisibility(View.VISIBLE);
        }
    }

    private void notifyCartTotal() {
        int total = 0;
        for (Product p : productList) total += p.getQuantity();
        if (cartListener != null) {
            cartListener.onAddToCart(null, total);
        }
    }

    @Override
    public int getItemCount() { return productList.size(); }

    public static class ProductViewHolder extends RecyclerView.ViewHolder {
        TextView txtName, txtUnit, txtPrice, txtQuantity, txtNote;
        ImageButton btnAddInitial, btnPlusInCart, btnMinus;
        ImageView imgProduct;

        public ProductViewHolder(@NonNull View itemView) {
            super(itemView);
            txtName = itemView.findViewById(R.id.txt_product_name);
            txtUnit = itemView.findViewById(R.id.txt_product_unit);
            txtPrice = itemView.findViewById(R.id.txt_product_price);
            txtQuantity = itemView.findViewById(R.id.txt_quantity);
            txtNote = itemView.findViewById(R.id.txt_product_note);
            btnAddInitial = itemView.findViewById(R.id.btn_add_item);
            btnPlusInCart = itemView.findViewById(R.id.btn_increase);
            btnMinus = itemView.findViewById(R.id.btn_decrease);
            imgProduct = itemView.findViewById(R.id.img_product);
        }
    }
}
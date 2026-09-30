import SwiftUI

struct ProductSelectionView: View {
    @ObservedObject var viewModel: OrderViewModel
    @State private var products: [Product] = []
    @State private var categories: [Category] = []
    @State private var selectedCategory: String? = nil
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ZoneChip(title: "Tất cả", isSelected: selectedCategory == nil) { selectedCategory = nil }
                        ForEach(categories) { cat in
                            ZoneChip(title: cat.name, isSelected: selectedCategory == cat.name) { selectedCategory = cat.name }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                List {
                    let filtered = selectedCategory == nil ? products : products.filter { $0.category == selectedCategory }
                    ForEach(filtered) { product in
                        HStack(spacing: 12) {
                            if let resourceName = product.imageResourceName, !resourceName.isEmpty {
                                Image(resourceName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(UIColor.systemGray5))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name).font(.headline)
                                Text("\(product.price)đ").font(.subheadline).foregroundColor(.orange)
                            }
                            Spacer()
                            
                            // Quantity Controls
                            let cartItem = viewModel.cart.first(where: { $0.id == product.id })
                            let cartQty = cartItem?.quantity ?? 0
                            
                            if cartQty > 0 {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        if let item = cartItem {
                                            viewModel.updateQuantity(for: item, delta: -1)
                                        }
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.title2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Text("\(cartQty)")
                                        .font(.headline)
                                        .frame(minWidth: 20)
                                    
                                    Button(action: {
                                        if let item = cartItem {
                                            viewModel.updateQuantity(for: item, delta: 1)
                                        } else {
                                            viewModel.addToCart(product: product)
                                        }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.title2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                Button(action: {
                                    viewModel.addToCart(product: product)
                                }) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.orange)
                                        .font(.title2)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                
                if !viewModel.cart.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Đã chọn \(viewModel.cart.reduce(0) { $0 + $1.quantity }) món")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.getTotalAmount())đ")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Text("XONG")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 120, height: 44)
                                    .background(Color.orange)
                                    .cornerRadius(22)
                                    .shadow(color: Color.orange.opacity(0.3), radius: 5, x: 0, y: 3)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 15)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .navigationTitle("Chọn món")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear {
                FirebaseManager.shared.listenToProducts { fetched in
                    DispatchQueue.main.async { self.products = fetched }
                }
                FirebaseManager.shared.listenToCategories { fetched in
                    DispatchQueue.main.async { self.categories = fetched }
                }
            }
        }
    }
}

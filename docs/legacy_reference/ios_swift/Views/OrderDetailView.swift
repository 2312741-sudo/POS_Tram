import SwiftUI

struct OrderDetailView: View {
    let table: Table
    @StateObject private var viewModel: OrderViewModel
    @State private var showingProductSelection = false
    @State private var showingPayment = false
    @State private var showingQR = false
    @Environment(\.presentationMode) var presentationMode
    
    init(table: Table) {
        self.table = table
        _viewModel = StateObject(wrappedValue: OrderViewModel(table: table))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Cart Items List
                if viewModel.cart.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "cart")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding()
                        Text("Chưa có món nào")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(viewModel.cart) { product in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.name).font(.headline)
                                    if !product.note.isEmpty {
                                        Text(product.note).font(.caption).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Text("\(product.quantity)").font(.headline).foregroundColor(.orange)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                // Bottom Card (Like Android)
                VStack(spacing: 20) {
                    HStack {
                        Text("Tổng thanh toán")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(viewModel.getTotalAmount())đ")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    HStack(spacing: 15) {
                        Button(action: {
                            viewModel.currentTable = table
                            viewModel.confirmOrder()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("LƯU BÀN")
                                .font(.headline)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            showingPayment = true
                        }) {
                            Text("THANH TOÁN")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.orange)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
            }
        }
        .navigationTitle("Bàn: \(table.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 15) {
                    Button(action: { showingQR = true }) {
                        Image(systemName: "qrcode")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    Button(action: { showingProductSelection = true }) {
                        Text("THÊM MÓN")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .sheet(isPresented: $showingProductSelection) {
            ProductSelectionView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPayment) {
            PaymentView(table: table, viewModel: viewModel)
        }
        .sheet(isPresented: $showingQR) {
            TableQRView(table: table)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseOrderDetails"))) { _ in
            presentationMode.wrappedValue.dismiss()
        }
        .onAppear {
            if viewModel.cart.isEmpty {
                showingProductSelection = true
            }
        }
    }
}

// Helper to round specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

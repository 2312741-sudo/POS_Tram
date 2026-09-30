import SwiftUI

struct ProductSale: Identifiable {
    var id: String
    var name: String
    var quantity: Int
    var totalPrice: Int
}

struct HistoryView: View {
    @State private var allHistory: [OrderHistory] = []
    @State private var filterMode: Int = 0 // 0: Hôm nay, 1: 7 Ngày, 2: Tháng này, 3: Tất cả
    @State private var viewMode: Int = 0 // 0: Đơn hàng, 1: Sản phẩm đã bán
    
    var filteredHistory: [OrderHistory] {
        let now = Date()
        return allHistory.filter { order in
            let orderDate = Date(timeIntervalSince1970: TimeInterval(order.timestamp) / 1000)
            if filterMode == 0 {
                return Calendar.current.isDateInToday(orderDate)
            } else if filterMode == 1 {
                if let diff = Calendar.current.dateComponents([.day], from: orderDate, to: now).day {
                    return diff <= 7
                }
            } else if filterMode == 2 {
                return Calendar.current.isDate(orderDate, equalTo: now, toGranularity: .month)
            }
            return true
        }
    }
    
    var totalSales: Int {
        var total = 0
        for order in filteredHistory { total += order.totalAmount }
        return total
    }
    
    var totalCash: Int {
        var total = 0
        for order in filteredHistory {
            if order.paymentMethod == "Tiền mặt" || order.paymentMethod == "Tiền mặt + CK" {
                total += order.totalAmount
            }
        }
        return total
    }
    
    var totalTransfer: Int {
        var total = 0
        for order in filteredHistory {
            if order.paymentMethod == "Chuyển khoản" {
                total += order.totalAmount
            }
        }
        return total
    }
    
    var productSales: [ProductSale] {
        var sales: [String: (name: String, quantity: Int, totalPrice: Int)] = [:]
        for order in filteredHistory {
            if let itemsData = order.itemsJson.data(using: .utf8),
               let items = try? JSONDecoder().decode([Product].self, from: itemsData) {
                for item in items {
                    let current = sales[item.name] ?? (name: item.name, quantity: 0, totalPrice: 0)
                    sales[item.name] = (
                        name: item.name,
                        quantity: current.quantity + item.quantity,
                        totalPrice: current.totalPrice + (item.price * item.quantity)
                    )
                }
            }
        }
        return sales.map { ProductSale(id: $0.key, name: $0.value.name, quantity: $0.value.quantity, totalPrice: $0.value.totalPrice) }
                    .sorted(by: { $0.quantity > $1.quantity })
    }
    
    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Thời gian", selection: $filterMode) {
                Text("Hôm nay").tag(0)
                Text("7 Ngày").tag(1)
                Text("Tháng này").tag(2)
                Text("Tất cả").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            .background(Color(UIColor.systemBackground))
            
            Picker("Xem theo", selection: $viewMode) {
                Text("Đơn hàng").tag(0)
                Text("Sản phẩm đã bán").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding([.horizontal, .bottom])
            .background(Color(UIColor.systemBackground))
            
            // Summary Board
            VStack(spacing: 10) {
                HStack {
                    Text("Tổng Doanh Thu:")
                    Spacer()
                    Text("\(totalSales)đ").bold().foregroundColor(.orange)
                }
                HStack {
                    Text("Tiền mặt:")
                    Spacer()
                    Text("\(totalCash)đ").foregroundColor(.green)
                }
                HStack {
                    Text("Chuyển khoản:")
                    Spacer()
                    Text("\(totalTransfer)đ").foregroundColor(.blue)
                }
                HStack {
                    Text("Số đơn:")
                    Spacer()
                    Text("\(filteredHistory.count)")
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding()
            
            if viewMode == 0 {
                List {
                    ForEach(filteredHistory) { order in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Bàn: \(order.tableName)").font(.headline)
                                Spacer()
                                Text("\(order.totalAmount)đ").bold().foregroundColor(.orange)
                            }
                            HStack {
                                Text(order.paymentMethod ?? "N/A").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(order.timestamp)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List {
                    ForEach(productSales) { sale in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sale.name).font(.headline)
                                Text("Doanh thu: \(sale.totalPrice)đ").font(.subheadline).foregroundColor(.orange)
                            }
                            Spacer()
                            Text("\(sale.quantity) cái").font(.headline).foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Báo cáo Lịch sử")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            FirebaseManager.shared.listenToHistory { fetched in
                DispatchQueue.main.async {
                    self.allHistory = fetched.sorted(by: { $0.timestamp > $1.timestamp })
                }
            }
        }
    }
}

struct QRCodeView: View {
    var body: some View {
        VStack {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding()
            Text("Quét mã để đặt món")
                .font(.headline)
        }
        .navigationTitle("Mã QR")
    }
}

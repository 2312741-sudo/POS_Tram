import SwiftUI

struct OnlineOrderView: View {
    @State private var onlineOrders: [OnlineOrder] = []
    
    var body: some View {
        List(onlineOrders) { order in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Đơn Online: Bàn \(order.tableName ?? "?")")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                    Text(order.status == "PENDING" ? "Chờ xác nhận" : "Đã xử lý")
                        .font(.caption)
                        .padding(5)
                        .background(order.status == "PENDING" ? Color.orange : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                
                Text(formatItems(order.itemsJson ?? "[]"))
                    .font(.body)
                
                if order.status == "PENDING" {
                    HStack {
                        Button("Xác nhận") {
                            confirmOrder(order)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button("Hủy") {
                            cancelOrder(order)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Đơn Online")
        .onAppear {
            FirebaseManager.shared.listenToOnlineOrders { orders in
                DispatchQueue.main.async {
                    self.onlineOrders = orders.sorted(by: { $0.timestamp > $1.timestamp })
                }
            }
        }
    }
    
    private func formatItems(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([Product].self, from: data) else {
            return "Lỗi hiển thị món"
        }
        return items.map {
            let noteStr = $0.note.isEmpty ? "" : " (\($0.note))"
            return "\($0.name) x\($0.quantity)\(noteStr)"
        }.joined(separator: "\n")
    }
    
    private func confirmOrder(_ order: OnlineOrder) {
        guard let key = order.firebaseKey else { return }
        FirebaseManager.shared.updateOnlineOrderStatus(key: key, status: "CONFIRMED")
        
        // Push to kitchen
        let kitchenOrder = KitchenOrder(
            tableName: order.tableName ?? "Online",
            itemsJson: order.itemsJson ?? "[]",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            isDone: false
        )
        FirebaseManager.shared.pushKitchenOrder(kitchenOrder)
    }
    
    private func cancelOrder(_ order: OnlineOrder) {
        guard let key = order.firebaseKey else { return }
        FirebaseManager.shared.updateOnlineOrderStatus(key: key, status: "CANCELLED")
    }
}

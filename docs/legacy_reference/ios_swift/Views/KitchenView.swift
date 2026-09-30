import SwiftUI

struct KitchenView: View {
    @StateObject private var viewModel = KitchenViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.kitchenOrders) { order in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Bàn: \(order.tableName)")
                            .font(.headline)
                        Spacer()
                        Text("Mới")
                            .font(.caption)
                            .padding(5)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(5)
                    }
                    
                    Text(formatItems(order.itemsJson))
                        .font(.body)
                    
                    Button(action: {
                        viewModel.markAsDone(order: order)
                    }) {
                        Text("Đã xong")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 5)
            }
            .navigationTitle("Bếp")
        }
    }
    
    private func formatItems(_ json: String) -> String {
        // Minimal json parser for display
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([Product].self, from: data) else {
            return "Lỗi hiển thị món"
        }
        
        return items.map { "\($0.name) x\($0.quantity)" }.joined(separator: "\n")
    }
}

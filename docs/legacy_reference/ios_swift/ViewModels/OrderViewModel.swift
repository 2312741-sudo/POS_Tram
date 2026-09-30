import Foundation

class OrderViewModel: ObservableObject {
    @Published var cart: [Product] = []
    @Published var currentTable: Table?
    
    init(table: Table? = nil) {
        self.currentTable = table
        if let json = table?.currentOrderJson, !json.isEmpty, let data = json.data(using: .utf8) {
            do {
                self.cart = try JSONDecoder().decode([Product].self, from: data)
            } catch {
                print("Failed to decode table cart: \(error)")
            }
        }
    }
    
    func addToCart(product: Product) {
        if let index = cart.firstIndex(where: { $0.id == product.id && $0.note == product.note }) {
            cart[index].quantity += 1
        } else {
            var newProduct = product
            newProduct.quantity = 1
            cart.append(newProduct)
        }
    }
    
    func updateQuantity(for product: Product, delta: Int) {
        if let index = cart.firstIndex(where: { $0.id == product.id && $0.note == product.note }) {
            cart[index].quantity += delta
            if cart[index].quantity <= 0 {
                cart.remove(at: index)
            }
        }
    }
    
    func getTotalAmount() -> Int {
        return cart.reduce(0) { $0 + ($1.price * $1.quantity) }
    }
    
    func confirmOrder() {
        guard let table = currentTable else { return }
        
        do {
            let data = try JSONEncoder().encode(cart)
            let itemsJson = String(data: data, encoding: .utf8) ?? "[]"
            
            // 1. Update Table
            var updatedTable = table
            updatedTable.inUse = true
            updatedTable.currentOrderJson = itemsJson
            FirebaseManager.shared.updateTable(updatedTable)
            
            // 2. Push to Kitchen
            let kitchenOrder = KitchenOrder(
                tableName: table.name,
                itemsJson: itemsJson,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                isDone: false
            )
            FirebaseManager.shared.pushKitchenOrder(kitchenOrder)
            
            // Clear cart
            cart.removeAll()
            
        } catch {
            print("Failed to encode cart: \(error)")
        }
    }
}

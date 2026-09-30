import Foundation

class KitchenViewModel: ObservableObject {
    @Published var kitchenOrders: [KitchenOrder] = []
    
    init() {
        fetchKitchenOrders()
    }
    
    func fetchKitchenOrders() {
        FirebaseManager.shared.listenToKitchenOrders { [weak self] fetchedOrders in
            DispatchQueue.main.async {
                self?.kitchenOrders = fetchedOrders
                    .filter { !$0.isDone }
                    .sorted { $0.timestamp < $1.timestamp }
            }
        }
    }
    
    func markAsDone(order: KitchenOrder) {
        guard let key = order.firebaseKey else { return }
        FirebaseManager.shared.updateKitchenOrderStatus(key: key, isDone: true)
    }
}

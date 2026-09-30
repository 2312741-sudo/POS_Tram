import Foundation

class TableViewModel: ObservableObject {
    @Published var tables: [Table] = []
    
    init() {
        fetchTables()
    }
    
    func fetchTables() {
        FirebaseManager.shared.listenToTables { [weak self] fetchedTables in
            DispatchQueue.main.async {
                self?.tables = fetchedTables.sorted(by: { $0.name < $1.name })
            }
        }
    }
    
    func filterTables(by zone: String?, inUse: Bool?) -> [Table] {
        return tables.filter { table in
            let matchZone = zone == nil || zone == "Tất cả" || table.zone == zone
            let matchStatus = inUse == nil || table.inUse == inUse
            return matchZone && matchStatus
        }
    }
}

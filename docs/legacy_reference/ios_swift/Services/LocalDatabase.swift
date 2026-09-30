import Foundation

class LocalDatabase {
    static let shared = LocalDatabase()
    private let fileManager = FileManager.default
    
    private func getFileURL(for filename: String) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("\(filename).json")
    }
    
    private func save<T: Encodable>(_ items: [T], to filename: String) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: getFileURL(for: filename))
        } catch {
            print("Lỗi lưu \(filename): \(error)")
        }
    }
    
    private func load<T: Decodable>(from filename: String) -> [T] {
        do {
            let data = try Data(contentsOf: getFileURL(for: filename))
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("Lỗi tải \(filename) hoặc file chưa tồn tại: \(error)")
            return []
        }
    }
    
    // MARK: - Users
    func getUsers() -> [User] {
        let users: [User] = load(from: "users")
        if users.isEmpty {
            // Seed default users
            let defaults = [
                User(fullName: "Nhân viên", username: "nv", pin: "1", role: "STAFF"),
                User(fullName: "Quản lý", username: "ql", pin: "1", role: "MANAGER"),
                User(fullName: "Đầu bếp", username: "bep", pin: "1", role: "KITCHEN")
            ]
            saveUsers(defaults)
            return defaults
        }
        return users
    }
    func saveUsers(_ users: [User]) { save(users, to: "users") }
    
    // MARK: - Zones
    func getZones() -> [Zone] { load(from: "zones") }
    func saveZones(_ zones: [Zone]) { save(zones, to: "zones") }
    
    // MARK: - Categories
    func getCategories() -> [Category] { load(from: "categories") }
    func saveCategories(_ cats: [Category]) { save(cats, to: "categories") }
    
    // MARK: - Products
    func getProducts() -> [Product] { load(from: "products") }
    func saveProducts(_ products: [Product]) { save(products, to: "products") }
    
    // MARK: - Tables (Offline)
    func getLocalTables() -> [Table] { load(from: "localtables") }
    func saveLocalTables(_ tables: [Table]) { save(tables, to: "localtables") }
    
    // MARK: - Order History
    func getOrderHistory() -> [OrderHistory] { load(from: "history") }
    func saveOrderHistory(_ history: [OrderHistory]) { save(history, to: "history") }
}

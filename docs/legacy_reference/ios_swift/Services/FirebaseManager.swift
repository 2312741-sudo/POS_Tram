import Foundation
import FirebaseDatabase

class FirebaseManager {
    static let shared = FirebaseManager()
    
    private let ref: DatabaseReference
    
    private init() {
        // Must call FirebaseApp.configure() in AppDelegate or App struct
        self.ref = Database.database(url: "https://ungdungdidong-94edd-default-rtdb.firebaseio.com").reference()
    }
    
    // MARK: - Tables
    func listenToTables(completion: @escaping ([Table]) -> Void) {
        ref.child("tables").observe(.value) { snapshot in
            var tables: [Table] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var table = try JSONDecoder().decode(Table.self, from: jsonData)
                        table.firebaseKey = childSnapshot.key
                        tables.append(table)
                    } catch {
                        print("Error decoding table: \(error)")
                    }
                }
            }
            completion(tables)
        }
    }
    
    func updateTable(_ table: Table) {
        guard let key = table.firebaseKey else { return }
        do {
            let data = try JSONEncoder().encode(table)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                ref.child("tables").child(key).setValue(dict)
            }
        } catch {
            print("Error encoding table: \(error)")
        }
    }
    
    // MARK: - Online Orders
    func listenToOnlineOrders(completion: @escaping ([OnlineOrder]) -> Void) {
        ref.child("online_orders").observe(.value) { snapshot in
            var orders: [OnlineOrder] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var order = try JSONDecoder().decode(OnlineOrder.self, from: jsonData)
                        order.firebaseKey = childSnapshot.key
                        orders.append(order)
                    } catch {
                        print("Error decoding online order: \(error)")
                    }
                }
            }
            completion(orders)
        }
    }
    
    func updateOnlineOrderStatus(key: String, status: String) {
        ref.child("online_orders").child(key).child("status").setValue(status)
    }
    
    // MARK: - Kitchen Orders
    func listenToKitchenOrders(completion: @escaping ([KitchenOrder]) -> Void) {
        ref.child("kitchen_orders").observe(.value) { snapshot in
            var orders: [KitchenOrder] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var order = try JSONDecoder().decode(KitchenOrder.self, from: jsonData)
                        order.firebaseKey = childSnapshot.key
                        orders.append(order)
                    } catch {
                        print("Error decoding kitchen order: \(error)")
                    }
                }
            }
            completion(orders)
        }
    }
    
    func pushKitchenOrder(_ order: KitchenOrder) {
        let childRef = ref.child("kitchen_orders").childByAutoId()
        var newOrder = order
        newOrder.firebaseKey = childRef.key
        
        do {
            let data = try JSONEncoder().encode(newOrder)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error encoding kitchen order: \(error)")
        }
    }
    
    func updateKitchenOrderStatus(key: String, isDone: Bool) {
        ref.child("kitchen_orders").child(key).child("isDone").setValue(isDone)
    }
    
    // MARK: - Users
    func listenToUsers(completion: @escaping ([User]) -> Void) {
        ref.child("users").observe(.value) { snapshot in
            var items: [User] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var item = try JSONDecoder().decode(User.self, from: jsonData)
                        // item.id is UUID if not present, but for firebase we can use key
                        item.id = childSnapshot.key
                        items.append(item)
                    } catch { print("Error: \(error)") }
                }
            }
            completion(items)
        }
    }
    
    // MARK: - Products
    func listenToProducts(completion: @escaping ([Product]) -> Void) {
        ref.child("products").observe(.value) { snapshot in
            var items: [Product] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var item = try JSONDecoder().decode(Product.self, from: jsonData)
                        item.id = childSnapshot.key
                        items.append(item)
                    } catch { print("Error: \(error)") }
                }
            }
            completion(items)
        }
    }
    
    // MARK: - Categories
    func listenToCategories(completion: @escaping ([Category]) -> Void) {
        ref.child("categories").observe(.value) { snapshot in
            var items: [Category] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var item = try JSONDecoder().decode(Category.self, from: jsonData)
                        item.id = childSnapshot.key
                        items.append(item)
                    } catch { print("Error: \(error)") }
                }
            }
            completion(items)
        }
    }
    
    // MARK: - Zones
    func listenToZones(completion: @escaping ([Zone]) -> Void) {
        ref.child("zones").observe(.value) { snapshot in
            var items: [Zone] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var item = try JSONDecoder().decode(Zone.self, from: jsonData)
                        item.id = childSnapshot.key
                        items.append(item)
                    } catch { print("Error: \(error)") }
                }
            }
            completion(items)
        }
    }
    
    // MARK: - History
    func listenToHistory(completion: @escaping ([OrderHistory]) -> Void) {
        ref.child("history").observe(.value) { snapshot in
            var items: [OrderHistory] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
                        var item = try JSONDecoder().decode(OrderHistory.self, from: jsonData)
                        item.id = childSnapshot.key
                        items.append(item)
                    } catch { print("Error: \(error)") }
                }
            }
            completion(items)
        }
    }
    
    func pushHistory(_ history: OrderHistory) {
        let childRef = ref.child("history").childByAutoId()
        do {
            let data = try JSONEncoder().encode(history)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error encoding history: \(error)")
        }
    }
    
    func pushProduct(_ product: Product) {
        let childRef = ref.child("products").childByAutoId()
        var newProd = product
        newProd.id = childRef.key ?? UUID().uuidString
        do {
            let data = try JSONEncoder().encode(newProd)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error encoding product: \(error)")
        }
    }
    
    // MARK: - Tables CRUD Helpers
    func pushTable(_ table: Table) {
        let childRef = ref.child("tables").childByAutoId()
        var newTable = table
        newTable.firebaseKey = childRef.key
        do {
            let data = try JSONEncoder().encode(newTable)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error encoding table: \(error)")
        }
    }
    
    func deleteTable(key: String) {
        ref.child("tables").child(key).removeValue()
    }
    
    // MARK: - Products CRUD Helpers
    func updateProduct(_ product: Product) {
        do {
            let data = try JSONEncoder().encode(product)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                ref.child("products").child(product.id).setValue(dict)
            }
        } catch {
            print("Error updating product: \(error)")
        }
    }
    
    func deleteProduct(id: String) {
        ref.child("products").child(id).removeValue()
    }
    
    // MARK: - Categories CRUD Helpers
    func pushCategory(_ category: Category) {
        let childRef = ref.child("categories").childByAutoId()
        var newCat = category
        newCat.id = childRef.key ?? UUID().uuidString
        do {
            let data = try JSONEncoder().encode(newCat)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error pushing category: \(error)")
        }
    }
    
    func updateCategory(_ category: Category) {
        do {
            let data = try JSONEncoder().encode(category)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                ref.child("categories").child(category.id).setValue(dict)
            }
        } catch {
            print("Error updating category: \(error)")
        }
    }
    
    func deleteCategory(id: String) {
        ref.child("categories").child(id).removeValue()
    }
    
    // MARK: - Zones CRUD Helpers
    func pushZone(_ zone: Zone) {
        let childRef = ref.child("zones").childByAutoId()
        var newZone = zone
        newZone.id = childRef.key ?? UUID().uuidString
        do {
            let data = try JSONEncoder().encode(newZone)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error pushing zone: \(error)")
        }
    }
    
    func updateZone(_ zone: Zone) {
        do {
            let data = try JSONEncoder().encode(zone)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                ref.child("zones").child(zone.id).setValue(dict)
            }
        } catch {
            print("Error updating zone: \(error)")
        }
    }
    
    func deleteZone(id: String) {
        ref.child("zones").child(id).removeValue()
    }
    
    // MARK: - Users CRUD Helpers
    func pushUser(_ user: User) {
        let childRef = ref.child("users").childByAutoId()
        var newUser = user
        newUser.id = childRef.key ?? UUID().uuidString
        do {
            let data = try JSONEncoder().encode(newUser)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                childRef.setValue(dict)
            }
        } catch {
            print("Error pushing user: \(error)")
        }
    }
    
    func updateUser(_ user: User) {
        do {
            let data = try JSONEncoder().encode(user)
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                ref.child("users").child(user.id).setValue(dict)
            }
        } catch {
            print("Error updating user: \(error)")
        }
    }
    
    func deleteUser(id: String) {
        ref.child("users").child(id).removeValue()
    }
}

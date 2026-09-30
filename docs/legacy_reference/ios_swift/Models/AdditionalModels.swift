import Foundation

struct User: Identifiable, Codable {
    var id: String = UUID().uuidString
    var fullName: String
    var username: String
    var pin: String
    var role: String // "MANAGER", "STAFF", "KITCHEN"
    
    enum CodingKeys: String, CodingKey { case id, fullName, username, pin, role }
    init(id: String = UUID().uuidString, fullName: String, username: String, pin: String, role: String) { self.id = id; self.fullName = fullName; self.username = username; self.pin = pin; self.role = role }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        }
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        pin = (try? c.decodeIfPresent(String.self, forKey: .pin)) ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "STAFF"
    }
}

struct Category: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    
    enum CodingKeys: String, CodingKey { case id, name }
    init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Khác"
    }
}

struct Zone: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    
    enum CodingKeys: String, CodingKey { case id, name }
    init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Khu vực"
    }
}

struct OrderHistory: Identifiable, Codable {
    var id: String = UUID().uuidString
    var tableName: String
    var itemsJson: String
    var totalAmount: Int
    var timestamp: Int64
    var cashierName: String
    var paymentMethod: String?
    var orderCode: String?
    var status: String?
    
    enum CodingKeys: String, CodingKey { case id, tableName, itemsJson, totalAmount, timestamp, cashierName, paymentMethod, orderCode, status }
    
    init(id: String = UUID().uuidString, tableName: String, itemsJson: String, totalAmount: Int, timestamp: Int64, cashierName: String, paymentMethod: String? = nil, orderCode: String? = nil, status: String? = nil) {
        self.id = id; self.tableName = tableName; self.itemsJson = itemsJson; self.totalAmount = totalAmount; self.timestamp = timestamp; self.cashierName = cashierName; self.paymentMethod = paymentMethod; self.orderCode = orderCode; self.status = status
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        }
        tableName = (try? c.decodeIfPresent(String.self, forKey: .tableName)) ?? "Bàn ?"
        itemsJson = (try? c.decodeIfPresent(String.self, forKey: .itemsJson)) ?? "[]"
        
        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .totalAmount) {
            totalAmount = intVal
        } else if let doubleVal = try? c.decodeIfPresent(Double.self, forKey: .totalAmount) {
            totalAmount = Int(doubleVal)
        } else if let strVal = try? c.decodeIfPresent(String.self, forKey: .totalAmount) {
            totalAmount = Int(strVal) ?? 0
        } else {
            totalAmount = 0
        }
        
        if let longVal = try? c.decodeIfPresent(Int64.self, forKey: .timestamp) {
            timestamp = longVal
        } else if let doubleVal = try? c.decodeIfPresent(Double.self, forKey: .timestamp) {
            timestamp = Int64(doubleVal)
        } else if let strVal = try? c.decodeIfPresent(String.self, forKey: .timestamp) {
            timestamp = Int64(strVal) ?? Int64(Date().timeIntervalSince1970 * 1000)
        } else {
            timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }
        
        cashierName = (try? c.decodeIfPresent(String.self, forKey: .cashierName)) ?? ""
        paymentMethod = try? c.decodeIfPresent(String.self, forKey: .paymentMethod)
        orderCode = try? c.decodeIfPresent(String.self, forKey: .orderCode)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
    }
}

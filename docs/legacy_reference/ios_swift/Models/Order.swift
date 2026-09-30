import Foundation

struct KitchenOrder: Identifiable, Codable {
    var id: String {
        return firebaseKey ?? UUID().uuidString
    }
    
    var tableName: String
    var itemsJson: String
    var timestamp: Int64
    var isDone: Bool
    var firebaseKey: String?
    
    
    enum CodingKeys: String, CodingKey {
        case tableName, itemsJson, timestamp, isDone, firebaseKey
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tableName = (try? c.decodeIfPresent(String.self, forKey: .tableName)) ?? "Bàn ?"
        itemsJson = (try? c.decodeIfPresent(String.self, forKey: .itemsJson)) ?? "[]"
        timestamp = (try? c.decodeIfPresent(Int64.self, forKey: .timestamp)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        firebaseKey = try? c.decodeIfPresent(String.self, forKey: .firebaseKey)
    }
    
    init(tableName: String, itemsJson: String, timestamp: Int64, isDone: Bool, firebaseKey: String? = nil) {
        self.tableName = tableName
        self.itemsJson = itemsJson
        self.timestamp = timestamp
        self.isDone = isDone
        self.firebaseKey = firebaseKey
    }
}

struct OnlineOrder: Identifiable, Codable {
    var id: String {
        return firebaseKey ?? UUID().uuidString
    }
    
    var tableName: String?
    var tableZone: String?
    var itemsJson: String?
    var status: String?
    var type: String?
    var timestamp: Int64
    var firebaseKey: String?
    
    enum CodingKeys: String, CodingKey {
        case tableName, tableZone, itemsJson, status, type, timestamp, firebaseKey
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tableName = try? c.decodeIfPresent(String.self, forKey: .tableName)
        tableZone = try? c.decodeIfPresent(String.self, forKey: .tableZone)
        itemsJson = try? c.decodeIfPresent(String.self, forKey: .itemsJson)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        timestamp = (try? c.decodeIfPresent(Int64.self, forKey: .timestamp)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        firebaseKey = try? c.decodeIfPresent(String.self, forKey: .firebaseKey)
    }
    
    init(tableName: String? = nil, tableZone: String? = nil, itemsJson: String? = nil, status: String? = nil, type: String? = nil, timestamp: Int64, firebaseKey: String? = nil) {
        self.tableName = tableName
        self.tableZone = tableZone
        self.itemsJson = itemsJson
        self.status = status
        self.type = type
        self.timestamp = timestamp
        self.firebaseKey = firebaseKey
    }
}

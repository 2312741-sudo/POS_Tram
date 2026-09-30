import Foundation

struct Table: Identifiable, Codable {
    var id: String {
        return firebaseKey ?? name
    }
    
    var name: String
    var zone: String
    var inUse: Bool
    var currentOrderJson: String?
    var firebaseKey: String?
    
    enum CodingKeys: String, CodingKey {
        case name, zone, inUse, currentOrderJson, firebaseKey
    }
    
    init(name: String, zone: String, inUse: Bool = false, currentOrderJson: String? = nil, firebaseKey: String? = nil) {
        self.name = name
        self.zone = zone
        self.inUse = inUse
        self.currentOrderJson = currentOrderJson
        self.firebaseKey = firebaseKey
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Bàn"
        zone = (try? container.decodeIfPresent(String.self, forKey: .zone)) ?? "Khác"
        inUse = (try? container.decodeIfPresent(Bool.self, forKey: .inUse)) ?? false
        currentOrderJson = try? container.decodeIfPresent(String.self, forKey: .currentOrderJson)
        firebaseKey = try? container.decodeIfPresent(String.self, forKey: .firebaseKey)
    }
}

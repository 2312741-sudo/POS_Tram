import Foundation

struct Product: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var price: Int
    var unit: String
    var category: String
    var imageResourceName: String?
    var imageBase64: String?
    
    // For cart
    var quantity: Int = 0
    var note: String = ""
    
    enum CodingKeys: String, CodingKey {
        case id, name, price, unit, category, imageResourceName, imageBase64, quantity, note
    }
    
    init(id: String = UUID().uuidString, name: String, price: Int, unit: String, category: String) {
        self.id = id
        self.name = name
        self.price = price
        self.unit = unit
        self.category = category
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Không tên"
        
        if let intPrice = try? container.decodeIfPresent(Int.self, forKey: .price) {
            price = intPrice
        } else if let strPrice = try? container.decodeIfPresent(String.self, forKey: .price) {
            price = Int(strPrice) ?? 0
        } else {
            price = 0
        }
        
        unit = (try? container.decodeIfPresent(String.self, forKey: .unit)) ?? "Cái"
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? "Khác"
        imageResourceName = try? container.decodeIfPresent(String.self, forKey: .imageResourceName)
        imageBase64 = try? container.decodeIfPresent(String.self, forKey: .imageBase64)
        quantity = (try? container.decodeIfPresent(Int.self, forKey: .quantity)) ?? 0
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }
}

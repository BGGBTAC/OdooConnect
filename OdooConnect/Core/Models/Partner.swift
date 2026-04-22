import Foundation

struct Partner: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let name: String
    @OdooOptionalString var email: String?
    @OdooOptionalString var phone: String?
    @OdooOptionalString var city: String?
    @OdooOptionalString var street: String?
    @OdooOptionalString var zip: String?

    static let fields: [String] = ["id", "name", "email", "phone", "city", "street", "zip"]
}

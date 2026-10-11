import Foundation

struct PicOfDay: Identifiable, Equatable {
    var id: URL { pageURL }
    let title: String
    let date: Date
    let explanation: String
    let credit: String
    let altText: String
    let imageURL: URL
    let pageURL: URL
}

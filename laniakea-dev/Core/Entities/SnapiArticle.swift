import Foundation

struct SnapiArticleResponse: Codable {
    let results: [SnapiArticle]
}

struct SnapiArticle: Codable, Identifiable {
    let id: Int
    let title: String
    let url: String
    let image_url: String?
    let news_site: String
    let summary: String
    let published_at: String
}

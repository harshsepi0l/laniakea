import Foundation

struct SnapiArticleResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
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
    let updated_at: String
    let featured: Bool
}




// MARK: - Author Model
struct Author: Codable {
    let name: String
    let socials: Socials?
}

struct Socials: Codable {
    let x: String?
    let youtube: String?
    let instagram: String?
    let linkedin: String?
    let mastodon: String?
    let bluesky: String?
}

import Foundation

struct GeneratedArticle: Codable, Equatable {
    struct Section: Codable, Equatable {
        let heading: String
        let body: String
    }

    struct Source: Codable, Equatable {
        let name: String
        let url: String
    }

    let title: String
    let summary: String
    let sections: [Section]
    let source: Source
    let image_url: String?
    let published_at: String
}

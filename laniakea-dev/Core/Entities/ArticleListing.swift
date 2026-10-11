import Foundation

/// What the article screen needs to show a story, whether or not an AI version exists yet.
struct ArticleListing {
    let title: String
    let summary: String
    let sourceName: String
    let sourceURL: String
    let imageURL: String?
    let publishedAt: Date?
    /// Path of the generated JSON, relative to the generated-articles base URL.
    let generatedPath: String
}

extension SnapiArticle {
    var listing: ArticleListing {
        ArticleListing(
            title: title,
            summary: summary,
            sourceName: news_site,
            sourceURL: url,
            imageURL: image_url,
            publishedAt: Self.parseDate(published_at),
            generatedPath: "\(id).json"
        )
    }

    private static func parseDate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }
}

extension PicOfDay {
    var listing: ArticleListing {
        ArticleListing(
            title: title,
            summary: explanation,
            sourceName: "NASA APOD",
            sourceURL: pageURL.absoluteString,
            imageURL: imageURL.absoluteString,
            publishedAt: date,
            generatedPath: "apod/\(Self.utcDay.string(from: date)).json"
        )
    }

    // Must match the generator, which names APOD files by the feed's UTC publish date.
    private static let utcDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

import Foundation

// APOD moved to science.nasa.gov in Sept 2026; the legacy api.nasa.gov/planetary/apod
// endpoint now returns a placeholder, so we read NASA's official APOD RSS feed instead.
class PicOfDayAPIService: PicOfDayRepo {
    private let feedURL = URL(string: "https://science.nasa.gov/feed/apod-basic/")!
    private let displayWidth = 1200

    func fetchPicOfDay(completion: @escaping (Result<PicOfDay, Error>) -> Void) {
        URLSession.shared.dataTask(with: feedURL) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                completion(.failure(APODError.badResponse))
                return
            }
            let parser = APODFeedParser(data: data)
            guard let item = parser.parseLatestItem(), let pic = self.makePicOfDay(from: item) else {
                completion(.failure(APODError.unreadableFeed))
                return
            }
            completion(.success(pic))
        }.resume()
    }

    private func makePicOfDay(from item: [String: String]) -> PicOfDay? {
        guard
            let title = item["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let pageURL = item["apod:url"].flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
            let hdURLString = item["apod:hdurl"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let imageURL = resized(hdURLString),
            let pubDate = item["pubDate"].flatMap(Self.parseRFC822)
        else { return nil }

        var explanation = HTMLText.plain(item["apod:explanation"] ?? "")
        if explanation.hasPrefix("Explanation:") {
            explanation = String(explanation.dropFirst("Explanation:".count))
        }
        if let range = explanation.range(of: "Tomorrow's picture:") {
            explanation = String(explanation[..<range.lowerBound])
        }

        return PicOfDay(
            title: HTMLText.plain(title),
            date: pubDate,
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            credit: HTMLText.plain(item["apod:credit"] ?? ""),
            altText: HTMLText.plain(item["apod:alt"] ?? title),
            imageURL: imageURL,
            pageURL: pageURL
        )
    }

    // Originals can exceed 30 MB; NASA's image CDN resizes via the w/fit query params.
    private func resized(_ urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "w", value: String(displayWidth)),
            URLQueryItem(name: "fit", value: "clip"),
        ]
        return components.url
    }

    private static func parseRFC822(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum APODError: LocalizedError {
    case badResponse
    case unreadableFeed

    var errorDescription: String? {
        switch self {
        case .badResponse: return "NASA's server didn't respond. Check your connection and try again."
        case .unreadableFeed: return "Today's picture couldn't be read from NASA's feed."
        }
    }
}

private final class APODFeedParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var item: [String: String]?
    private var currentElement: String?
    private var buffer = ""
    private var finished = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parseLatestItem() -> [String: String]? {
        parser.parse()
        return finished ? item : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "item" {
            item = [:]
        } else if item != nil {
            currentElement = elementName
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if currentElement != nil, let string = String(data: CDATABlock, encoding: .utf8) { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" {
            finished = true
            parser.abortParsing()
        } else if elementName == currentElement {
            item?[elementName] = buffer
            currentElement = nil
        }
    }
}

enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " "]

    private static func decodeEntities(_ string: String) -> String {
        var result = string
        let pattern = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard
                let whole = Range(match.range, in: result),
                let hexFlag = Range(match.range(at: 1), in: result),
                let digits = Range(match.range(at: 2), in: result),
                let code = UInt32(result[digits], radix: result[hexFlag].isEmpty ? 10 : 16),
                let scalar = Unicode.Scalar(code)
            else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}

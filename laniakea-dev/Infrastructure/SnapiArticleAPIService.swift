import Foundation

class SnapiArticleAPIService: SnapiArticleRepo {
    
    func fetchSnapiArticle(completion: @escaping (Result<[SnapiArticle], Error>) -> Void) {
        guard let url = URL(string: "https://api.spaceflightnewsapi.net/v4/articles/?news_site=NASA,ESA&limit=20") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -2)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(SnapiArticleResponse.self, from: data)
                completion(.success(decoded.results))
            } catch {
                completion(.failure(error))
                print("❌ Decode error:", error)
            }
        }.resume()
    }
}

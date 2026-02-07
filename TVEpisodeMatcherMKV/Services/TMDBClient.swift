import Foundation

struct TMDBClient {
    let accessToken: String
    let session: URLSession

    init(accessToken: String, session: URLSession = .shared) {
        self.accessToken = accessToken
        self.session = session
    }

    func searchShow(name: String) async throws -> TMDBShow? {
        guard let url = URL(string: "https://api.themoviedb.org/3/search/tv?query=\(name.urlQueryEncoded)&include_adult=false&language=en-US") else {
            return nil
        }
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response)
        let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return bestShowMatch(for: name, results: decoded.results)
    }

    func searchShows(name: String, limit: Int = 10) async throws -> [TMDBShow] {
        guard let url = URL(string: "https://api.themoviedb.org/3/search/tv?query=\(name.urlQueryEncoded)&include_adult=false&language=en-US") else {
            return []
        }
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response)
        let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        let ranked = rankedShows(for: name, results: decoded.results)
        if limit <= 0 { return [] }
        return Array(ranked.prefix(limit))
    }

    func fetchSeason(showId: Int, seasonNumber: Int) async throws -> TMDBSeasonResponse? {
        guard let url = URL(string: "https://api.themoviedb.org/3/tv/\(showId)/season/\(seasonNumber)?language=en-US") else {
            return nil
        }
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response)
        return try JSONDecoder().decode(TMDBSeasonResponse.self, from: data)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        if http.statusCode == 401 {
            throw TMDBError.unauthorized
        }
        if http.statusCode >= 400 {
            throw TMDBError.httpError(http.statusCode)
        }
    }

    private func bestShowMatch(for query: String, results: [TMDBShow]) -> TMDBShow? {
        guard !results.isEmpty else { return nil }
        let normalizedQuery = query.normalizedTokenString
        return results.max { lhs, rhs in
            showScore(for: lhs, query: normalizedQuery) < showScore(for: rhs, query: normalizedQuery)
        }
    }

    private func rankedShows(for query: String, results: [TMDBShow]) -> [TMDBShow] {
        guard !results.isEmpty else { return [] }
        let normalizedQuery = query.normalizedTokenString
        return results.sorted { lhs, rhs in
            showScore(for: lhs, query: normalizedQuery) > showScore(for: rhs, query: normalizedQuery)
        }
    }

    private func showScore(for show: TMDBShow, query: String) -> Int {
        let nameScore = matchScore(name: show.name, query: query)
        let originalScore = matchScore(name: show.originalName ?? "", query: query)
        return max(nameScore, originalScore)
    }

    private func matchScore(name: String, query: String) -> Int {
        let normalized = name.normalizedTokenString
        if normalized == query {
            return 100
        }
        if normalized.hasPrefix(query) || query.hasPrefix(normalized) {
            return 75
        }
        if normalized.contains(query) || query.contains(normalized) {
            return 50
        }
        let overlap = normalized.tokenOverlapScore(with: query)
        return 25 + overlap
    }
}

enum TMDBError: Error {
    case unauthorized
    case httpError(Int)
}

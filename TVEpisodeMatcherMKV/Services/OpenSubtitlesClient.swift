import Foundation

struct OpenSubtitlesEpisodeMatch: Hashable {
    let episodeNumber: Int
    let title: String?
}

final class OpenSubtitlesClient {
    let apiKey: String
    let username: String
    let password: String
    let session: URLSession

    private var token: String?
    private var baseURL: URL

    init(apiKey: String, username: String, password: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.session = session
        self.baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
        self.token = nil
    }

    func matchEpisodesByHash(movieHash: String, movieBytesize: Int64) async throws -> [OpenSubtitlesEpisodeMatch] {
        if token == nil {
            try await login()
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "moviehash", value: movieHash),
            URLQueryItem(name: "moviebytesize", value: String(movieBytesize))
        ]
        guard let url = components?.url else { return [] }
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data, requestURL: url)
        do {
            let decoded = try JSONDecoder().decode(OpenSubtitlesSubtitleResponse.self, from: data)
            let candidates = decoded.data.compactMap { item -> OpenSubtitlesEpisodeMatch? in
                let details = item.attributes.featureDetails
                guard let episodeNumber = details?.episodeNumber else { return nil }
                return OpenSubtitlesEpisodeMatch(episodeNumber: episodeNumber, title: details?.title)
            }
            return candidates
        } catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "Non-UTF8 response"
            throw OpenSubtitlesError.decoding(snippet)
        }
    }

    func searchSubtitles(parentTmdbId: Int, seasonNumber: Int, episodeNumber: Int, language: String) async throws -> [OpenSubtitlesSubtitleData] {
        if token == nil {
            try await login()
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "parent_tmdb_id", value: String(parentTmdbId)),
            URLQueryItem(name: "season_number", value: String(seasonNumber)),
            URLQueryItem(name: "episode_number", value: String(episodeNumber)),
            URLQueryItem(name: "languages", value: language),
            URLQueryItem(name: "order_by", value: "download_count"),
            URLQueryItem(name: "order_direction", value: "desc")
        ]
        guard let url = components?.url else { return [] }
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data, requestURL: url)
        let decoded = try JSONDecoder().decode(OpenSubtitlesSubtitleResponse.self, from: data)
        return decoded.data
    }

    func downloadSubtitle(fileId: Int) async throws -> Data {
        if token == nil {
            try await login()
        }
        let downloadEndpoint = "\(baseURL.absoluteString)/download"
        guard let url = URL(string: downloadEndpoint) else {
            throw OpenSubtitlesError.httpError(-1, endpoint: downloadEndpoint, responseSnippet: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("TVEpisodeMatcherMKV 0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload = ["file_id": fileId]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, requestURL: url)
        let decoded = try JSONDecoder().decode(OpenSubtitlesDownloadResponse.self, from: data)
        guard let downloadURL = URL(string: decoded.link) else {
            throw OpenSubtitlesError.httpError(-1, endpoint: url.absoluteString, responseSnippet: nil)
        }
        let (fileData, fileResponse) = try await session.data(for: URLRequest(url: downloadURL))
        try validate(response: fileResponse, data: fileData, requestURL: downloadURL)
        if fileData.starts(with: [0x1f, 0x8b]) {
            return fileData.gunzipped() ?? fileData
        }
        return fileData
    }

    private func login() async throws {
        guard let url = URL(string: "\(baseURL.absoluteString)/login") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("TVEpisodeMatcherMKV 0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload = OpenSubtitlesLoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, requestURL: url)
        let decoded = try JSONDecoder().decode(OpenSubtitlesLoginResponse.self, from: data)
        token = decoded.token
        if let baseUrl = decoded.baseUrl, let normalized = normalizeBaseURL(baseUrl) {
            baseURL = normalized
        }
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("TVEpisodeMatcherMKV 0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data?, requestURL: URL?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw OpenSubtitlesError.unauthorized(endpoint: requestURL?.absoluteString)
        }
        if http.statusCode >= 400 {
            let snippet = data.flatMap { String(data: $0.prefix(500), encoding: .utf8) }
            throw OpenSubtitlesError.httpError(http.statusCode, endpoint: requestURL?.absoluteString, responseSnippet: snippet)
        }
    }

    private func normalizeBaseURL(_ baseUrl: String) -> URL? {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: URL?
        if let url = URL(string: trimmed), url.scheme != nil {
            candidate = url
        } else {
            candidate = URL(string: "https://\(trimmed)")
        }
        guard let url = candidate else { return nil }
        guard let host = url.host, host.contains("api.opensubtitles.com") else {
            return nil
        }
        if url.path.contains("/api/v1") {
            return url
        }
        return url.appendingPathComponent("api/v1")
    }
}

struct OpenSubtitlesLoginRequest: Encodable {
    let username: String
    let password: String
}

struct OpenSubtitlesLoginResponse: Decodable {
    let token: String
    let baseUrl: String?

    enum CodingKeys: String, CodingKey {
        case token
        case baseUrl = "base_url"
    }
}

struct OpenSubtitlesSubtitleResponse: Decodable {
    let data: [OpenSubtitlesSubtitleData]
}

struct OpenSubtitlesSubtitleData: Decodable {
    let attributes: OpenSubtitlesSubtitleAttributes
}

struct OpenSubtitlesSubtitleAttributes: Decodable {
    let language: String?
    let featureDetails: OpenSubtitlesFeatureDetails?
    let files: [OpenSubtitlesFile]?

    enum CodingKeys: String, CodingKey {
        case language
        case featureDetails = "feature_details"
        case files
    }
}

struct OpenSubtitlesFeatureDetails: Decodable {
    let title: String?
    let parentTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let imdbId: Int?
    let tmdbId: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case parentTitle = "parent_title"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
    }
}

struct OpenSubtitlesFile: Decodable {
    let fileId: Int
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
    }
}

struct OpenSubtitlesDownloadResponse: Decodable {
    let link: String
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case link
        case fileName = "file_name"
    }
}

enum OpenSubtitlesError: Error {
    case unauthorized(endpoint: String?)
    case httpError(Int, endpoint: String?, responseSnippet: String?)
    case decoding(String)
}

extension OpenSubtitlesError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized(let endpoint):
            if let endpoint {
                return "Unauthorized (check API key/credentials). Endpoint: \(endpoint)"
            }
            return "Unauthorized (check API key/credentials)"
        case .httpError(let code, let endpoint, let responseSnippet):
            var message = "HTTP error \(code)"
            if let endpoint {
                message += ". Endpoint: \(endpoint)"
            }
            if let responseSnippet, !responseSnippet.isEmpty {
                message += ". Response: \(responseSnippet)"
            }
            return message
        case .decoding(let snippet):
            return "Decoding failed. Response: \(snippet)"
        }
    }
}

enum OpenSubtitlesHasher {
    static func computeHash(for url: URL) throws -> (hash: String, fileSize: Int64) {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        let fileSizeInt64 = Int64(fileSize)
        let chunkSize: UInt64 = 65536

        try fileHandle.seek(toOffset: 0)
        let head = try fileHandle.read(upToCount: Int(chunkSize)) ?? Data()

        let tailOffset = fileSize > chunkSize ? fileSize - chunkSize : 0
        try fileHandle.seek(toOffset: tailOffset)
        let tail = try fileHandle.read(upToCount: Int(chunkSize)) ?? Data()

        var hash = UInt64(fileSize)
        hash &+= checksum(data: head)
        hash &+= checksum(data: tail)

        return (hash: String(format: "%016llx", hash), fileSize: fileSizeInt64)
    }

    private static func checksum(data: Data) -> UInt64 {
        var sum: UInt64 = 0
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
            let chunk = data[index..<end]
            var value: UInt64 = 0
            for (offset, byte) in chunk.enumerated() {
                value |= UInt64(byte) << (UInt64(offset) * 8)
            }
            sum &+= value
            index = end
        }
        return sum
    }
}

import Foundation

enum XDError: LocalizedError {
    case api(String)
    case http(Int)
    case decode(String)
    case needCookie
    case needLogin

    var errorDescription: String? {
        switch self {
        case .api(let m): return m
        case .http(let code): return "网络错误（HTTP \(code)）"
        case .decode(let m): return "解析失败：\(m)"
        case .needCookie: return "该操作需要饼干"
        case .needLogin: return "该操作需要登录 X 岛账号"
        }
    }
}

struct Multipart {
    let boundary = "----CookieJar\(UUID().uuidString)"
    private var body = Data()

    mutating func add(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    mutating func addFile(_ name: String, data: Data, filename: String, mime: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finalized() -> Data {
        var d = body
        d.append("--\(boundary)--\r\n")
        return d
    }
}

private extension Data {
    mutating func append(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}

actor XDHTTP {
    static let shared = XDHTTP()

    private var session: URLSession
    private var phpSessionID: String?
    private var backupPhpSessionID: String?
    private(set) var userCookie: String?

    var isLoggedIn: Bool { userCookie != nil }
    var hasSession: Bool { phpSessionID != nil }

    static let userAgent = "cookiejar-ios/1.0"

    private init() {
        session = XDHTTP.makeSession(timeout: 20)
        userCookie = KeychainStore.read("xd.userCookie")
    }

    private static func makeSession(timeout: Int) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = TimeInterval(timeout)
        config.timeoutIntervalForResource = TimeInterval(timeout * 3)
        config.httpAdditionalHeaders = ["User-Agent": XDHTTP.userAgent]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    var rawSession: URLSession { session }

    func setUserCookie(_ value: String?) {
        userCookie = value
        if let value { KeychainStore.write("xd.userCookie", value) } else { KeychainStore.delete("xd.userCookie") }
    }

    func setTimeout(_ seconds: Int) {
        session.invalidateAndCancel()
        session = XDHTTP.makeSession(timeout: max(5, min(60, seconds)))
    }

    private func cookieHeader(for url: URL, cookie: String?) -> String? {
        var parts: [String] = []
        if let cookie, !cookie.isEmpty { parts.append(cookie) }
        let urls = XDURLs.shared
        if urls.isBase(url), let s = phpSessionID { parts.append(s) }
        if urls.isBackup(url), let s = backupPhpSessionID { parts.append(s) }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func harvest(_ response: URLResponse, requestURL: URL) {
        guard let http = response as? HTTPURLResponse,
              let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") else { return }
        let urls = XDURLs.shared
        for chunk in setCookie.components(separatedBy: ",") {
            let pair = chunk.split(separator: ";").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard pair.hasPrefix("PHPSESSID=") else { continue }
            if urls.isBase(requestURL) {
                phpSessionID = pair
            } else if urls.isBackup(requestURL) {
                backupPhpSessionID = pair
            }
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else { throw XDError.http(http.statusCode) }
    }

    private func send(_ url: URL,
                      method: String,
                      cookie: String?,
                      contentType: String? = nil,
                      body: Data? = nil) async throws -> (Data, HTTPURLResponse?) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let h = cookieHeader(for: url, cookie: cookie) {
            req.setValue(h, forHTTPHeaderField: "Cookie")
        }
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        harvest(resp, requestURL: url)
        try check(resp)
        return (data, resp as? HTTPURLResponse)
    }

    private func formBody(_ fields: [String: String]) -> Data? {
        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery?.data(using: .utf8)
    }

    @discardableResult
    func get(_ url: URL, cookie: String? = nil) async throws -> Data {
        try await send(url, method: "GET", cookie: cookie).0
    }

    @discardableResult
    func postForm(_ url: URL, fields: [String: String], cookie: String? = nil) async throws -> Data {
        try await postFormWithHeaders(url, fields: fields, cookie: cookie).0
    }

    func postFormWithHeaders(_ url: URL, fields: [String: String], cookie: String? = nil) async throws -> (Data, String?) {
        let (data, resp) = try await send(url, method: "POST", cookie: cookie,
                                          contentType: "application/x-www-form-urlencoded",
                                          body: formBody(fields))
        return (data, resp?.value(forHTTPHeaderField: "Set-Cookie"))
    }

    @discardableResult
    func postMultipart(_ url: URL, multipart: Multipart, cookie: String?) async throws -> Data {
        try await send(url, method: "POST", cookie: cookie,
                       contentType: "multipart/form-data; boundary=\(multipart.boundary)",
                       body: multipart.finalized()).0
    }
}

extension Data {
    var utf8String: String { String(data: self, encoding: .utf8) ?? String(decoding: self, as: UTF8.self) }
}

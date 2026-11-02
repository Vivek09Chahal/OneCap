import Foundation

struct HTTPDownloader: Downloading {
    @concurrent func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        let settings = RequestSettings()
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(settings[.download])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await settings.data(for: request) {
            try await session.data(for: $0)
        }
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https",
              (200..<300).contains(http.statusCode)
                else { throw AppFailure("Download failed for \(url.host ?? "server").") }
        return data
    }
}

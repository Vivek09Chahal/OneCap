import Foundation

struct HTTPDownloader: Downloading {
    @concurrent func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https",
              (200..<300).contains(http.statusCode)
                else { throw AppFailure("Download failed for \(url.host ?? "server").") }
        return data
    }
}

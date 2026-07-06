import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An outgoing HTTP request as the client hands it to the transport.
public struct PulseHTTPRequest {
    /// Absolute URL string (endpoint + path).
    public let url: String
    /// Request path, e.g. "/v1/batch". Mock transports match on this.
    public let path: String
    /// Header fields. Names are sent as given; matching in tests is
    /// case-insensitive on names.
    public let headers: [String: String]
    /// UTF-8 JSON body.
    public let body: Data

    public init(url: String, path: String, headers: [String: String], body: Data) {
        self.url = url
        self.path = path
        self.headers = headers
        self.body = body
    }
}

/// A received HTTP response.
public struct PulseHTTPResponse {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Transport abstraction. All requests are POST. The completion may be
/// invoked on any thread; the client re-dispatches it onto its executor.
public protocol PulseTransport {
    func send(_ request: PulseHTTPRequest, completion: @escaping (Result<PulseHTTPResponse, Error>) -> Void)
}

public enum PulseTransportError: Error {
    case invalidURL
    case notAnHTTPResponse
}

/// Production transport backed by `URLSession`.
public final class PulseURLSessionTransport: PulseTransport {

    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: PulseHTTPRequest, completion: @escaping (Result<PulseHTTPResponse, Error>) -> Void) {
        guard let url = URL(string: request.url) else {
            completion(.failure(PulseTransportError.invalidURL))
            return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(PulseTransportError.notAnHTTPResponse))
                return
            }
            completion(.success(PulseHTTPResponse(status: http.statusCode, body: data ?? Data())))
        }
        task.resume()
    }
}

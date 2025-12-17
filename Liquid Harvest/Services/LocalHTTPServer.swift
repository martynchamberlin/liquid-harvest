//
//  LocalHTTPServer.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation
import Network

class LocalHTTPServer {
    private var listener: NWListener?
    private var port: UInt16 = 5006
    private var callback: ((String) -> Void)?
    private var errorCallback: ((String) -> Void)?

    func start(port: UInt16 = 5006, onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.port = port
        self.callback = onCode
        self.errorCallback = onError

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global())
        } catch {
            errorCallback?("Failed to start local server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self?.handleRequest(request, connection: connection)
            }

            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        print("🔵 Received HTTP request:")
        print(request.prefix(500)) // Print first 500 chars for debugging

        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            print("❌ No first line in request")
            return
        }

        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            print("❌ Invalid request line: \(firstLine)")
            return
        }

        let path = components[1]
        print("🔵 Request path: \(path)")

        if path.contains("?") {
            let urlComponents = path.components(separatedBy: "?")
            let queryString = urlComponents[1]
            // Handle fragment separator too (in case it's in the fragment)
            let actualQuery = queryString.components(separatedBy: "#").first ?? queryString
            let params = parseQueryString(actualQuery)

            if let error = params["error"] {
                errorCallback?(error)
            } else if let code = params["code"] {
                print("✅ Found authorization code, calling callback")
                callback?(code)
            } else {
                // Log what we received for debugging
                print("⚠️ Received callback but no code found. Query string: \(actualQuery)")
                print("⚠️ Params: \(params)")
                if let error = params["error"] {
                    print("❌ OAuth error: \(error)")
                    errorCallback?(error)
                }
            }
        }

        // Send response
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Liquid Harvest</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5; }
                .container { background: white; padding: 2em; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
                h1 { margin: 0 0 0.5em 0; }
                p { color: #666; margin: 0; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Liquid Harvest</h1>
                <p>You may now close this window and return to the app.</p>
            </div>
        </body>
        </html>
        """

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"

        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func parseQueryString(_ queryString: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = queryString.components(separatedBy: "&")

        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            if keyValue.count == 2 {
                let key = keyValue[0].removingPercentEncoding ?? keyValue[0]
                let value = keyValue[1].removingPercentEncoding ?? keyValue[1]
                params[key] = value
            }
        }

        return params
    }
}


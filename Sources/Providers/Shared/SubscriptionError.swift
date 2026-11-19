import Foundation

enum SubscriptionError: LocalizedError {
    case message(String)
    case unauthorized(String)
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .unauthorized(let provider): return "\(provider) session expired or was rejected. Reconnect in Settings."
        case .http(429): return "Too many requests. Automatic refresh will retry later."
        case .http(let code): return "The usage service returned HTTP \(code)."
        }
    }
}

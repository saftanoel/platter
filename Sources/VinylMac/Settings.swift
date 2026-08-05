import Combine
import Foundation

enum BackdropStyle: String, CaseIterable, Identifiable {
    /// A flat wash tinted from the current cover's background colour.
    case albumTint
    /// The original mahogany desk.
    case mahogany

    var id: String { rawValue }

    var label: String {
        switch self {
        case .albumTint: return "Album colour"
        case .mahogany: return "Mahogany desk"
        }
    }
}

/// The handful of user choices the scene reads. Small enough to stay a single observable
/// object; the scene redraws only when one of these actually changes.
final class Settings: ObservableObject {
    private static let backdropKey = "backdropStyle"

    @Published var backdrop: BackdropStyle {
        didSet {
            guard backdrop != oldValue else { return }
            UserDefaults.standard.set(backdrop.rawValue, forKey: Self.backdropKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.backdropKey)
        backdrop = stored.flatMap(BackdropStyle.init(rawValue:)) ?? .albumTint
    }
}

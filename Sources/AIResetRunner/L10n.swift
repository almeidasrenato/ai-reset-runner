import Foundation

enum Language: String, CaseIterable {
    case en, pt

    static var current: Language {
        Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .en
    }
}

/// The string for the chosen language (English by default). Thread-safe:
/// provider errors are built off the main thread.
func L(_ en: String, _ pt: String) -> String {
    Language.current == .pt ? pt : en
}

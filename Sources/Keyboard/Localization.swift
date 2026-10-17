import Foundation

/// Looks a visible keyboard string up in the keyboard's own string catalog; falls back to the English text.
func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }

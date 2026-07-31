import Foundation

/// The version the menu bar shows. Duplicated in Resources/Info.plist; the
/// release workflow's preflight fails the build if the two ever disagree.
public enum CoreInfo {
    public static let version = "0.1.0"
}

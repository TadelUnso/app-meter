import Foundation

/// The project's outbound links, in one place so the menu never hand-rolls a URL.
public enum UpdateChecker {
    public static let repoPageURL = URL(string: "https://github.com/TadelUnso/app-meter")!
    public static let issuesPageURL = URL(string: "https://github.com/TadelUnso/app-meter/issues")!
    public static let releasesPageURL = URL(string: "https://github.com/TadelUnso/app-meter/releases")!
}

import Foundation
import Testing
@testable import AppMeterCore

@Suite("App Store Connect apps")
struct AppStoreConnectAppsTests {
    /// The shape /v1/apps answers with, trimmed to the two fields asked for.
    private static let json = """
    {"data":[
      {"type":"apps","id":"6789246448","attributes":{"name":"Бюро Знахідок","bundleId":"com.biuroznakhidok.app"}},
      {"type":"apps","id":"111","attributes":{"name":"No Bundle","bundleId":null}}
    ]}
    """

    @Test func readsTheBundleIdAndNameOfEachApp() throws {
        let apps = try AppStoreConnectClient.appsResponse(from: Data(Self.json.utf8))
        #expect(apps["6789246448"] == AppStoreApp(bundleID: "com.biuroznakhidok.app", name: "Бюро Знахідок"))
    }

    /// An app without a bundle id cannot be paired with anything, so it is left
    /// out rather than entered under an empty key.
    @Test func skipsAnAppWithNoBundleId() throws {
        let apps = try AppStoreConnectClient.appsResponse(from: Data(Self.json.utf8))
        #expect(apps["111"] == nil)
        #expect(apps.count == 1)
    }
}

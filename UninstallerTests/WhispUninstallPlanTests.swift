import XCTest
@testable import WhispUninstallerCore

final class WhispUninstallPlanTests: XCTestCase {
    func testDefaultItemsIncludeLegacyStoreAsExplicitOptIn() throws {
        let items = WhispInstallLayout.defaultItems()

        let legacyStore = try XCTUnwrap(items.first { $0.id == "legacyStore" })
        XCTAssertFalse(legacyStore.isSelectedByDefault)
        XCTAssertTrue(legacyStore.requiresExplicitSelection)
        XCTAssertEqual(
            legacyStore.paths.map(\.lastPathComponent),
            ["default.store", "default.store-wal", "default.store-shm"]
        )
    }

    func testDefaultItemsIncludeApplicationsAndAppSupportLocations() throws {
        let items = WhispInstallLayout.defaultItems()

        let applicationsItem = try XCTUnwrap(items.first { $0.id == "applications" })
        XCTAssertTrue(applicationsItem.paths.map(\.path).contains("/Applications/Whisp.app"))

        let appSupportItem = try XCTUnwrap(items.first { $0.id == "appSupport" })
        XCTAssertEqual(
            appSupportItem.paths.map(\.path),
            [FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Whisp", isDirectory: true)
                .path]
        )
    }

    func testPreferencesItemClearsAppDefaultsDomain() throws {
        let items = WhispInstallLayout.defaultItems()
        let preferencesItem = try XCTUnwrap(items.first { $0.id == "preferences" })

        switch preferencesItem.action {
        case .clearPreferenceDomain(let domain, let paths):
            XCTAssertEqual(domain, WhispInstallLayout.appBundleIdentifier)
            XCTAssertTrue(paths.contains {
                $0.path == FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/com.whisp.app.plist", isDirectory: false)
                    .path
            })
        default:
            XCTFail("Preferences item should clear the Whisp defaults domain")
        }
    }

    func testUninstallClearsPersistentDomainValues() throws {
        let suiteName = "WhispUninstallerCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "hasCompletedWelcome")
        defaults.set("1.1", forKey: "lastWelcomeVersion")

        let service = WhispUninstallerService(
            fileManager: .default,
            userDefaults: defaults,
            processRunner: { _, _ in ("", "", 0) }
        )

        let item = WhispUninstallItem(
            id: "preferences",
            title: "Preferences",
            detail: "",
            action: .clearPreferenceDomain(domain: suiteName, paths: []),
            isSelectedByDefault: true
        )

        _ = try service.uninstall(items: [item])

        XCTAssertNil(defaults.object(forKey: "hasCompletedWelcome"))
        XCTAssertNil(defaults.object(forKey: "lastWelcomeVersion"))
        XCTAssertTrue(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
    }
}
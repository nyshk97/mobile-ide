import XCTest
@testable import MobileIDE

final class ComposerStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ComposerStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testDraftIsPerSession() {
        let store = ComposerStore(defaults: defaults)
        XCTAssertEqual(store.draft(for: "a"), "")
        store.setDraft("途中まで", for: "a")
        XCTAssertEqual(store.draft(for: "a"), "途中まで")
        XCTAssertEqual(store.draft(for: "b"), "", "別セッションには漏れない")
        store.setDraft("", for: "a")
        XCTAssertEqual(store.draft(for: "a"), "")
        XCTAssertNil(defaults.object(forKey: ComposerStore.draftKey("a")), "空にしたらキーごと消す")
    }

    @MainActor
    func testModeDefaultsToComposerAndPersists() {
        let store = ComposerStore(defaults: defaults)
        XCTAssertEqual(store.mode(for: "a"), .composer)
        store.setMode(.direct, for: "a")
        XCTAssertEqual(store.mode(for: "a"), .direct)
        XCTAssertEqual(store.mode(for: "b"), .composer, "別セッションは既定のまま")
        // 別のインスタンス（= 次回起動）でも読める
        XCTAssertEqual(ComposerStore(defaults: defaults).mode(for: "a"), .direct)
        XCTAssertEqual(ComposerStore(defaults: defaults).draft(for: "a"), "")
    }

    @MainActor
    func testUnknownStoredModeFallsBackToComposer() {
        defaults.set("garbage", forKey: ComposerStore.modeKey("a"))
        XCTAssertEqual(ComposerStore(defaults: defaults).mode(for: "a"), .composer)
    }

    func testToggle() {
        XCTAssertEqual(InputMode.composer.toggled, .direct)
        XCTAssertEqual(InputMode.direct.toggled, .composer)
    }
}

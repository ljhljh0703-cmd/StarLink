import XCTest
@testable import StarLink

final class StarLinkTests: XCTestCase {
    
    func testBaselineAssertion() {
        // Simple test to verify the testing target works correctly.
        XCTAssertTrue(true, "Baseline verification should pass.")
    }
    
    func testAppConfigDefaults() {
        // Verify defaults or bundle structure
        let bundle = Bundle(for: type(of: self))
        XCTAssertNotNil(bundle, "Bundle should be loadable.")
    }
}

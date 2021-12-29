import XCTest
@testable import SharingCore

final class SharingCoreTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.


        var p = 0;
        guard let pC = SharingCoreInit(extra: &p, cb: { sender, pointer, size in
            print("收到数据：\(size)")
        }) else {
            print("init sharing core failed")
            return
        }

        print("begin")
        SharingCoreBeginScreenCapture(pointer: pC)
        print("begin end")

        print("sleep")
        sleep(10)
        print("sleep end")

        print("stop")
        SharingCoreStopScreenCapture(pointer: pC)
        print("stop end")

        print("deallocate")
        SharingCoreDeallocate(pointer: pC)
        print("deallocate end")
    }
}

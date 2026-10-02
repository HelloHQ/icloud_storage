import Foundation
import XCTest
@testable import ICloudDownload

private final class MetadataItem: NSMetadataItem {
  private let url: URL?

  init(path: String?) {
    url = path.map { URL(fileURLWithPath: $0) }
    super.init()
  }

  override func value(forAttribute key: String) -> Any? {
    return key == NSMetadataItemURLKey ? url : nil
  }
}

private final class MetadataQuery: NSMetadataQuery {
  var items: [Any] = []
  var stopCount = 0

  override var results: [Any] { items }

  override func stop() {
    stopCount += 1
  }
}

private final class ObserverCapture {}

final class DownloadQueryTests: XCTestCase {
  private let wantedPath = "/icloud-storage-tests/container/Documents/backup.zip"

  private func makeDownload(_ query: MetadataQuery, center: NotificationCenter = NotificationCenter()) -> DownloadQuery {
    return DownloadQuery(query: query, cloudFileURL: URL(fileURLWithPath: wantedPath), notificationCenter: center)
  }

  func testSelectsRequestedPathInsteadOfFirstSameNamedFile() {
    let query = MetadataQuery()
    let wanted = MetadataItem(path: wantedPath)
    query.items = [
      MetadataItem(path: "/icloud-storage-tests/container/Documents/old/backup.zip"),
      MetadataItem(path: "/icloud-storage-tests/container/backup.zip"),
      MetadataItem(path: "/icloud-storage-tests/other-container/Documents/backup.zip"),
      MetadataItem(path: "/icloud-storage-tests/container/archive/Documents/backup.zip"),
      wanted,
    ]
    XCTAssertTrue(makeDownload(query).matchingItem() === wanted)
  }

  func testSameNamedFileDoesNotSuppressMissingFileTimeout() {
    let query = MetadataQuery()
    query.items = [MetadataItem(path: "/icloud-storage-tests/container/backup.zip")]
    let download = makeDownload(query)
    XCTAssertNil(download.matchingItem())
    XCTAssertTrue(download.stopIfNotFound())
    XCTAssertFalse(download.isActive)
    XCTAssertEqual(query.stopCount, 1)
  }

  func testFindsRemoteItemWithoutLocalPlaceholder() {
    XCTAssertFalse(FileManager.default.fileExists(atPath: wantedPath))
    let query = MetadataQuery()
    let wanted = MetadataItem(path: wantedPath)
    query.items = [wanted]
    let download = makeDownload(query)
    XCTAssertTrue(download.matchingItem() === wanted)
    XCTAssertFalse(download.stopIfNotFound())
    XCTAssertTrue(download.isActive)
  }

  func testSkipsInvalidResultsAndStandardizesPaths() {
    let query = MetadataQuery()
    let wanted = MetadataItem(path: "/icloud-storage-tests/container/Documents/old/../backup.zip")
    query.items = ["not metadata", MetadataItem(path: nil), wanted]
    XCTAssertTrue(makeDownload(query).matchingItem() === wanted)
  }

  func testConcurrentDownloadsHaveIndependentRequestState() {
    // No event channel is needed to identify or track either request.
    let first = makeDownload(MetadataQuery())
    let second = makeDownload(MetadataQuery())
    XCTAssertNotEqual(first.id, second.id)
    XCTAssertEqual(first.beginCheck(), true)
    XCTAssertEqual(second.beginCheck(), true)
    XCTAssertNil(first.beginCheck())
    first.endCheck()
    XCTAssertEqual(first.beginCheck(), false)
    first.stop()
    XCTAssertNil(first.beginCheck())
    XCTAssertNil(second.beginCheck())
    second.endCheck()
    XCTAssertEqual(second.beginCheck(), false)
  }

  func testStopRemovesBothObserverTokensAndReleasesCaptures() {
    let center = NotificationCenter()
    let query = MetadataQuery()
    let download = makeDownload(query, center: center)
    var updates = 0
    var capture: ObserverCapture? = ObserverCapture()
    weak var weakCapture = capture
    download.observe { [heldCapture = capture!] _ in
      _ = heldCapture
      updates += 1
    }
    capture = nil
    center.post(name: .NSMetadataQueryDidFinishGathering, object: query)
    center.post(name: .NSMetadataQueryDidUpdate, object: query)
    XCTAssertEqual(updates, 2)
    XCTAssertNotNil(weakCapture)
    download.stop()
    XCTAssertNil(weakCapture)
    center.post(name: .NSMetadataQueryDidFinishGathering, object: query)
    center.post(name: .NSMetadataQueryDidUpdate, object: query)
    XCTAssertEqual(updates, 2)
    download.stop()
    XCTAssertEqual(query.stopCount, 1)
  }

  func testMissingFileTimeoutCleansUpWithoutEventChannel() {
    let center = NotificationCenter()
    let query = MetadataQuery()
    let download = makeDownload(query, center: center)
    var capture: ObserverCapture? = ObserverCapture()
    weak var weakCapture = capture
    download.observe { [heldCapture = capture!] _ in _ = heldCapture }
    capture = nil
    XCTAssertTrue(download.stopIfNotFound())
    XCTAssertNil(weakCapture)
    XCTAssertNil(download.beginCheck())
    XCTAssertFalse(download.stopIfNotFound())
    XCTAssertEqual(query.stopCount, 1)
  }

  func testCompletedDownloadDoesNotLaterReportNotFound() {
    let query = MetadataQuery()
    let download = makeDownload(query)
    download.stop()
    XCTAssertFalse(download.stopIfNotFound())
    XCTAssertEqual(query.stopCount, 1)
  }

  func testDeinitRemovesObservers() {
    let center = NotificationCenter()
    let query = MetadataQuery()
    var download: DownloadQuery? = makeDownload(query, center: center)
    weak var weakDownload = download
    var capture: ObserverCapture? = ObserverCapture()
    weak var weakCapture = capture
    download?.observe { [heldCapture = capture!] _ in _ = heldCapture }
    capture = nil
    download = nil
    XCTAssertNil(weakDownload)
    XCTAssertNil(weakCapture)
    XCTAssertEqual(query.stopCount, 1)
  }
}

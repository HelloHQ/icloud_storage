import Foundation

@_silgen_name("icloud_file_probe_start") private func startProbe()
@_silgen_name("icloud_file_probe_stop") private func stopProbe() -> Int32

private final class ProbeMetadataItem: NSMetadataItem {
  let url: URL

  init(path: String) {
    url = URL(fileURLWithPath: path, isDirectory: false)
    super.init()
  }

  override func value(forAttribute key: String) -> Any? {
    key == NSMetadataItemURLKey ? url : nil
  }
}

private final class ProbeMetadataQuery: NSMetadataQuery {
  var items: [Any] = []
  override var results: [Any] { items }
  override func stop() {}
}

@main
private struct DownloadFilesystemProbe {
  static func main() {
    let path = "/icloud-storage-tests/no-filesystem-lookup/backup.zip"

    // The original freeze came from this initializer's implicit directory
    // lookup. Calibration must observe that lookup; zero would be a false pass.
    startProbe()
    _ = URL(fileURLWithPath: path).hasDirectoryPath
    guard stopProbe() > 0 else {
      print("FAIL: filesystem probe did not observe URL directory inference")
      exit(1)
    }

    let url = URL(fileURLWithPath: path, isDirectory: false)
    let query = ProbeMetadataQuery()
    let wanted = ProbeMetadataItem(path: path)
    query.items = [ProbeMetadataItem(path: path + ".old"), wanted]

    startProbe()
    let download = DownloadQuery(query: query, cloudFileURL: url, notificationCenter: NotificationCenter())
    let matched = download.matchingItem()
    let lookups = stopProbe()

    guard matched === wanted, lookups == 0 else {
      print("FAIL: download matching performed \(lookups) filesystem lookups")
      exit(1)
    }
    print("PASS: download initialization and matching performed zero filesystem lookups")
  }
}

import Foundation

// One instance per download, including calls without a progress event channel.
// Query state and observer ownership are confined to the main queue.
final class DownloadQuery {
  let id = UUID()
  let query: NSMetadataQuery
  private(set) var isActive = true
  private let cloudFileURL: URL
  private let notificationCenter: NotificationCenter
  private var observerTokens: [NSObjectProtocol] = []
  private var pendingCheck = false
  private var requestedDownload = false

  init(query: NSMetadataQuery, cloudFileURL: URL, notificationCenter: NotificationCenter = .default) {
    self.query = query
    self.cloudFileURL = cloudFileURL.standardizedFileURL
    self.notificationCenter = notificationCenter
  }

  func matchingItem() -> NSMetadataItem? {
    guard isActive else { return nil }
    // Discovery uses the filename, but selection must also match the container
    // and relative path. A URL match does not require a local placeholder.
    return query.results.compactMap { $0 as? NSMetadataItem }.first { item in
      guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return false }
      return url.standardizedFileURL.path == cloudFileURL.path
    }
  }

  func observe(_ onUpdate: @escaping (DownloadQuery) -> Void) {
    for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, NSNotification.Name.NSMetadataQueryDidUpdate] {
      let token = notificationCenter.addObserver(forName: name, object: query, queue: query.operationQueue) { [weak self] _ in
        guard let self = self, self.isActive else { return }
        onUpdate(self)
      }
      observerTokens.append(token)
    }
  }

  // nil means a check is already running or the query has finished. Otherwise,
  // the value indicates whether this call must request the download from iCloud.
  func beginCheck() -> Bool? {
    guard isActive, !pendingCheck else { return nil }
    pendingCheck = true
    let needsDownloadRequest = !requestedDownload
    requestedDownload = true
    return needsDownloadRequest
  }

  func endCheck() {
    pendingCheck = false
  }

  func stopIfNotFound() -> Bool {
    guard isActive, matchingItem() == nil else { return false }
    stop()
    return true
  }

  func stop() {
    guard isActive else { return }
    isActive = false
    pendingCheck = false
    requestedDownload = false
    query.stop()
    for token in observerTokens {
      notificationCenter.removeObserver(token)
    }
    observerTokens.removeAll()
  }

  deinit {
    stop()
  }
}

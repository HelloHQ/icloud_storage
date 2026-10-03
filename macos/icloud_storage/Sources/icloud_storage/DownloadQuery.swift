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
    self.cloudFileURL = URL(fileURLWithPath: DownloadQuery.canonicalPath(cloudFileURL))
    self.notificationCenter = notificationCenter
  }

  func matchingItem() -> NSMetadataItem? {
    guard isActive else { return nil }
    // Discovery uses the filename, but selection must also match the container
    // and relative path. A URL match does not require a local placeholder.
    return query.results.compactMap { $0 as? NSMetadataItem }.first { item in
      guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return false }
      return DownloadQuery.canonicalPath(url) == cloudFileURL.path
    }
  }

  // The container URL and the metadata item URL can spell the same file
  // differently: /var, /tmp and /etc are symlinks to /private/..., and the
  // two APIs do not agree on which form they return (iOS containers live under
  // /private/var/mobile). Normalize lexically so no file system call runs on
  // the main thread and files without a local placeholder still compare.
  static func canonicalPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    for alias in ["/private/var/", "/private/tmp/", "/private/etc/"] where path.hasPrefix(alias) {
      return String(path.dropFirst("/private".count))
    }
    return path
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
    // The last reference can be dropped on a background queue (the status
    // check runs off the main thread). Observer removal is thread-safe, but
    // NSMetadataQuery belongs to the main queue, so stop it there.
    guard isActive else { return }
    isActive = false
    for token in observerTokens {
      notificationCenter.removeObserver(token)
    }
    let query = self.query
    if Thread.isMainThread {
      query.stop()
    } else {
      DispatchQueue.main.async { query.stop() }
    }
  }
}

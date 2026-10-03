import Flutter
import UIKit

public class IcloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  var streamHandlers: [String: StreamHandler] = [:]
  private var downloadQueries: [UUID: DownloadQuery] = [:]
  let querySearchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope];
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: "icloud_storage", binaryMessenger: messenger)
    let instance = IcloudStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.messenger = messenger
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "gather":
      gather(call, result)
    case "upload":
      upload(call, result)
    case "download":
      download(call, result)
    case "delete":
      delete(call, result)
    case "move":
      move(call, result)
    case "createEventChannel":
      createEventChannel(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func gather(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    addGatherFilesObservers(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
    
    if !eventChannelName.isEmpty {
      let streamHandler = self.streamHandlers[eventChannelName]!
      streamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
    query.start()
  }
  
  private func addGatherFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) {
      [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        removeObservers(query)
        if eventChannelName.isEmpty { query.stop() }
        result(files)
    }
    
    if !eventChannelName.isEmpty {
      NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) {
        [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        let streamHandler = self.streamHandlers[eventChannelName]!
        streamHandler.setEvent(files)
      }
    }
  }
  
  private func mapFileAttributesFromQuery(query: NSMetadataQuery, containerURL: URL) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    for item in query.results {
      guard let fileItem = item as? NSMetadataItem else { continue }
      guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
      if fileURL.absoluteString.last == "/" { continue }

      let map: [String: Any?] = [
        "relativePath": String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count)),
        "sizeInBytes": fileItem.value(forAttribute: NSMetadataItemFSSizeKey),
        "creationDate": (fileItem.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date)?.timeIntervalSince1970,
        "contentChangeDate": (fileItem.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970,
        "hasUnresolvedConflicts": fileItem.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey),
        "downloadStatus": fileItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey),
        "isDownloading": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey),
        "isUploaded": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey),
        "isUploading": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey),
      ]
      fileMaps.append(map)
    }
    return fileMaps
  }
  
  private func upload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    let localFileURL = URL(fileURLWithPath: localFilePath)
    
    do {
      if FileManager.default.fileExists(atPath: cloudFileURL.path) {
        try FileManager.default.removeItem(at: cloudFileURL)
      } else {
        let cloudFileDirURL = cloudFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cloudFileDirURL.path) {
          try FileManager.default.createDirectory(at: cloudFileDirURL, withIntermediateDirectories: true, attributes: nil)
        }
      }
      try FileManager.default.copyItem(at: localFileURL, to: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
    }
    
    if !eventChannelName.isEmpty {
      let query = NSMetadataQuery.init()
      query.operationQueue = .main
      query.searchScopes = querySearchScopes
      query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
      
      let uploadStreamHandler = self.streamHandlers[eventChannelName]!
      uploadStreamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
      addUploadObservers(query: query, eventChannelName: eventChannelName)
      
      query.start()
    }
    
    result(nil)
  }
  
  private func addUploadObservers(query: NSMetadataQuery, eventChannelName: String) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
  }
  
  private func onUploadQueryNotification(query: NSMetadataQuery, eventChannelName: String) {
    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemUploadingErrorKey]) else { return}
    guard let streamHandler = self.streamHandlers[eventChannelName] else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      streamHandler.setEvent(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      streamHandler.setEvent(progress)
      if (progress >= 100) {
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  private func download(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }

    // Cancellation can arrive while iCloud is still resolving the container.
    streamHandlers[eventChannelName]?.onCancelHandler = { [weak self] in
      self?.removeStreamHandler(eventChannelName)
    }

    // Resolving the ubiquity container can block on filesystem metadata.
    // Discover the remote item with NSMetadataQuery before requesting its data:
    // another device's file may not have a local placeholder path yet.
    DispatchQueue.global(qos: .utility).async { [self] in
      guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
      else {
        DispatchQueue.main.async { [self] in
          streamHandlers[eventChannelName]?.onCancelHandler = nil
          removeStreamHandler(eventChannelName)
          result(containerError)
        }
        return
      }

      let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
      DispatchQueue.main.async { [self] in
        guard eventChannelName.isEmpty || streamHandlers[eventChannelName] != nil else {
          result(FlutterError(code: "E_CANCEL", message: "Download cancelled", details: nil))
          return
        }
        let query = NSMetadataQuery()
        query.operationQueue = .main
        query.searchScopes = querySearchScopes
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, cloudFileURL.lastPathComponent)
        let download = DownloadQuery(query: query, cloudFileURL: cloudFileURL)
        downloadQueries[download.id] = download

        let downloadStreamHandler = streamHandlers[eventChannelName]
        downloadStreamHandler?.onCancelHandler = { [weak self, weak download] in
          guard let self = self, let download = download else { return }
          self.finishDownload(download, eventChannelName: eventChannelName)
        }

        let localFileURL = URL(fileURLWithPath: localFilePath)
        download.observe { [weak self] download in
          self?.onDownloadQueryNotification(download: download, localFileURL: localFileURL, eventChannelName: eventChannelName)
        }

        query.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self, weak download] in
          guard let self = self, let download = download,
                download.stopIfNotFound() else { return }
          self.streamHandlers[eventChannelName]?.setEvent(self.fileNotFoundError)
          self.finishDownload(download, eventChannelName: eventChannelName)
        }
        result(nil)
      }
    }
  }

  private func finishDownload(_ download: DownloadQuery, eventChannelName: String) {
    download.stop()
    downloadQueries.removeValue(forKey: download.id)
    streamHandlers[eventChannelName]?.onCancelHandler = nil
    removeStreamHandler(eventChannelName)
  }

  private func onDownloadQueryNotification(download: DownloadQuery, localFileURL: URL, eventChannelName: String) {
    guard let fileItem = download.matchingItem() else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard eventChannelName.isEmpty || streamHandlers[eventChannelName] != nil,
          let needsDownloadRequest = download.beginCheck() else { return }

    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      streamHandlers[eventChannelName]?.setEvent(progress)
    }

    // Resource values and the final copy may also block while iCloud hydrates
    // the file. Report their outcome on the main thread with the event stream.
    DispatchQueue.global(qos: .utility).async { [self] in
      var downloadError: FlutterError?
      var copied = false
      var stage = "request_download"
      do {
        if needsDownloadRequest {
          try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }
        stage = "read_download_status"
        let values = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadingStatusKey])
        if let error = values.ubiquitousItemDownloadingError {
          downloadError = nativeCodeError(error, stage: stage)
        } else if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
          stage = "copy_downloaded_file"
          try moveCloudFile(at: fileURL, to: localFileURL)
          copied = true
        }
      } catch {
        downloadError = nativeCodeError(error, stage: stage)
      }

      let outcomeError = downloadError
      let didCopy = copied
      DispatchQueue.main.async { [self] in
        guard download.isActive else { return }
        download.endCheck()
        guard eventChannelName.isEmpty || streamHandlers[eventChannelName] != nil else { return }
        let streamHandler = streamHandlers[eventChannelName]
        if let outcomeError = outcomeError {
          streamHandler?.setEvent(outcomeError)
        } else if didCopy {
          streamHandler?.setEvent(FlutterEndOfEventStream)
        } else {
          return
        }
        finishDownload(download, eventChannelName: eventChannelName)
      }
    }
  }

  private func moveCloudFile(at: URL, to: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
      }
      try FileManager.default.copyItem(at: at, to: to)
    } catch {
      throw error
    }
  }
  
  private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudFileName = args["cloudFileName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let fileURL = containerURL.appendingPathComponent(cloudFileName)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: fileURL, options: NSFileCoordinator.WritingOptions.forDeleting, error: nil) {
      writingURL in
      do {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: writingURL.path, isDirectory: &isDir) {
          result(fileNotFoundError)
          return
        }
        try FileManager.default.removeItem(at: writingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func move(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let atRelativePath = args["atRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let atURL = containerURL.appendingPathComponent(atRelativePath)
    let toURL = containerURL.appendingPathComponent(toRelativePath)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: atURL, options: NSFileCoordinator.WritingOptions.forMoving, writingItemAt: toURL, options: NSFileCoordinator.WritingOptions.forReplacing, error: nil) {
      atWritingURL, toWritingURL in
      do {
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(at: toDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func removeObservers(_ query: NSMetadataQuery) {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidUpdate, object: query)
  }
  
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: self.messenger!)
    eventChannel.setStreamHandler(streamHandler)
    self.streamHandlers[eventChannelName] = streamHandler
    
    result(nil)
  }
  
  private func removeStreamHandler(_ eventChannelName: String) {
    self.streamHandlers[eventChannelName] = nil
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCloud permission", details: nil)
  let fileNotFoundError = FlutterError(code: "E_FNF", message: "The file does not exist", details: nil)
  
  private func nativeCodeError(_ error: Error, stage: String? = nil) -> FlutterError {
    // Formatting Error/NSError can synchronously read URL resource metadata.
    // That operation stalled the simulator's Flutter main thread on download.
    let nativeError = error as NSError
    var details: [String: Any] = ["domain": nativeError.domain, "code": nativeError.code]
    if let stage = stage { details["stage"] = stage }
    return FlutterError(code: "E_NAT", message: "Native Code Error", details: details)
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var _eventSink: FlutterEventSink?
  var onCancelHandler: (() -> Void)?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    _eventSink = events
    DebugHelper.log("on listen")
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelHandler?()
    _eventSink = nil
    DebugHelper.log("on cancel")
    return nil
  }
  
  func setEvent(_ data: Any) {
    _eventSink?(data)
  }
}

class DebugHelper {
  public static func log(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}

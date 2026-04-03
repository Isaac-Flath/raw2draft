import Foundation

/// Event representing a file system change.
struct FileChangeEvent {
    enum ChangeType {
        case added
        case changed
        case removed
    }

    let type: ChangeType
    /// Absolute path to the changed file.
    let absolutePath: String
    /// Relative path within the watched directory (e.g. "content/blog.md" or "notes/ideas.md").
    let path: String
    /// Project ID (only set in content-studio mode).
    let projectId: String?
}

/// Protocol for file watching.
protocol FileWatcherServiceProtocol {
    var fileChanges: AsyncStream<FileChangeEvent> { get }
    func startWatching(projectsDirectory: URL)
    func startWatching(directory: URL)
    func stopWatching()
}

/// FSEvents-based file system watcher.
final class FileWatcherService: FileWatcherServiceProtocol {
    let fileChanges: AsyncStream<FileChangeEvent>
    private let continuation: AsyncStream<FileChangeEvent>.Continuation

    private var stream: FSEventStreamRef?
    private var streamContext: FSEventStreamContext?
    private var watchedDirectory: URL?
    private var mode: WatchMode = .generic

    private enum WatchMode {
        case contentStudio  // Filter to known subdirs, parse projectId
        case generic        // Watch everything, no projectId parsing
    }

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: FileChangeEvent.self)
        self.fileChanges = stream
        self.continuation = continuation
    }

    /// Watch a content-platform projects directory (filters to known subdirs, parses projectId).
    func startWatching(projectsDirectory: URL) {
        mode = .contentStudio
        startStream(directory: projectsDirectory)
    }

    /// Watch any directory recursively (no filtering, no projectId).
    func startWatching(directory: URL) {
        mode = .generic
        startStream(directory: directory)
    }

    func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stopWatching()
        continuation.finish()
    }

    // MARK: - Private

    private func startStream(directory: URL) {
        self.watchedDirectory = directory
        stopWatching()

        let pathToWatch = directory.path as CFString
        let pathsToWatch = [pathToWatch] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        self.streamContext = context

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            CFTimeInterval(Double(Constants.watcherStabilityThresholdMs) / 1000.0),
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    // MARK: - Event Processing

    fileprivate func handleEvent(path: String, flags: FSEventStreamEventFlags) {
        // Ignore directory-level events (we only care about files)
        if flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { return }

        guard let watchedDirectory else { return }
        let rootPath = watchedDirectory.path

        guard path.hasPrefix(rootPath) else { return }
        let relative = String(path.dropFirst(rootPath.count + 1)) // +1 for /
        guard !relative.isEmpty else { return }

        let changeType: FileChangeEvent.ChangeType
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            changeType = .removed
        } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            changeType = .added
        } else {
            changeType = .changed
        }

        switch mode {
        case .contentStudio:
            handleContentStudioEvent(absolutePath: path, relative: relative, changeType: changeType)
        case .generic:
            let event = FileChangeEvent(
                type: changeType,
                absolutePath: path,
                path: relative,
                projectId: nil
            )
            continuation.yield(event)
        }
    }

    private func handleContentStudioEvent(absolutePath: String, relative: String, changeType: FileChangeEvent.ChangeType) {
        let components = relative.split(separator: "/")
        guard components.count >= 2 else { return }

        let projectId = String(components[0])
        let subdir = String(components[1])

        // Strip project ID prefix so path is project-relative (e.g. "content/blog.md")
        let subPath = components.dropFirst().joined(separator: "/")

        let event = FileChangeEvent(
            type: changeType,
            absolutePath: absolutePath,
            path: subPath,
            projectId: projectId
        )

        continuation.yield(event)
    }
}

// MARK: - FSEvents Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let service = Unmanaged<FileWatcherService>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    for i in 0..<numEvents {
        service.handleEvent(path: paths[i], flags: eventFlags[i])
    }
}

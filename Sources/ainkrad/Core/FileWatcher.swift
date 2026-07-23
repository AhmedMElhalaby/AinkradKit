import CoreServices
import Foundation

/// The real `DevSessionChangeSource`: watches `directory` for filesystem
/// activity via an FSEvents stream, and calls `onChange` for each raw
/// notification. Deliberately dumb — no debouncing, no diffing of which
/// file changed — because `DevSession` owns debouncing (via its injected
/// `DevSessionScheduler`) so that logic can be unit-tested without FSEvents.
///
/// FSEvents (rather than a single `DispatchSource` on the directory's own
/// fd) is the correct API here because it is natively **recursive**: it
/// reports changes anywhere under `directory`'s subtree, not just to
/// `directory`'s own entries. A scaffolded Ainkrad app's editable sources
/// live two levels down (`Sources/Plugin/PluginApp.swift`), so a
/// non-recursive watch on the project root would never see the mainline
/// "edit a source file and save" event — the whole point of `ainkrad dev`.
final class FileWatcher: DevSessionChangeSource {
    private let directory: URL
    private var stream: FSEventStreamRef?

    var onChange: (() -> Void)?

    init(directory: URL) {
        self.directory = directory
    }

    func start() throws {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [directory.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FileWatcher.eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            throw DevSessionError(
                description: "Could not create an FSEvents stream to watch \(directory.path) for changes."
            )
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw DevSessionError(
                description: "Could not start the FSEvents stream watching \(directory.path)."
            )
        }

        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    /// The C callback FSEvents invokes on the stream's dispatch queue for
    /// every batch of events. `clientCallBackInfo` is the `FileWatcher`
    /// instance passed in unretained via the stream's context; we don't
    /// care which paths changed or how, only that something did, so every
    /// batch — regardless of size — becomes exactly one `onChange` call.
    /// `DevSession`'s injected scheduler is what turns a burst of these
    /// into a single rebuild.
    private static let eventCallback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
        guard let clientCallBackInfo else { return }
        let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
        watcher.onChange?()
    }
}

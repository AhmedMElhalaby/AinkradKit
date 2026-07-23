import Foundation

/// The real `DevSessionChangeSource`: watches a directory for filesystem
/// activity via a `DispatchSource` file-system-object source on the
/// directory's file descriptor, and calls `onChange` for each raw
/// notification. Deliberately dumb — no debouncing, no diffing of which
/// file changed — because `DevSession` owns debouncing (via its injected
/// `DevSessionScheduler`) so that logic can be unit-tested without FSEvents.
///
/// Watches `directory` itself, not a recursive tree: `DispatchSource`'s
/// `.write` event on a directory fires when an entry inside it is added,
/// removed, or renamed, which is what a build tool cares about for "did the
/// project change" purposes. A nested-directory rewrite would need a
/// recursive watcher (or FSEvents) — out of scope for this thin front end.
final class FileWatcher: DevSessionChangeSource {
    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    var onChange: (() -> Void)?

    init(directory: URL) {
        self.directory = directory
    }

    func start() throws {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw DevSessionError(
                description: "Could not watch \(directory.path) for changes (errno \(errno))."
            )
        }
        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .extend, .rename, .attrib],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.onChange?()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}

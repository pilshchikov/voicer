import Foundation

enum DebugLog {
    static let url = URL.libraryDirectory.appending(path: "Logs/Voicer.log")
    private static let queue = DispatchQueue(label: "voicer.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

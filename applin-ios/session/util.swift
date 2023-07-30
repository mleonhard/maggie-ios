import Foundation

// TODO: Put all of these inside a Util class.

func createDir(_ path: String) async throws {
    let task = Task {
        do {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw ApplinError.appError("error creating directory '\(path)': \(error)")
        }
    }
    try await task.value
}

func decodeJson<T: Decodable>(_ data: Data) throws -> T {
    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        throw "error decoding \(data.count) bytes as JSON to \(String(describing: T.self)): \(error)"
    }
}

func encodeJson<T: Encodable>(_ item: T) throws -> Data {
    do {
        let encoder = JSONEncoder()
        return try encoder.encode(item)
    } catch {
        throw "error encoding \(String(describing: item)) as JSON: \(error)"
    }
}

func deleteFile(path: String) async throws {
    let task = Task {
        do {
            // Apple's docs don't say what happens when the file doesn't exist.
            // https://developer.apple.com/documentation/foundation/filemanager/1408573-removeitem
            // Here's what I get from iOS 15 in Simulator:
            // Error Domain=NSCocoaErrorDomain Code=4 "'cache.json.tmp' couldn't be removed."
            // UserInfo={
            //   NSUserStringVariant=(Remove),
            //   NSFilePath=/Users/user/Library/Developer/CoreSimulator/Devices/61ED91D5-4782-4D6C-B943-74774C383CEC/data/
            //     Containers/Data/Application/CDF87840-5B50-4217-A2AC-5CC345A52A9B/Documents/cache.json.tmp,
            //   NSUnderlyingError=0x600000d541e0 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}
            // }
            // Apple docs also don't list the constant values.  And the editor won't show the values.
            // I printed out the value of kCFNotFound, which printed as -1.  But that value is not found in the error.
            // So I give up making this method idempotent.
            if !FileManager.default.fileExists(atPath: path) {
                return
            }
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw ApplinError.appError("error deleting file '\(path)': \(error)")
        }
    }
    try await task.value
}

func fileExists(path: String) async -> Bool {
    let task: Task<Bool, Never> = Task {
        FileManager.default.fileExists(atPath: path)
    }
    return await task.value
}

func getCacheDirPath() -> String {
    let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    return urls[0].path
}

func getDataDirPath() -> String {
    let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    return urls[0].path
}

func getTempDirPath() -> String {
    FileManager.default.temporaryDirectory.path
}

func moveFile(atPath: String, toPath: String) async throws {
    let task = Task {
        do {
            try FileManager.default.moveItem(atPath: atPath, toPath: toPath)
        } catch {
            throw ApplinError.appError("error moving file '\(atPath)' to '\(toPath)': \(error)")
        }
    }
    try await task.value
}

func readBundleFile(filepath: String) async throws -> Data {
    guard let url = Bundle.main.url(forResource: filepath, withExtension: nil)
    else {
        throw ApplinError.appError("bundle file not found: \(filepath)")
    }
    //print("readBundleFile(\(filename) reading \(url.absoluteString)")
    //file:///Users/user/Library/Developer/CoreSimulator/Devices/76F2E4B6E4C9/data/Containers/Bundle/Application/1D1493CF6169/applin-ios.app/default.json
    do {
        return try Data(contentsOf: url)
    } catch {
        throw ApplinError.appError("error reading bundle file \(filepath): \(error)")
    }
}

func readFile(path: String) async throws -> Data {
    let task: Task<Data, Error> = Task {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ApplinError.appError("error reading file '\(path)': \(error)")
        }
    }
    return try await task.value
}

/// Returns early when the task is cancelled.
func sleep(ms: Int) async {
    do {
        let nanoseconds = UInt64(ms).saturatingMultiply(1_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    } catch {
    }
}

func writeFile(data: Data, path: String) async throws {
    let task = Task {
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw ApplinError.appError("error writing file '\(path)': \(error)")
        }
    }
    try await task.value
}

extension Array {
    func get(_ index: Int) -> Element? {
        if index < self.count {
            return self[index]
        } else {
            return nil
        }
    }
}

extension Date {
    func secondsSinceEpoch() -> UInt64 {
        let doubleSeconds = self.timeIntervalSince1970
        if !doubleSeconds.isFinite {
            return 0
        }
        if doubleSeconds < 0.0 {
            return 0
        }
        if doubleSeconds > Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(doubleSeconds)
    }
}

extension Dictionary {
    func compactMap2<R>(_ f: (Key, Value) -> R?) -> Dictionary<Key, R> {
        Dictionary<Key, R>(uniqueKeysWithValues: self.compactMap { (key, value) in
            if let result: R = f(key, value) {
                return (key, result)
            } else {
                return nil
            }
        })
    }
}

extension HTTPURLResponse {
    func contentTypeBase() -> String? {
        if let mimeType = self.mimeType {
            return mimeType
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                    .lowercased()
        } else {
            return nil
        }
    }

    func dateHeader() throws -> Date {
        guard let headerValue = self.value(forHTTPHeaderField: "Date") else {
            throw ApplinError.serverError("missing 'Date' header")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Date
        //   Date: <day-name>, <day> <month> <year> <hour>:<minute>:<second> GMT
        //   Date: Wed, 21 Oct 2015 07:28:00 GMT
        // https://www.unicode.org/reports/tr35/tr35-31/tr35-dates.html#Date_Format_Patterns
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: headerValue) else {
            throw ApplinError.serverError("'Date' header has unexpected format: \(String(describing: headerValue))")
        }
        return date
    }

    func eTagHeader() throws -> String {
        guard let headerValue = self.value(forHTTPHeaderField: "eTag") else {
            throw ApplinError.serverError("missing 'eTag' header")
        }
        if headerValue.isEmpty {
            throw ApplinError.serverError("'eTag' header is empty")
        }
        return headerValue
    }

    func maxAgeHeader() -> UInt64? {
        guard let headerValue = self.value(forHTTPHeaderField: "Cache-Control") else {
            return nil
        }
        // Swift finally got a decent Regex class, but it's only for iOS 16, so we use the old one.
        guard let groups = NSRegularExpression("\\bmax-age=([0-9]+)\\b").firstMatchGroups(headerValue) else {
            return nil
        }
        return UInt64(groups[1])
    }

    func staleIfErrorHeader() -> UInt64? {
        guard let headerValue = self.value(forHTTPHeaderField: "Cache-Control") else {
            return nil
        }
        // Swift finally got a decent Regex class, but it's only for iOS 16, so we use the old one.
        guard let groups = NSRegularExpression("\\bstale-if-error=([0-9]+)\\b").firstMatchGroups(headerValue) else {
            return nil
        }
        return UInt64(groups[1])
    }
}

extension NSRegularExpression {
    // https://www.hackingwithswift.com/articles/108/how-to-use-regular-expressions-in-swift
    convenience init(_ pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            fatalError("error in regular expression: \(String(describing: pattern))")
        }
    }

    // https://stackoverflow.com/a/53652037
    func firstMatchGroups(_ string: String) -> [String]? {
        let range = NSRange(location: 0, length: string.utf16.count)
        guard let match = firstMatch(in: string, options: [], range: range) else {
            return nil
        }
        return (0..<match.numberOfRanges).map({ groupIndex in
            let nsRange = match.range(at: groupIndex)
            let range = Range(nsRange, in: string)!
            return String(string[range])
        })
    }
}

// This is impossible in Swift because `extension` does not support type parameters `<K, V>`.
//extension Sequence where Iterator.Element == (K, V) {
//    func toDict() -> Dictionary<K, V> {
//        Dictionary<K, V>(uniqueKeysWithValues: array)
//    }
//}

// Lets us throw strings as exceptions.
extension String: Error {
}

extension String {
    func removePrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        } else {
            return self
        }
    }

    func removeSuffix(_ suffix: String) -> String {
        if self.hasSuffix(suffix) {
            return String(self.dropLast(suffix.count))
        } else {
            return self
        }
    }
}

//extension Task where Success == Sendable, Failure == Error {
//    // Compiler refuses to allow calls to this method:
//    // "Instance member 'sleep' cannot be used on type 'Task<any Sendable, any Error>'; did you mean to use a value of this type instead?"
//    func sleep(milliseconds: UInt64) async throws {
//        let nanoseconds = milliseconds.saturatingMultiply(1_000_000)
//        try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
//    }
//}

extension UInt64 {
    func saturatingMultiply(_ other: UInt64) -> UInt64 {
        let (result, overflow) = self.multipliedReportingOverflow(by: other)
        return overflow ? UInt64.max : result
    }
}

// class Weak<T: AnyObject> {
//    weak var value: T?
//
//    init(_ value: T) {
//        self.value = value
//    }
// }

struct Stopwatch {
    let start: Date

    init() {
        self.start = Date.now
    }

    func waitUntil(seconds: Double) async {
        if !seconds.isFinite {
            return
        }
        let elapsed = self.start.distance(to: Date.now)
        let secondsToWait = seconds - elapsed
        if secondsToWait > 0.000001 {
            let nanoSecondsToWait = secondsToWait * 1_000_000_000
            do {
                try await Task.sleep(nanoseconds: UInt64(nanoSecondsToWait))
            } catch {
            }
        }
    }
}

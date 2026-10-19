// 勤怠記録（Mac 用）：ログイン・ロック解除・ロックの時刻を OneDrive の共有フォルダに書き込みます。
// 使い方: kintai-logger <名前> <共有フォルダのパス> [定期記録の間隔(分)]
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("使い方: kintai-logger <名前> <フォルダ> [間隔(分)]\n".data(using: .utf8)!)
    exit(1)
}
let name = args[1].replacingOccurrences(of: ",", with: " ")
let folder = URL(fileURLWithPath: args[2])
let interval = Double(args.count >= 4 ? args[3] : "15") ?? 15
let target = folder.appendingPathComponent("\(name).csv")
let pending = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Kintai/pending.csv")
let pc = Host.current().localizedName ?? "Mac"
var locked = false

let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"

func append(_ text: String, to url: URL) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
        // Excel で文字化けしないよう BOM 付き UTF-8 にする
        let header = Data([0xEF, 0xBB, 0xBF]) + "日時,名前,PC,種類\r\n".data(using: .utf8)!
        try header.write(to: url)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: text.data(using: .utf8)!)
}

func log(_ type: String) {
    let line = "\(formatter.string(from: Date())),\(name),\(pc),\(type)\r\n"
    do {
        guard FileManager.default.fileExists(atPath: folder.path) else { throw CocoaError(.fileNoSuchFile) }
        if let saved = try? String(contentsOf: pending, encoding: .utf8), !saved.isEmpty {
            try append(saved.replacingOccurrences(of: "\u{FEFF}", with: ""), to: target)
            try? FileManager.default.removeItem(at: pending)
        }
        try append(line, to: target)
    } catch {
        // 書けないときは手元に一時保存し、次回まとめて書く
        try? FileManager.default.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: pending.path) {
            FileManager.default.createFile(atPath: pending.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: pending) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line.data(using: .utf8)!)
            try? h.close()
        }
    }
}

let center = DistributedNotificationCenter.default()
center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    locked = false
    log("unlock")
}
center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    locked = true
    log("lock")
}
Timer.scheduledTimer(withTimeInterval: interval * 60, repeats: true) { _ in
    if !locked { log("active") }
}

log("logon")
RunLoop.main.run()

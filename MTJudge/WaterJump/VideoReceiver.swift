import Foundation
import Network

@available(iOS 13.0, *)
final class VideoReceiver {
    private let wire: TransferChannel
    private var file: FileHandle?
    private var temp: URL?
    private var info: [String: Any] = [:]
    private var total: Int64 = 0
    private var count: Int64 = 0
    private var finished = false
    private var relatedFiles: [(name: String, size: Int64, hash: String)] = []
    private var relatedIndex = 0
    private var relatedFile: FileHandle?
    private var relatedTempURLs: [URL] = []
    var progress: ((Double) -> Void)?
    var complete: ((URL?, Error?) -> Void)?
    init(_ connection: NWConnection, queue: DispatchQueue) { wire = TransferChannel(connection, queue:queue) }
    func start() {
        wire.failed = { [weak self] error in self?.finish(nil, error) }
        wire.start { [weak self] in self?.wire.receiveJSON { info in self?.begin(info) } }
    }
    func cancel() { finish(nil, ReceivedVideoManager.failure("受信を停止しました。送信元の動画は保持されています。")) }
    private func begin(_ info: [String: Any]) {
        do {
            guard let id = info["id"] as? String, UUID(uuidString:id) != nil,
                  info["version"] as? Int == 1,
                  let size = info["size"] as? NSNumber, size.int64Value > 0, size.int64Value <= 8 * 1024 * 1024 * 1024,
                  let hash = info["sha256"] as? String, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }),
                  let tags = info["tags"] as? [[String:String]], tags.count <= 100 else { throw ReceivedVideoManager.failure("受信する動画情報が不正です。") }
            if let entries = info["relatedFiles"] as? [[String: Any]] {
                for entry in entries {
                    guard let name = entry["name"] as? String, name.hasPrefix("."), name.count <= 80,
                          !name.contains("/"), !name.contains("\\"), let size = (entry["size"] as? NSNumber)?.int64Value,
                          size >= 0, size <= 10 * 1024 * 1024, let hash = entry["sha256"] as? String, hash.count == 64 else { throw ReceivedVideoManager.failure("関連JSONの情報が不正です。") }
                    relatedFiles.append((name:name, size:size, hash:hash))
                }
            }
            let directory = ReceivedVideoManager.directory
            try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:true)
            // Space for staging + atomic import. Never overwrite an existing recording.
            let free = try FileManager.default.attributesOfFileSystem(forPath:directory.path)[.systemFreeSize] as? NSNumber
            guard let free = free, free.int64Value > size.int64Value * 2 + 50 * 1024 * 1024 else { throw ReceivedVideoManager.failure("iPadの空き容量が不足しています。") }
            self.info = info; self.info["received"] = true; self.info["transferRequested"] = false; total = size.int64Value
            let incoming = directory.appendingPathComponent(".Incoming", isDirectory:true)
            try FileManager.default.createDirectory(at:incoming,withIntermediateDirectories:true)
            let staging = incoming.appendingPathComponent(UUID().uuidString + ".mov")
            guard FileManager.default.createFile(atPath:staging.path, contents:nil) else { throw ReceivedVideoManager.failure("受信ファイルを作成できません。") }
            temp = staging; file = try FileHandle(forWritingTo:staging)
            wire.sendJSON(["state":"READY"]) { self.next() }
        } catch { reject(error) }
    }
    private func next() {
        guard !finished else { return }
        if count == total {
            if relatedIndex < relatedFiles.count { receiveRelated(); return }
            do {
                try file?.synchronize(); try file?.close(); file = nil
                guard let temp = temp else { throw ReceivedVideoManager.failure("受信ファイルがありません。") }
                let url = try ReceivedVideoManager.commit(temp, metadata:info)
                for (index, entry) in relatedFiles.enumerated() {
                    guard index < relatedTempURLs.count else { continue }
                    let dataURL = relatedTempURLs[index]
                    let expected = try ReceivedVideoManager.digest(dataURL)
                    guard expected == entry.hash else { throw ReceivedVideoManager.failure("関連JSONのハッシュが一致しません。") }
                    let suffix = entry.name
                    let destination = URL(fileURLWithPath: url.path + suffix)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: dataURL, to: destination)
                }
                wire.sendJSON(["state":"TRANSFERRED", "id":info["id"]!]) { self.finish(url, nil) }
            } catch { reject(error) }
            return
        }
        wire.receive(Int(min(65536,total-count))) { [weak self] data in
            guard let self = self else { return }
            do {
                try self.file?.write(contentsOf:data)
                let old = Int(self.count * 100 / self.total)
                self.count += Int64(data.count)
                if Int(self.count * 100 / self.total) != old { self.progress?(Double(self.count)/Double(self.total)) }
                self.next()
            } catch { self.reject(error) }
        }
    }
    private func receiveRelated() {
        guard relatedIndex < relatedFiles.count else { next(); return }
        let entry = relatedFiles[relatedIndex]
        if relatedFile == nil {
            let incoming = ReceivedVideoManager.directory.appendingPathComponent(".Incoming", isDirectory:true)
            let url = incoming.appendingPathComponent(UUID().uuidString + ".json")
            guard FileManager.default.createFile(atPath:url.path, contents:nil) else { reject(ReceivedVideoManager.failure("関連JSONを保存できません。")); return }
            relatedTempURLs.append(url); relatedFile = try? FileHandle(forWritingTo:url)
        }
        let written = (try? relatedFile?.offsetInFile) ?? 0
        if written >= UInt64(entry.size) {
            try? relatedFile?.close(); relatedFile = nil; relatedIndex += 1; receiveRelated(); return
        }
        wire.receive(Int(min(65536, UInt64(entry.size) - written))) { [weak self] data in
            guard let self = self else { return }
            do { try self.relatedFile?.write(contentsOf:data); self.receiveRelated() } catch { self.reject(error) }
        }
    }
    private func reject(_ error: Error) {
        wire.sendJSON(["error":error.localizedDescription]) { self.finish(nil,error) }
    }
    private func finish(_ url: URL?, _ error: Error?) {
        guard !finished else { return }; finished = true
        wire.close(); try? file?.close(); file = nil; try? relatedFile?.close(); relatedFile = nil
        if let temp = temp { try? FileManager.default.removeItem(at:temp) }; temp = nil
        for url in relatedTempURLs { try? FileManager.default.removeItem(at:url) }; relatedTempURLs.removeAll(); relatedFiles.removeAll(); relatedIndex = 0
        let callback = complete; complete = nil; callback?(url,error)
    }
}

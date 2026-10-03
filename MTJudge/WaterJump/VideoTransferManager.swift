import Foundation
import Network

@available(iOS 13.0, *)
@objc public final class VideoTransferManager: NSObject {
    @objc public let discovery = PeerDiscoveryManager()
    @objc public var changed: (() -> Void)?
    @objc public var received: ((URL) -> Void)?
    @objc public private(set) var state = "IDLE"
    @objc public private(set) var message = ""
    @objc public private(set) var progress: Double = 0
    @objc public var enabled = false
    private let io = DispatchQueue(label:"MTJudge.transfer", qos:.utility)
    private var jobs: [[String: Any]] = [] // owned by main queue
    private var channel: TransferChannel?
    private var input: FileHandle?
    private var activeID: String?
    private var activeFilename: String?
    private var relatedInputs: [(url: URL, suffix: String, size: Int64)] = []
    private var relatedIndex = 0
    private var relatedHandle: FileHandle?
    private var receiver: VideoReceiver?
    private var receiving = false
    private var retryTimer: Timer?
    static var testQueueURL: URL?
    private var queueURL: URL { if let testQueueURL = Self.testQueueURL { return testQueueURL }; return FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0].appendingPathComponent("WaterJumpTransferQueue.json") }
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at:queueURL.deletingLastPathComponent(), withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:jobs).write(to:queueURL, options:.atomic)
            return true
        } catch { state = "TRANSFER_FAILED"; message = "転送待ち情報を保存できません。空き容量を確認してください。動画本体は保持しています。"; changed?(); return false }
    }
    private func recover() {
        // Reconstruct from the committed sidecars as well, closing the crash window
        // between local save and queue insertion. Filenames are never remote paths.
        let entries = (try? FileManager.default.contentsOfDirectory(at:ReceivedVideoManager.directory, includingPropertiesForKeys:nil)) ?? []
        for entry in entries where entry.lastPathComponent.lowercased().hasSuffix(".mov.wj.json") {
            guard let data = try? Data(contentsOf:entry), let info = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                  info["transferRequested"] as? Bool == true, info["received"] as? Bool != true, info["transferComplete"] as? Bool != true,
                  let id = info["id"] as? String, UUID(uuidString:id) != nil else { continue }
            let filename = (info["filename"] as? String) ?? (id + ".mov")
            guard FileManager.default.fileExists(atPath:ReceivedVideoManager.directory.appendingPathComponent(filename).path) else { continue }
            jobs.append(["id":id,"file":filename,"metadata":info,"peer":info["peer"] as? String ?? ""])
        }
        jobs.sort { (($0["metadata"] as? [String:Any])?["created"] as? Double ?? 0) < (($1["metadata"] as? [String:Any])?["created"] as? Double ?? 0) }
        // The journal is secondary to each file's durable transfer intent.
        _ = persist()
    }
    @objc public func protects(_ url: URL) -> Bool { jobs.contains { $0["file"] as? String == url.lastPathComponent } }
    @objc public func suspend() {
        enabled = false
        configure(receiving:false,browsing:false)
        io.async { self.channel?.fail(ReceivedVideoManager.failure("アプリが前景に戻ったら再送します。")) }
    }
    @objc public var pendingCount: Int { jobs.count }
    public override init() {
        super.init()
        recover()
        retryTimer = Timer.scheduledTimer(withTimeInterval:30, repeats:true) { [weak self] _ in self?.pump() }
        discovery.changed = { [weak self] in self?.changed?(); self?.pump() }
        discovery.accepted = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            self.io.async {
                guard self.receiver == nil, self.receiving else { connection.cancel(); return }
                let receiver = VideoReceiver(connection, queue:self.io); self.receiver = receiver
                self.publish("RECEIVING", "受信中...", 0)
                receiver.progress = { [weak self] value in self?.publish("RECEIVING", "受信中... \(Int(value * 100))%", value) }
                receiver.complete = { [weak self] url, error in
                    guard let self = self else { return }; self.receiver = nil
                    DispatchQueue.main.async {
                        self.state = url == nil ? "ERROR" : "COMPLETE"
                        self.message = error?.localizedDescription ?? "受信完了"
                        self.changed?(); if let url = url { self.received?(url) }
                    }
                }
                receiver.start()
            }
        }
    }
    deinit { retryTimer?.invalidate() }
    @objc public func configure(receiving: Bool, browsing: Bool) {
        io.async { self.receiving = receiving; if !receiving { self.receiver?.cancel(); self.receiver = nil } }
        discovery.configure(receiving:receiving, browsing:browsing)
    }
    @objc public func enqueue(_ url: URL, metadata: [String: Any]) {
        guard let id = metadata["id"] as? String, !jobs.contains(where: { $0["id"] as? String == id }) else { return }
        jobs.append(["id":id, "file":url.lastPathComponent, "metadata":metadata, "peer":metadata["peer"] as? String ?? discovery.selectedID])
        guard persist() else { return }; state = "WAITING_TRANSFER"; message = "転送待ち \(jobs.count)本"; changed?(); pump()
    }
    @objc public func retry() { pump() }
    /// 保存済み動画のサイドカーを使って、完了済みの動画も再転送キューへ戻す。
    @objc public func requeue(_ url: URL) {
        guard let data = try? Data(contentsOf: url.appendingPathExtension("wj.json")),
              var info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = info["id"] as? String, UUID(uuidString: id) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return }
        info["transferRequested"] = true
        info["transferComplete"] = false
        jobs.removeAll { ($0["id"] as? String) == id }
        jobs.append(["id": id, "file": url.lastPathComponent, "metadata": info, "peer": info["peer"] as? String ?? discovery.selectedID])
        _ = persist()
        state = "WAITING_TRANSFER"; message = "再転送待ち"; changed?(); pump()
    }
    private func relatedMetadata(for url: URL) -> [[String: Any]] {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + "."
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return entries.compactMap { entry in
            guard entry.lastPathComponent.hasPrefix(prefix), entry.pathExtension.lowercased() == "json",
                  let size = try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0,
                  let hash = try? ReceivedVideoManager.digest(entry) else { return nil }
            return ["name": String(entry.lastPathComponent.dropFirst(url.lastPathComponent.count)), "size": size, "sha256": hash]
        }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }
    private func publish(_ state: String, _ message: String, _ progress: Double) {
        DispatchQueue.main.async { self.state = state; self.message = message; self.progress = progress; self.changed?() }
    }
    private func pump() {
        guard enabled, activeID == nil, let job = jobs.first, let id = job["id"] as? String,
              let filename = job["file"] as? String, let info = job["metadata"] as? [String: Any] else { return }
        let peer = (job["peer"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? discovery.selectedID
        guard let connection = discovery.connection(to: peer) else {
            state = "TRANSFER_FAILED"; message = "転送先が未接続です。同じWi-Fiで受信待機をONにし、再送してください。"; changed?(); return
        }
        guard persist() else { return }
        var url = ReceivedVideoManager.directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path), let legacyID = job["id"] as? String {
            let legacyURL = ReceivedVideoManager.directory.appendingPathComponent(legacyID).appendingPathExtension("mov")
            if FileManager.default.fileExists(atPath: legacyURL.path) { url = legacyURL }
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            state = "TRANSFER_FAILED"; message = "転送元動画が見つかりません。保存動画一覧から再送してください。"; changed?(); return
        }
        activeFilename = url.lastPathComponent
        // Bind an initially unregistered job once; later destination changes never reroute it.
        if (jobs[0]["peer"] as? String ?? "").isEmpty {
            jobs[0]["peer"] = peer
            var boundInfo = info; boundInfo["peer"] = peer
            do {
                let sidecar = url.appendingPathExtension("wj.json")
                try JSONSerialization.data(withJSONObject:boundInfo).write(to:sidecar, options:.atomic)
                jobs[0]["metadata"] = boundInfo
                guard persist() else { return }
            } catch { state = "TRANSFER_FAILED"; message = "転送先を保存できません"; changed?(); return }
        }
        let related = relatedMetadata(for: url)
        relatedInputs = related.compactMap { entry in
            guard let suffix = entry["name"] as? String, let size = (entry["size"] as? NSNumber)?.int64Value else { return nil }
            return (url: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + suffix), suffix: suffix, size: size)
        }
        relatedIndex = 0; try? relatedHandle?.close(); relatedHandle = nil
        var transferInfo = info; transferInfo["relatedFiles"] = related
        activeID = id; state = "TRANSFERRING"; message = "iPadへ転送中..."; progress = 0; changed?()
        io.async {
            let wire = TransferChannel(connection, queue:self.io); self.channel = wire
            wire.failed = { [weak self] error in self?.finish(id, error: error) }
            wire.start { [weak self, weak wire] in
                guard let self = self, let wire = wire else { return }
                do {
                    self.input = try FileHandle(forReadingFrom:url)
                    wire.sendJSON(transferInfo) {
                        wire.receiveJSON { response in
                            if response["state"] as? String == "READY" { self.sendChunk(id, info: transferInfo, total:(transferInfo["size"] as? NSNumber)?.int64Value ?? 0, sent:0) }
                            else { wire.fail(ReceivedVideoManager.failure(response["error"] as? String ?? "受信端末が動画を受け付けませんでした")) }
                        }
                    }
                } catch { wire.fail(error) }
            }
        }
    }
    private func sendChunk(_ id: String, info: [String: Any], total: Int64, sent: Int64) {
        guard let wire = channel, let file = input else { return }
        if sent == total {
            sendRelated(id, info: info) {
                wire.receiveJSON { response in
                if response["state"] as? String == "TRANSFERRED", response["id"] as? String == id {
                    do {
                        let filename = self.activeFilename ?? (id + ".mov")
                        let sidecar = ReceivedVideoManager.directory.appendingPathComponent(filename).appendingPathExtension("wj.json")
                        var metadata = try JSONSerialization.jsonObject(with:Data(contentsOf:sidecar)) as! [String:Any]
                        metadata["transferComplete"] = true
                        try JSONSerialization.data(withJSONObject:metadata).write(to:sidecar, options:.atomic)
                        self.finish(id, error:nil)
                    } catch { wire.fail(error) }
                }
                else { wire.fail(ReceivedVideoManager.failure(response["error"] as? String ?? "受信完了を確認できません。再送してください。")) }
                }
            }
            return
        }
        do {
            guard let data = try file.read(upToCount: Int(min(65536, total-sent))), !data.isEmpty else { throw ReceivedVideoManager.failure("転送元動画を読み込めません。") }
            wire.send(data) {
                let count = sent + Int64(data.count)
                let percent = Int(count * 100 / max(total,1)), old = Int(sent * 100 / max(total,1))
                if percent != old { self.publish("TRANSFERRING", "iPadへ転送中... \(percent)%", Double(count)/Double(total)) }
                self.sendChunk(id, info: info, total:total, sent:count)
            }
        } catch { wire.fail(error) }
    }
    private func sendRelated(_ id: String, info: [String: Any], completion: @escaping () -> Void) {
        guard let wire = channel else { return }
        guard relatedIndex < relatedInputs.count else { completion(); return }
        let input = relatedInputs[relatedIndex]
        if relatedHandle == nil { relatedHandle = try? FileHandle(forReadingFrom: input.url) }
        guard let handle = relatedHandle else { wire.fail(ReceivedVideoManager.failure("関連JSONを読み込めません。")); return }
        do {
            let sent = (try handle.offsetInFile)
            if sent >= UInt64(input.size) {
                try? handle.close(); relatedHandle = nil; relatedIndex += 1; sendRelated(id, info: info, completion: completion); return
            }
            guard let data = try handle.read(upToCount: Int(min(65536, UInt64(input.size) - sent))), !data.isEmpty else { throw ReceivedVideoManager.failure("関連JSONを読み込めません。") }
            wire.send(data) { self.sendRelated(id, info: info, completion: completion) }
        } catch { wire.fail(error) }
    }
    private func finish(_ id: String, error: Error?) {
        channel?.close(); channel = nil; try? input?.close(); input = nil; try? relatedHandle?.close(); relatedHandle = nil; relatedInputs.removeAll(); relatedIndex = 0; activeFilename = nil
        DispatchQueue.main.async {
            guard self.activeID == id else { return }; self.activeID = nil
            if let error = error { self.state = "TRANSFER_FAILED"; self.message = "転送失敗: \(error.localizedDescription) 元動画は保存済みです。" }
            else { self.jobs.removeAll { $0["id"] as? String == id }; self.state = "TRANSFERRED"; self.message = "転送完了"; self.progress = 1 }
            _ = self.persist(); self.changed?(); if error == nil { self.pump() }
        }
    }
}

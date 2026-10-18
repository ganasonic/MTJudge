import Foundation
import Network
import UIKit

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
    private var activePeer: String?
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
        if let data = try? Data(contentsOf:queueURL), let stored = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] { jobs = stored }
        jobs.removeAll { job in
            if job["cancelled"] as? Bool == true { return false }
            guard let filename = job["file"] as? String,
                  let data = try? Data(contentsOf:ReceivedVideoManager.directory.appendingPathComponent(filename).appendingPathExtension("wj.json")),
                  let info = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return false }
            if let completed = info["completedPeers"] as? [String] { return completed.contains(job["peer"] as? String ?? "") }
            return info["transferComplete"] as? Bool == true
        }
        let entries = (try? FileManager.default.contentsOfDirectory(at:ReceivedVideoManager.directory, includingPropertiesForKeys:nil)) ?? []
        for entry in entries where entry.lastPathComponent.lowercased().hasSuffix(".mov.wj.json") {
            guard let data = try? Data(contentsOf:entry), let info = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                  info["transferRequested"] as? Bool == true, info["received"] as? Bool != true, info["transferComplete"] as? Bool != true,
                  let id = info["id"] as? String, UUID(uuidString:id) != nil else { continue }
            let filename = (info["filename"] as? String) ?? (id + ".mov")
            guard FileManager.default.fileExists(atPath:ReceivedVideoManager.directory.appendingPathComponent(filename).path) else { continue }
            if !jobs.contains(where:{$0["id"] as? String == id}) { jobs.append(["id":id,"file":filename,"metadata":info,"peer":info["peer"] as? String ?? ""]) }
        }
        jobs.sort { (($0["metadata"] as? [String:Any])?["created"] as? Double ?? 0) < (($1["metadata"] as? [String:Any])?["created"] as? Double ?? 0) }
        // The journal is secondary to each file's durable transfer intent.
        _ = persist()
    }
    @objc public func protects(_ url: URL) -> Bool { jobs.contains { $0["cancelled"] as? Bool != true && $0["sourceMissing"] as? Bool != true && $0["file"] as? String == url.lastPathComponent } }
    @objc public func suspend() {
        enabled = false
        configure(receiving:false,browsing:false)
        io.async { self.channel?.fail(ReceivedVideoManager.failure("アプリが前景に戻ったら再送します。")) }
    }
    @objc public var pendingCount: Int { jobs.filter { eligible($0) }.count }
    @objc public var communicationBusy: Bool { activeID != nil || state == "RECEIVING" }
    @objc public var needsRetry: Bool { state == "TRANSFER_FAILED" }
    private func jobKey(_ job: [String:Any]) -> String {
        (job["id"] as? String ?? "") + "|" + (job["peer"] as? String ?? "")
    }
    @objc public var transferQueueEntries: [[String:Any]] {
        let d = UserDefaults.standard
        return jobs.filter { $0["cancelled"] as? Bool != true }.map { job in
            let info = job["metadata"] as? [String:Any] ?? [:]
            let peer = job["peer"] as? String ?? ""
            let registration = discovery.registeredPeers.first { $0["id"] == peer }
            let sameConfiguration = (info["connectionMode"] as? String ?? "manual") == (d.string(forKey:"WJConnectionMode") ?? "manual") &&
                (info["connectionGeneration"] as? String ?? "") == (d.string(forKey:"WJConnectionGeneration") ?? "") &&
                (d.string(forKey:"WJConnectionMode") != "automatic" || info["groupID"] as? String == d.string(forKey:"WJCameraGroupID"))
            let url = sourceURL(for:job)
            let active = job["id"] as? String == activeID && peer == activePeer
            let category = !sameConfiguration ? 1 : (!eligible(job) && job["sourceMissing"] as? Bool != true ? 0 : (url == nil || job["sourceMissing"] as? Bool == true ? 3 : 2))
            return ["key":jobKey(job), "filename":job["file"] as? String ?? "", "peerID":peer,
                    "peerName":registration?["name"] ?? (peer.isEmpty ? "未指定" : "登録解除済み／以前の端末"),
                    "created":info["created"] as? Double ?? 0, "category":category,
                    "active":active, "path":url?.path ?? "", "missing":url == nil]
        }
    }
    @objc public func removeTransferEntries(_ keys: [String]) -> String? {
        let selected = Set(keys)
        guard !jobs.contains(where: { selected.contains(jobKey($0)) && $0["id"] as? String == activeID && ($0["peer"] as? String ?? "") == activePeer }) else {
            return "転送中の項目は削除できません。転送が終了してから選択してください。"
        }
        let previous = jobs
        // Durable cancellation records prevent recovery from sidecars after relaunch.
        // Never delete or change the video or its tags and other related files.
        for index in jobs.indices where selected.contains(jobKey(jobs[index])) {
            jobs[index]["cancelled"] = true
            jobs[index]["cancelledAt"] = Date().timeIntervalSince1970
        }
        if !persist() { jobs = previous; return message }
        changed?(); pump(); return nil
    }
    private func scoped(_ metadata: [String:Any]) -> [String:Any] {
        var result = metadata
        let d = UserDefaults.standard
        result["connectionMode"] = d.string(forKey:"WJConnectionMode") ?? "manual"
        result["connectionGeneration"] = d.string(forKey:"WJConnectionGeneration") ?? ""
        result["groupID"] = d.string(forKey:"WJCameraGroupID") ?? ""
        result["senderID"] = discovery.deviceID
        return result
    }
    private func eligible(_ job: [String:Any]) -> Bool {
        guard job["cancelled"] as? Bool != true, job["sourceMissing"] as? Bool != true else { return false }
        let info = job["metadata"] as? [String:Any] ?? [:], d = UserDefaults.standard
        let mode = d.string(forKey:"WJConnectionMode") ?? "manual"
        guard (info["connectionMode"] as? String ?? "manual") == mode,
              (info["connectionGeneration"] as? String ?? "") == (d.string(forKey:"WJConnectionGeneration") ?? "") else { return false }
        if mode == "automatic" {
            let peer = job["peer"] as? String ?? ""
            let target = peer.isEmpty ? discovery.selectedID : peer
            guard !target.isEmpty, discovery.registeredPeers.contains(where: { $0["id"] == target }) else { return false }
            let role = d.string(forKey:"WJGroupRole") ?? ""
            let members = d.array(forKey:"WJGroupMembers") as? [[String:String]] ?? []
            guard members.contains(where: { $0["id"] == target && (role == "MAIN" ? $0["role"] == "RECEIVER" : role.hasPrefix("CAMERA_") && $0["role"] == "MAIN") }) else { return false }
            return info["groupID"] as? String == d.string(forKey:"WJCameraGroupID")
        }
        return true
    }
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
        let metadata = scoped(metadata)
        guard let id = metadata["id"] as? String else { return }
        let registered = discovery.registeredPeers.compactMap { $0["id"] }.filter { !$0.isEmpty }
        if UserDefaults.standard.string(forKey:"WJConnectionMode") == "automatic", UserDefaults.standard.string(forKey:"WJGroupRole") == "MAIN", registered.isEmpty { return }
        let targets = registered.isEmpty ? [discovery.selectedID] : registered
        var saved = metadata; saved["transferRequested"] = true; saved["transferComplete"] = false; saved["completedPeers"] = [String]()
        if let data = try? JSONSerialization.data(withJSONObject:saved) { try? data.write(to:url.appendingPathExtension("wj.json"),options:.atomic) }
        for peer in targets where !jobs.contains(where: { ($0["id"] as? String) == id && ($0["peer"] as? String ?? "") == peer }) {
            jobs.append(["id":id, "file":url.lastPathComponent, "metadata":metadata, "peer":peer])
        }
        guard !targets.isEmpty else { return }
        guard persist() else { return }; state = "WAITING_TRANSFER"; message = "転送待ち \(jobs.filter { eligible($0) }.count)件"; changed?(); pump()
    }
    @objc public func retry() { pump() }
    /// 保存済み動画のサイドカーを使って、完了済みの動画も再転送キューへ戻す。
    @objc public func requeue(_ url: URL) {
        guard let data = try? Data(contentsOf: url.appendingPathExtension("wj.json")),
              var info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = info["id"] as? String, UUID(uuidString: id) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return }
        info = scoped(info)
        info["transferRequested"] = true
        info["transferComplete"] = false; info["completedPeers"] = [String]()
        if let data = try? JSONSerialization.data(withJSONObject:info) { try? data.write(to:url.appendingPathExtension("wj.json"),options:.atomic) }
        jobs.removeAll { ($0["id"] as? String) == id }
        let registered = discovery.registeredPeers.compactMap { $0["id"] }.filter { !$0.isEmpty }
        let targets = registered.isEmpty ? [discovery.selectedID] : registered
        for peer in targets { jobs.append(["id": id, "file": url.lastPathComponent, "metadata": info, "peer": peer]) }
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
    // Keep missing jobs recoverable, but never let one missing file block later recordings.
    private func sourceURL(for job: [String:Any]) -> URL? {
        let names = [job["file"] as? String, (job["metadata"] as? [String:Any])?["filename"] as? String,
                     (job["id"] as? String).map { $0 + ".mov" }].compactMap { $0 }
        for name in names where URL(fileURLWithPath:name).lastPathComponent == name {
            let url = ReceivedVideoManager.directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:url.path) { return url }
        }
        return nil
    }
    @objc public var missingSourceFilenames: [String] {
        Array(Set(jobs.filter { eligible($0) && sourceURL(for:$0) == nil }.compactMap { $0["file"] as? String })).sorted()
    }
    private func pump() {
        guard enabled, activeID == nil, UIApplication.shared.isProtectedDataAvailable else { return }
        // Missing sources are retained as history, not actionable transfer failures.
        // Explicit requeue from the library creates a fresh job if the video is recovered.
        let previousJobs = jobs
        var archivedMissing = false
        for index in jobs.indices where eligible(jobs[index]) && sourceURL(for:jobs[index]) == nil {
            jobs[index]["sourceMissing"] = true
            jobs[index]["sourceMissingAt"] = Date().timeIntervalSince1970
            archivedMissing = true
        }
        if archivedMissing && !persist() { jobs = previousJobs; return }
        let current = jobs.filter { eligible($0) }
        guard !current.isEmpty else {
            if ["WAITING_TRANSFER", "TRANSFER_FAILED", "TRANSFERRED"].contains(state) {
                state = "IDLE"; message = ""; progress = 0; changed?()
            }
            return
        }
        var selected: (job:[String:Any], url:URL, peer:String, connection:NWConnection)?
        var unavailable: [String] = []
        for job in current {
            guard let url = sourceURL(for:job) else { continue }
            let peer = (job["peer"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? discovery.selectedID
            guard let connection = discovery.connection(to:peer) else { unavailable.append(peer); continue }
            selected = (job,url,peer,connection); break
        }
        guard let selected = selected else {
            state = "TRANSFER_FAILED"
            if !unavailable.isEmpty {
                let names = Set(unavailable.map { id in discovery.registeredPeers.first { $0["id"] == id }?["name"] ?? id }).sorted()
                message = "転送先「\(names.joined(separator:"、"))」の接続待ちです。同じWi-Fiで受信端末のMTJudgeを前景で開いてください。接続後に自動再送します。"
            } else {
                state = "IDLE"; message = ""; progress = 0
            }
            changed?(); return
        }
        let job = selected.job, url = selected.url, peer = selected.peer, connection = selected.connection
        guard let id = job["id"] as? String, var info = job["metadata"] as? [String:Any] else { return }
        info["filename"] = url.lastPathComponent
        guard persist() else { return }
        activeFilename = url.lastPathComponent
        activePeer = peer
        // Bind an initially unregistered job once; later destination changes never reroute it.
        if let index = jobs.firstIndex(where:{$0["id"] as? String == id && ($0["peer"] as? String ?? "").isEmpty}) {
            jobs[index]["peer"] = peer
            var boundInfo = info; boundInfo["peer"] = peer
            do {
                let sidecar = url.appendingPathExtension("wj.json")
                try JSONSerialization.data(withJSONObject:boundInfo).write(to:sidecar, options:.atomic)
                jobs[index]["metadata"] = boundInfo
                guard persist() else { return }
            } catch { state = "TRANSFER_FAILED"; message = "転送先を保存できません"; changed?(); return }
        }
        let related = relatedMetadata(for: url)
        relatedInputs = related.compactMap { entry in
            guard let suffix = entry["name"] as? String, let size = (entry["size"] as? NSNumber)?.int64Value else { return nil }
            return (url: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + suffix), suffix: suffix, size: size)
        }
        relatedIndex = 0; try? relatedHandle?.close(); relatedHandle = nil
        var transferInfo = info; transferInfo["relatedFiles"] = related; transferInfo["senderID"] = discovery.deviceID
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
                    self.finish(id, error:nil)
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
        let finishedFilename = activeFilename ?? (id + ".mov")
        channel?.close(); channel = nil; try? input?.close(); input = nil; try? relatedHandle?.close(); relatedHandle = nil; relatedInputs.removeAll(); relatedIndex = 0; activeFilename = nil
        DispatchQueue.main.async {
            guard self.activeID == id else { return }
            if let error = error { self.state = "TRANSFER_FAILED"; self.message = "転送失敗（\(finishedFilename)）: \(error.localizedDescription)" }
            else {
                let destination = self.activePeer ?? ""
                do {
                    let sidecar = ReceivedVideoManager.directory.appendingPathComponent(finishedFilename).appendingPathExtension("wj.json")
                    var metadata = try JSONSerialization.jsonObject(with:Data(contentsOf:sidecar)) as! [String:Any]
                    var completed = metadata["completedPeers"] as? [String] ?? []
                    if !completed.contains(destination) { completed.append(destination) }
                    metadata["completedPeers"] = completed
                    metadata["transferComplete"] = !self.jobs.contains { $0["id"] as? String == id && ($0["peer"] as? String ?? "") != destination }
                    try JSONSerialization.data(withJSONObject:metadata).write(to:sidecar,options:.atomic)
                } catch {
                    self.activeID = nil; self.activePeer = nil; self.state = "TRANSFER_FAILED"; self.message = "転送完了情報を保存できません。動画は保持しています。"; self.changed?(); return
                }
                self.jobs.removeAll { ($0["id"] as? String) == id && ($0["peer"] as? String ?? "") == destination }
                let remaining = self.jobs.filter { self.eligible($0) }.count
                self.state = remaining == 0 ? "TRANSFERRED" : "WAITING_TRANSFER"
                self.message = remaining == 0 ? "転送完了" : "転送待ち \(remaining)件"
                self.progress = 1
            }
            self.activeID = nil; self.activePeer = nil
            _ = self.persist(); self.changed?(); if error == nil { self.pump() }
        }
    }
}

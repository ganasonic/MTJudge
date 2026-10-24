import Foundation
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation
import CryptoKit

@available(iOS 13.0, *)
@objc public final class ReceivedVideoManager: NSObject {
    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
    static let io = DispatchQueue(label: "MTJudge.videoStore", qos: .utility)
    static var testDirectory: URL?
    static var directory: URL {
        if let testDirectory = testDirectory { return testDirectory }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "MTJudge.WaterJump", code: 1, userInfo: [NSLocalizedDescriptionKey:message]) }
    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    // Read capture time, never the receive/save time, when aligning two cameras.
    @objc public static func recordingStartTime(_ url: URL) -> TimeInterval {
        let info = ((try? Data(contentsOf: url.appendingPathExtension("wj.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        let value = (info["recordingStart"] as? NSNumber)?.doubleValue ?? Double(info["recordingStart"] as? String ?? "") ?? 0
        if value.isFinite && value > 0 { return value > 100_000_000_000 ? value / 1000 : value }
        let embedded = AVURLAsset(url: url).creationDate?.dateValue?.timeIntervalSince1970 ?? 0
        if embedded.isFinite && embedded > 0 { return embedded }
        if !(info["imported"] as? Bool ?? false) {
            let name = info["filename"] as? String ?? url.lastPathComponent
            if let range = name.range(of: "^MTJ[0-9]{17}", options: .regularExpression) {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = "yyyyMMddHHmmssSSS"
                if let date = formatter.date(from: String(name[range].dropFirst(3))) { return date.timeIntervalSince1970 }
            }
        }
        return 0
    }
    static func metadata(_ url: URL, id: String, tags: [[String: String]]) throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard !asset.tracks(withMediaType: .video).isEmpty, duration.isFinite, duration > 0 else { throw failure("動画ファイルを読み込めません。元動画は保持しています。") }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8 * 1024 * 1024 * 1024 else { throw failure("動画のサイズが転送可能範囲を超えています（上限8GB）。") }
        let track = asset.tracks(withMediaType: .video).first!
        var codec = "unknown"
        if let format = track.formatDescriptions.first {
            let fourcc = CMFormatDescriptionGetMediaSubType(format as! CMFormatDescription)
            codec = String(bytes: [UInt8((fourcc >> 24) & 255), UInt8((fourcc >> 16) & 255), UInt8((fourcc >> 8) & 255), UInt8(fourcc & 255)], encoding: .ascii) ?? "unknown"
        }
        let start = recordingStartTime(url)
        return ["version":1, "id":id, "remoteOnly":false, "sourceCameraID":UserDefaults.standard.string(forKey:"WJDeviceID") ?? "", "sessionID":UserDefaults.standard.string(forKey:"WJSessionID") ?? id, "cameraRole":UserDefaults.standard.string(forKey:"WJCameraRole") ?? "MAIN_CAMERA", "cameraName":UserDefaults.standard.string(forKey:"WJCameraName") ?? deviceName, "groupID":UserDefaults.standard.string(forKey:"WJCameraGroupID") ?? "", "recordingStart": start, "size":size, "sha256":try digest(url), "tags":tags, "duration":duration,
                "width":abs(track.naturalSize.width), "height":abs(track.naturalSize.height), "fps":track.nominalFrameRate,
                "bitrate":track.estimatedDataRate, "codec":codec, "created":Date().timeIntervalSince1970]
    }
    static func commit(_ source: URL, metadata: [String: Any]) throws -> URL {
        guard let id = metadata["id"] as? String, UUID(uuidString: id) != nil,
              let expected = metadata["sha256"] as? String, expected.count == 64,
              let size = metadata["size"] as? NSNumber, size.int64Value > 0 else { throw failure("受信情報が不正です。") }
        let files = FileManager.default
        let localGroup = UserDefaults.standard.string(forKey: "WJCameraGroupID") ?? ""
        let incomingGroup = metadata["groupID"] as? String ?? ""
        // グループ設定済み端末では、別グループの動画を保存領域へ登録しない。
        // 未設定の旧データは後方互換のため受け入れる。
        if !localGroup.isEmpty && !incomingGroup.isEmpty && localGroup != incomingGroup {
            throw failure("別のカメラグループの動画です。転送先グループを確認してください。")
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let requestedName = (metadata["filename"] as? String).flatMap { name -> String? in
            let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
            return cleaned.isEmpty ? nil : cleaned
        } ?? {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMddHHmmssSSS"
            return "MTJ" + formatter.string(from: Date()) + ".MOV"
        }()
        var final = directory.appendingPathComponent(requestedName)
        if files.fileExists(atPath: final.path) {
            if try digest(final) != expected {
                let ext = (requestedName as NSString).pathExtension
                let stem = (requestedName as NSString).deletingPathExtension
                var index = 1
                repeat {
                    let candidate = directory.appendingPathComponent("\(stem)_\(index).\(ext.isEmpty ? "MOV" : ext)")
                    if !files.fileExists(atPath: candidate.path) { final = candidate; break }
                    index += 1
                } while index < 10000
                if files.fileExists(atPath: final.path) { throw failure("同名動画が多すぎるため保存できません。") }
            }
        }
        let actual = try metadataForValidation(source)
        guard actual == size.int64Value, try digest(source) == expected else { throw failure("受信した動画のサイズまたはハッシュが一致しません。再送してください。") }
        if !files.fileExists(atPath:final.path) {
            let temp = directory.appendingPathComponent(UUID().uuidString + ".partial")
            do { try files.copyItem(at: source, to: temp); try files.moveItem(at: temp, to: final) }
            catch { try? files.removeItem(at: temp); throw error }
        }
        var persistedMetadata = metadata
        persistedMetadata["filename"] = final.lastPathComponent
        try JSONSerialization.data(withJSONObject: persistedMetadata).write(to: final.appendingPathExtension("wj.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: persistedMetadata["tags"] ?? []).write(to: final.appendingPathExtension("tags.json"), options: .atomic)
        return final
    }
    private static func metadataForValidation(_ url: URL) throws -> Int64 {
        let asset = AVURLAsset(url: url)
        guard !asset.tracks(withMediaType: .video).isEmpty, CMTimeGetSeconds(asset.duration).isFinite, CMTimeGetSeconds(asset.duration) > 0 else { throw failure("受信ファイルが再生可能な動画ではありません。") }
        return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
    // Photo picker URLs are temporary. Finish the durable import before closing
    // the picker or letting the player write annotations beside the movie.
    @objc public static func importPhotoVideo(_ source: URL, completion: @escaping (URL?, NSError?) -> Void) {
        io.async {
            do {
                let id = UUID().uuidString
                var info = try metadata(source, id: id, tags: [])
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyyMMddHHmmssSSS"
                let stem = "MTJ" + formatter.string(from: Date())
                var filename = stem + ".MOV"
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
                    filename = stem + "_" + id + ".MOV"
                }
                info["filename"] = filename
                info["imported"] = true
                info["transferRequested"] = false
                let saved = try commit(source, metadata: info)
                DispatchQueue.main.async { completion(saved, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error as NSError) }
            }
        }
    }
    @objc public static func saveAutomatic(_ source: URL, completion: @escaping (URL?, [String: Any]?, NSError?) -> Void) {
        io.async {
            do {
                // AVCaptureMovieFileOutputの完了通知直後は、端末によってAVAssetの
                // トラック情報が読み出せるまでわずかな遅延がある。特にリモート停止
                // されたサブカメラで発生しやすいため、保存処理を数回リトライする。
                var info: [String: Any]?
                var lastError: Error?
                for _ in 0..<8 {
                    do { info = try metadata(source, id: UUID().uuidString, tags: []); break }
                    catch { lastError = error; Thread.sleep(forTimeInterval: 0.25) }
                }
                guard var info = info else { throw lastError ?? failure("動画ファイルを読み込めません。元動画は保持しています。") }
                let captureStart = UserDefaults.standard.double(forKey:"WJRecordingStartTime")
                if captureStart.isFinite && captureStart > 0 { info["recordingStart"] = captureStart }
                info["remoteOnly"] = UserDefaults.standard.bool(forKey:"WJRecordingRemoteOnly")
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMddHHmmssSSS"
                let sourceName = source.deletingPathExtension().lastPathComponent
                info["filename"] = sourceName.hasPrefix("MTJ") ? sourceName + ".MOV" : "MTJ" + formatter.string(from: Date()) + ".MOV"
                let isSubCamera = (info["cameraRole"] as? String) == "SUB_CAMERA"
                info["transferRequested"] = UserDefaults.standard.bool(forKey:"WJTransfer") && (isSubCamera || !UserDefaults.standard.bool(forKey:"WJTagBeforeTransfer"))
                if UserDefaults.standard.string(forKey:"WJConnectionMode") == "automatic", UserDefaults.standard.string(forKey:"WJGroupRole") == "MAIN", (UserDefaults.standard.array(forKey:"WJPeerRegistrations") ?? []).isEmpty { info["transferRequested"] = false }
                info["peer"] = UserDefaults.standard.string(forKey:"WJPeerID") ?? ""
                info["connectionMode"] = UserDefaults.standard.string(forKey:"WJConnectionMode") ?? "manual"
                info["connectionGeneration"] = UserDefaults.standard.string(forKey:"WJConnectionGeneration") ?? ""
                info["groupID"] = UserDefaults.standard.string(forKey:"WJCameraGroupID") ?? ""
                info["cameraNumber"] = UserDefaults.standard.string(forKey:"WJGroupRole") ?? ""
                let saved = try commit(source, metadata: info)
                // The temporary original is intentionally retained if any operation fails.
                DispatchQueue.main.async { completion(saved, info, nil) }
            } catch { DispatchQueue.main.async { completion(nil, nil, error as NSError) } }
        }
    }
    // A container's absolute path can change after an app update. Prefer the
    // video's persistent ID, with a filename fallback for legacy exports.
    @objc public static func videoIdentity(_ url: URL) -> String {
        if let data = try? Data(contentsOf: url.appendingPathExtension("wj.json")),
           let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = info["id"] as? String, UUID(uuidString: id) != nil {
            return "id:" + id
        }
        return "file:" + url.lastPathComponent
    }
    @objc public static func isFavoriteVideo(_ url: URL) -> Bool {
        let defaults = UserDefaults.standard
        let identity = videoIdentity(url)
        var ids = defaults.stringArray(forKey: "WJFavoriteVideoIDs") ?? []
        if ids.contains(identity) { return true }
        let oldPaths = defaults.stringArray(forKey: "WJFavoriteVideoPaths") ?? []
        if oldPaths.contains(where: { URL(fileURLWithPath: $0).lastPathComponent == url.lastPathComponent }) {
            ids.append(identity)
            defaults.set(ids, forKey: "WJFavoriteVideoIDs")
            return true
        }
        return false
    }
    @objc public static func setFavoriteVideo(_ url: URL, favorite: Bool) {
        let defaults = UserDefaults.standard
        let identity = videoIdentity(url)
        var ids = defaults.stringArray(forKey: "WJFavoriteVideoIDs") ?? []
        ids.removeAll { $0 == identity }
        if favorite { ids.append(identity) }
        defaults.set(ids, forKey: "WJFavoriteVideoIDs")
        // Remove legacy entries even when switching off, so migration cannot
        // unexpectedly resurrect a favorite on the next read.
        let oldPaths = (defaults.stringArray(forKey: "WJFavoriteVideoPaths") ?? []).filter {
            URL(fileURLWithPath: $0).lastPathComponent != url.lastPathComponent
        }
        defaults.set(oldPaths, forKey: "WJFavoriteVideoPaths")
        NotificationCenter.default.post(name: Notification.Name("WJVideoFavoritesChanged"), object: url)
    }
    @objc public static func recordPlayback(_ url: URL) {
        let d = UserDefaults.standard, filename = url.lastPathComponent
        var recent = d.stringArray(forKey:"WJPlaybackHistory") ?? []
        recent.removeAll { $0 == filename }; recent.insert(filename, at:0)
        d.set(Array(recent.prefix(10)), forKey:"WJPlaybackHistory")
        d.set(filename, forKey:"WJLastPlayedFilename")
    }
    @objc public static func videos() -> [URL] {
        // 旧バージョンの自動録画先を、現在の受信動画と同じRecordingsへ移行する。
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CameraRecordings", isDirectory: true)
        if let oldFiles = try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for old in oldFiles where old.pathExtension.lowercased() == "mov" {
                let target = directory.appendingPathComponent(old.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.moveItem(at: old, to: target)
                    for suffix in ["wj.json", "tags.json", "pose.json"] {
                        let sidecar = old.appendingPathExtension(suffix)
                        let targetSidecar = target.appendingPathExtension(suffix)
                        if FileManager.default.fileExists(atPath: sidecar.path) { try? FileManager.default.moveItem(at: sidecar, to: targetSidecar) }
                    }
                }
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let videos = files.filter { $0.pathExtension.lowercased() == "mov" }
        for video in videos {
            let sidecar = video.appendingPathExtension("wj.json")
            if !FileManager.default.fileExists(atPath: sidecar.path), let info = try? metadata(video, id: UUID().uuidString, tags: []) {
                var repaired = info
                let created = (try? video.resourceValues(forKeys: [.creationDateKey]).creationDate)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                repaired["created"] = created
                repaired["cameraRole"] = "MAIN_CAMERA"
                repaired["sessionID"] = UserDefaults.standard.string(forKey: "WJSessionID") ?? repaired["id"]!
                if let data = try? JSONSerialization.data(withJSONObject: repaired) { try? data.write(to: sidecar, options: .atomic) }
                if let tags = try? JSONSerialization.data(withJSONObject: [], options: .sortedKeys) { try? tags.write(to: video.appendingPathExtension("tags.json"), options: .atomic) }
            }
        }
        return videos.sorted { ((try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }
    }
}

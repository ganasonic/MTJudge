import Foundation
import AVFoundation
import CryptoKit

@available(iOS 13.0, *)
@objc public final class ReceivedVideoManager: NSObject {
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
        return ["version":1, "id":id, "size":size, "sha256":try digest(url), "tags":tags, "duration":duration,
                "width":abs(track.naturalSize.width), "height":abs(track.naturalSize.height), "fps":track.nominalFrameRate,
                "bitrate":track.estimatedDataRate, "codec":codec, "created":Date().timeIntervalSince1970]
    }
    static func commit(_ source: URL, metadata: [String: Any]) throws -> URL {
        guard let id = metadata["id"] as? String, UUID(uuidString: id) != nil,
              let expected = metadata["sha256"] as? String, expected.count == 64,
              let size = metadata["size"] as? NSNumber, size.int64Value > 0 else { throw failure("受信情報が不正です。") }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent(id).appendingPathExtension("mov")
        if files.fileExists(atPath: final.path) {
            guard try digest(final) == expected else { throw failure("同じIDの異なる動画が存在します。上書きしません。") }
        } else {
            let actual = try metadataForValidation(source)
            guard actual == size.int64Value, try digest(source) == expected else { throw failure("受信した動画のサイズまたはハッシュが一致しません。再送してください。") }
            let temp = directory.appendingPathComponent(UUID().uuidString + ".partial")
            do { try files.copyItem(at: source, to: temp); try files.moveItem(at: temp, to: final) }
            catch { try? files.removeItem(at: temp); throw error }
        }
        try JSONSerialization.data(withJSONObject: metadata).write(to: final.appendingPathExtension("wj.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: metadata["tags"] ?? []).write(to: final.appendingPathExtension("tags.json"), options: .atomic)
        return final
    }
    private static func metadataForValidation(_ url: URL) throws -> Int64 {
        let asset = AVURLAsset(url: url)
        guard !asset.tracks(withMediaType: .video).isEmpty, CMTimeGetSeconds(asset.duration).isFinite, CMTimeGetSeconds(asset.duration) > 0 else { throw failure("受信ファイルが再生可能な動画ではありません。") }
        return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
    @objc public static func saveAutomatic(_ source: URL, completion: @escaping (URL?, [String: Any]?, NSError?) -> Void) {
        io.async {
            do {
                var info = try metadata(source, id: UUID().uuidString, tags: [])
                info["transferRequested"] = UserDefaults.standard.bool(forKey:"WJTransfer")
                info["peer"] = UserDefaults.standard.string(forKey:"WJPeerID") ?? ""
                let saved = try commit(source, metadata: info)
                // The temporary original is intentionally retained if any operation fails.
                DispatchQueue.main.async { completion(saved, info, nil) }
            } catch { DispatchQueue.main.async { completion(nil, nil, error as NSError) } }
        }
    }
    @objc public static func videos() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "mov" }.sorted { ((try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }
    }
}

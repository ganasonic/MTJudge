// Runs production TLS framing, receiver and storage code on macOS using a synthetic movie.
// No existing user movie or Documents directory is touched.
import Foundation
import AVFoundation
import Network

@main struct WaterJumpTransferRegression {
    static let queue = DispatchQueue(label:"test.wj.network")
    static var receivers: [VideoReceiver] = []
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n",stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func movie(_ url: URL) throws {
        let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        let input = AVAssetWriterInput(mediaType:.video, outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264, AVVideoWidthKey:64, AVVideoHeightKey:64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:64])
        writer.add(input); require(writer.startWriting(),"synthetic video writer starts"); writer.startSession(atSourceTime:.zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.005) }
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault,64,64,kCVPixelFormatType_32ARGB,nil,&pixel)
            CVPixelBufferLockBaseAddress(pixel!,[])
            memset(CVPixelBufferGetBaseAddress(pixel!),Int32(frame * 4),CVPixelBufferGetDataSize(pixel!))
            CVPixelBufferUnlockBaseAddress(pixel!,[])
            require(adaptor.append(pixel!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)),"frame \(frame)")
        }
        input.markAsFinished(); let done = DispatchSemaphore(value:0); writer.finishWriting { done.signal() }; done.wait()
        require(writer.status == .completed,"synthetic movie completed")
    }
    static func upload(_ listener: NWListener, key: String, info: [String:Any], data: Data, disconnect: Bool = false) -> [String:Any] {
        let done = DispatchSemaphore(value:0)
        var result: [String:Any] = [:]
        var channel: TransferChannel?
        queue.async {
            let connection = NWConnection(host:"127.0.0.1",port:listener.port!,using:PeerDiscoveryManager.parameters(key)!)
            let wire = TransferChannel(connection,queue:queue); channel = wire
            wire.failed = { error in result = ["error":error.localizedDescription]; done.signal() }
            wire.start {
                // Fragment the frame header to exercise TCP segmentation handling.
                let payload = try! JSONSerialization.data(withJSONObject:info)
                var length = UInt32(payload.count).bigEndian
                let prefix = withUnsafeBytes(of:&length) { Data($0) }
                wire.send(Data(prefix.prefix(1))) {
                    wire.send(Data(prefix.dropFirst()) + payload) {
                        wire.receiveJSON { ack in
                            guard ack["state"] as? String == "READY" else { result = ack; wire.close(); done.signal(); return }
                            wire.send(disconnect ? Data(data.prefix(data.count/2)) : data) {
                                if disconnect { wire.close(); result = ["disconnected":true]; done.signal(); return }
                                wire.receiveJSON { response in result = response; wire.close(); done.signal() }
                            }
                        }
                    }
                }
            }
        }
        require(done.wait(timeout:.now()+75) == .success,"transfer finished within timeout")
        withExtendedLifetime(channel) {}
        print("transfer result: \(result)")
        return result
    }
    static func main() throws {
        let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("MTJudge-WJ-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        ReceivedVideoManager.testDirectory = root.appendingPathComponent("Recordings")
        let source = root.appendingPathComponent("source.mov"); try movie(source)
        let id = UUID().uuidString
        let info = try ReceivedVideoManager.metadata(source,id:id,tags:[["category":"場所","id":"test-tag","name":"S-Air"]])
        let data = try Data(contentsOf:source)
        let key = Data(repeating:0x42,count:32).base64EncodedString()
        let listener = try NWListener(using:PeerDiscoveryManager.parameters(key)!,on:.any)
        let ready = DispatchSemaphore(value:0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.newConnectionHandler = { connection in
            let receiver = VideoReceiver(connection,queue:queue); receivers.append(receiver)
            receiver.complete = { _, _ in receivers.removeAll { $0 === receiver } }
            receiver.start()
        }
        listener.start(queue:queue)
        require(ready.wait(timeout:.now()+10) == .success,"TLS listener ready")
        require(upload(listener,key:key,info:info,data:data)["state"] as? String == "TRANSFERRED","TLS video transfer and receiver ACK")
        let destination = ReceivedVideoManager.directory.appendingPathComponent(id+".mov")
        let hashesMatch = try ReceivedVideoManager.digest(destination) == ReceivedVideoManager.digest(source)
        require(hashesMatch,"source/destination SHA-256 match")
        require(upload(listener,key:key,info:info,data:data)["state"] as? String == "TRANSFERRED","duplicate retransmission acknowledged")
        require(ReceivedVideoManager.videos().count == 1,"duplicate is not registered twice")
        let tags = try JSONSerialization.jsonObject(with:Data(contentsOf:destination.appendingPathExtension("tags.json"))) as! [[String:String]]
        require(tags.first?["name"] == "S-Air","category/tag metadata preserved")
        var corrupt = info; corrupt["id"] = UUID().uuidString; corrupt["sha256"] = String(repeating:"0",count:64)
        require(upload(listener,key:key,info:corrupt,data:data)["error"] != nil,"hash mismatch rejected")
        require(ReceivedVideoManager.videos().count == 1,"corrupted file not registered")
        var interrupted = info; interrupted["id"] = UUID().uuidString
        _ = upload(listener,key:key,info:interrupted,data:data,disconnect:true)
        Thread.sleep(forTimeInterval:1)
        require(FileManager.default.fileExists(atPath:source.path),"disconnect preserves sender original")
        require(upload(listener,key:key,info:interrupted,data:data)["state"] as? String == "TRANSFERRED","retry after disconnect succeeds")
        require(ReceivedVideoManager.videos().count == 2,"two separate recordings retained")
        let wrongKey = Data(repeating:0x23,count:32).base64EncodedString()
        require(upload(listener,key:wrongKey,info:info,data:data)["error"] != nil,"unregistered TLS key rejected")
        var traversal = info; traversal["id"] = "../../escape"
        require(upload(listener,key:key,info:traversal,data:data)["error"] != nil,"path traversal rejected")
        listener.cancel()
        VideoTransferManager.testQueueURL = root.appendingPathComponent("queue.json")
        var queued = info; queued["id"] = UUID().uuidString; queued["transferRequested"] = true; queued["created"] = 1
        let queuedURL = try ReceivedVideoManager.commit(source,metadata:queued)
        var second = queued; second["id"] = UUID().uuidString; second["created"] = 2
        _ = try ReceivedVideoManager.commit(source,metadata:second)
        let manager = VideoTransferManager()
        require(manager.pendingCount == 2,"restart reconstructs two queued recordings")
        require(manager.protects(queuedURL),"queued source protected from deletion")
        let journal = try JSONSerialization.jsonObject(with:Data(contentsOf:VideoTransferManager.testQueueURL!)) as! [[String:Any]]
        require(journal[0]["id"] as? String == queued["id"] as? String,"queue retains chronological order")
        queued["transferComplete"] = true
        try JSONSerialization.data(withJSONObject:queued).write(to:queuedURL.appendingPathExtension("wj.json"),options:.atomic)
        let restarted = VideoTransferManager()
        require(restarted.pendingCount == 1,"ACKed recording not requeued after restart")
        print("ALL TRANSFER TESTS PASSED; artifacts: \(root.path)")
    }
}

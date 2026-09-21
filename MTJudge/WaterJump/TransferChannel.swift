import Foundation
import Network

// Length-prefixed JSON control frames followed by exactly the declared video bytes.
// Every receive is bounded; movies are never accumulated in memory.
final class TransferChannel {
    let connection: NWConnection
    let queue: DispatchQueue
    var failed: ((Error) -> Void)?
    private var watchdog: DispatchSourceTimer?
    private var lastActivity = Date()
    private var closed = false
    private var connected = false
    init(_ connection: NWConnection, queue: DispatchQueue) { self.connection = connection; self.queue = queue }
    func start(_ ready: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastActivity) > (self.connected ? 60 : 15) { self.fail(NSError(domain: "MTJudge.Transfer", code: 1, userInfo: [NSLocalizedDescriptionKey:"通信が途切れました。元動画は保持しています。再送してください。"])) }
        }
        watchdog = timer; timer.resume()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.connected = true; self?.lastActivity = Date(); ready()
            case .failed(let error): self?.fail(error)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    func close() { guard !closed else { return }; closed = true; watchdog?.cancel(); watchdog = nil; connection.cancel(); failed = nil; connection.stateUpdateHandler = nil }
    func fail(_ error: Error) { guard !closed else { return }; let callback = failed; close(); callback?(error) }
    func send(_ data: Data, completion: @escaping () -> Void) {
        guard !closed else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self, !self.closed else { return }
            if let error = error { self.fail(error) } else { self.lastActivity = Date(); completion() }
        })
    }
    func sendJSON(_ object: [String: Any], completion: @escaping () -> Void) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard data.count <= 16384 else { throw NSError(domain:"MTJudge.Transfer", code:2) }
            var count = UInt32(data.count).bigEndian
            send(withUnsafeBytes(of: &count) { Data($0) } + data, completion: completion)
        } catch { fail(error) }
    }
    func receive(_ count: Int, completion: @escaping (Data) -> Void) {
        guard !closed, count > 0, count <= 65536 else { return }
        receivePart(count, previous: Data(), completion: completion)
    }
    private func receivePart(_ count: Int, previous: Data, completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - previous.count) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            if let error = error { self.fail(error); return }
            var result = previous; if let data = data { result.append(data); self.lastActivity = Date() }
            if result.count == count { completion(result) }
            else if complete { self.fail(NSError(domain:"MTJudge.Transfer",code:3,userInfo:[NSLocalizedDescriptionKey:"転送が途中で終了しました。再送してください。"])) }
            else { self.receivePart(count, previous: result, completion: completion) }
        }
    }
    func receiveJSON(_ completion: @escaping ([String: Any]) -> Void) {
        receive(4) { [weak self] header in
            let size = header.reduce(0) { ($0 << 8) | Int($1) }
            guard let self = self else { return }
            guard size > 0, size <= 16384 else { self.fail(NSError(domain:"MTJudge.Transfer",code:4)); return }
            self.receive(size) { data in
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { self.fail(NSError(domain:"MTJudge.Transfer",code:5)); return }
                completion(json)
            }
        }
    }
}

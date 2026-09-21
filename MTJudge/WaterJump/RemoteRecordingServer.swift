import Foundation
import Network
import Darwin

// A deliberately small HTTP/1.1 server: no file-serving, no uploads, bounded headers,
// one request per connection. Commands require a session token and POST.
@objc public final class RemoteRecordingServer: NSObject {
    @objc public var command: ((String) -> [String: Any])?
    @objc public var status: (() -> [String: Any])?
    @objc public var changed: (() -> Void)?
    @objc public private(set) var address = ""
    @objc public private(set) var errorMessage = ""
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var token = ""
    private let preferredPort: UInt16 = 8765
    @objc public func start() {
        guard listener == nil else { return }
        if let saved = UserDefaults.standard.string(forKey: "WJRemoteToken"), !saved.isEmpty {
            token = saved
        } else {
            token = UUID().uuidString + UUID().uuidString
            UserDefaults.standard.set(token, forKey: "WJRemoteToken")
        }
        do {
            let port = NWEndpoint.Port(rawValue: preferredPort) ?? .any
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self = self, let listener = listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.errorMessage = ""
                    self.address = "http://\(Self.wifiAddress()):\(listener.port!.rawValue)/#\(self.token)"
                case .failed(let error): self.errorMessage = "リモコン待受を開始できません: \(error.localizedDescription)"; self.stop()
                default: break
                }
                self.changed?()
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { errorMessage = "待受エラー: \(error.localizedDescription)"; changed?() }
    }
    @objc public func stop() {
        listener?.cancel(); listener = nil; address = ""; token = ""
        let active = clients.values; clients.removeAll(); active.forEach { $0.cancel() }
        changed?()
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.close(id) }
        read(id, Data())
    }
    private func close(_ id: UUID) { clients.removeValue(forKey: id)?.cancel() }
    private func read(_ id: UUID, _ previous: Data) {
        guard let connection = clients[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self = self else { return }
            var buffer = previous; if let data = data { buffer.append(data) }
            guard buffer.count <= 8192, error == nil else { self.close(id); return }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)), let header = String(data: buffer[..<end.lowerBound], encoding: .utf8) {
                self.handle(id, header)
            } else if complete { self.close(id) } else { self.read(id, buffer) }
        }
    }
    private func handle(_ id: UUID, _ header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ")
        guard request.count == 3 else { close(id); return }
        let method = String(request[0]), path = String(request[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { close(id); return }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { close(id); return }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, (headers["content-length"] ?? "0") == "0" else { respond(id, 400, ["error":"本文は不要です"]); return }
        if method == "GET" && path == "/" { send(id, 200, "text/html; charset=utf-8", Data(Self.page.utf8)); return }
        guard !token.isEmpty, headers["x-mtjudge-token"] == token else { respond(id, 403, ["error":"接続用URLをカメラ設定から開いてください"]); return }
        if let origin = headers["origin"], origin != "http://" + (headers["host"] ?? "") { respond(id, 403, [:]); return }
        if method == "GET" && path == "/status" { respond(id, 200, status?() ?? ["state":"IDLE"]); return }
        guard method == "POST", ["/start", "/stop"].contains(path) else { respond(id, 404, [:]); return }
        let response = command?(path == "/start" ? "START" : "STOP") ?? ["error":"カメラ画面を開いてください"]
        respond(id, response["error"] == nil ? 200 : 409, response)
    }
    private func respond(_ id: UUID, _ code: Int, _ object: [String: Any]) {
        send(id, code, "application/json", (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
    private func send(_ id: UUID, _ code: Int, _ type: String, _ body: Data) {
        guard let connection = clients[id] else { return }
        let header = "HTTP/1.1 \(code) Result\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }
    private static func wifiAddress() -> String {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return "Wi-Fi未接続" }
        defer { freeifaddrs(list) }
        var pointer = list
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == "en0", let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
        }
        return "Wi-Fi未接続"
    }
    private static let page = """
    <!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MTJudge Remote</title>
    <style>body{font:20px system-ui;background:#111;color:white;text-align:center;padding:20px}button{font-size:32px;padding:25px;margin:10px;border-radius:20px}#start{background:#e44;color:white}p{overflow-wrap:anywhere}</style>
    <h1>MTJudge Remote</h1><p id="connection">接続中...</p><p id="state">---</p><p id="detail"></p><button id="start" disabled>START</button><button id="stop" disabled>STOP</button>
    <script>
    const token=location.hash.slice(1)||sessionStorage.getItem('mtjudge-token')||'';if(token)sessionStorage.setItem('mtjudge-token',token);history.replaceState(null,'','/');let busy=false;
    async function request(path,method='GET'){const r=await fetch(path,{method,headers:{'X-MTJudge-Token':token},signal:AbortSignal.timeout(4000)});const data=await r.json();if(!r.ok)throw Error(data.error||'操作できません');return data;}
    async function poll(){try{let s=await request('/status');document.querySelector('#connection').textContent='接続済み';document.querySelector('#state').textContent=s.state;document.querySelector('#detail').textContent=s.message||'';document.querySelector('#start').disabled=busy||!s.canStart;document.querySelector('#stop').disabled=busy||s.state!=='RECORDING';}catch(e){document.querySelector('#connection').textContent='未接続: '+e.message;document.querySelector('#start').disabled=true;document.querySelector('#stop').disabled=true;}}
    for(const name of ['start','stop'])document.querySelector('#'+name).onclick=async()=>{busy=true;try{await request('/'+name,'POST')}catch(e){document.querySelector('#detail').textContent=e.message}finally{busy=false;poll()}};
    setInterval(poll,1000);poll();
    </script></html>
    """
}

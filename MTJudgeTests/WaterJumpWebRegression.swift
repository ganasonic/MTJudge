import Foundation
@main struct WaterJumpWebRegression {
    static func main() {
        let server = RemoteRecordingServer()
        var recording = false
        server.status = { ["state":recording ? "RECORDING" : "READY", "canStart":!recording] }
        server.command = { command in
            if command == "START" && recording { return ["error":"録画中です"] }
            recording = command == "START"
            return server.status!()
        }
        var started = false
        server.changed = {
            guard !server.address.isEmpty, !started else { return }; started = true
            let parts = server.address.components(separatedBy:"#")
            let token = parts[1]
            var base = URLComponents(string:parts[0])!; base.host = "127.0.0.1"
            let root = base.url!
            DispatchQueue.global().async {
                func check(_ path: String, _ method: String, _ auth: String?, _ origin: String? = nil, expected: Int) {
                    var request = URLRequest(url:root.appendingPathComponent(path)); request.httpMethod = method; request.timeoutInterval = 5
                    if let auth = auth { request.setValue(auth,forHTTPHeaderField:"X-MTJudge-Token") }
                    if let origin = origin { request.setValue(origin,forHTTPHeaderField:"Origin") }
                    let done = DispatchSemaphore(value:0); var status = 0
                    URLSession.shared.dataTask(with:request) { _,response,_ in status = (response as? HTTPURLResponse)?.statusCode ?? 0; done.signal() }.resume()
                    guard done.wait(timeout:.now()+8) == .success, status == expected else { fputs("FAIL \(method) \(path): \(status) != \(expected)\n",stderr); exit(1) }
                    print("PASS \(method) \(path) -> \(status)")
                }
                check("", "GET", nil,expected:200)
                check("status","GET",nil,expected:403)
                check("start","GET",token,expected:404)
                check("start","POST",token,"http://untrusted.invalid",expected:403)
                check("start","POST",token,expected:200)
                check("start","POST",token,expected:409)
                check("status","GET",token,expected:200)
                check("stop","POST",token,expected:200)
                check("stop","POST",token,expected:200)
                check("start","POST","invalid",expected:403)
                print("ALL WEB TESTS PASSED")
                exit(0)
            }
        }
        server.start(); dispatchMain()
    }
}

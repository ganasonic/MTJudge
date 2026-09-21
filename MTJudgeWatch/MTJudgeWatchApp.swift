import SwiftUI
import WatchConnectivity

final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state = "IDLE"
    @Published var message = "iPhoneでMTJudge Cameraを開いてください"
    @Published var reachable = false
    @Published var canStart = false
    @Published var sending = false
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func update(_ response: [String: Any]) {
        DispatchQueue.main.async {
            self.reachable = WCSession.default.isReachable
            if let error = response["error"] as? String { self.state = "ERROR"; self.message = error; return }
            self.state = response["state"] as? String ?? "IDLE"
            self.message = response["message"] as? String ?? ""
            self.canStart = response["canStart"] as? Bool ?? false
        }
    }
    func send(_ command: String) {
        reachable = WCSession.default.isReachable
        guard reachable else { state = "ERROR"; message = "iPhoneと接続できません"; return }
        guard !sending else { return }; sending = true
        WCSession.default.sendMessage(["command": command], replyHandler: { response in
            DispatchQueue.main.async { self.sending = false; self.update(response) }
        }, errorHandler: { error in
            DispatchQueue.main.async { self.sending = false; self.state = "ERROR"; self.message = "通信を確認してください。開始済み録画はiPhone側で自動停止します。" }
        })
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { update(session.receivedApplicationContext) }
    func sessionReachabilityDidChange(_ session: WCSession) { update(session.receivedApplicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { update(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { update(applicationContext) }
}
@main struct MTJudgeWatchApp: App {
    @StateObject private var remote = WatchRemote()
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 8) {
                    Text(remote.state).bold()
                    Text(remote.reachable ? "接続済み" : "未接続").font(.caption)
                    Button(remote.state == "RECORDING" ? "STOP" : "REC") { remote.send(remote.state == "RECORDING" ? "STOP" : "START") }
                        .font(.system(size: 32, weight: .bold)).tint(.red)
                        .disabled(remote.sending || !remote.reachable || (!remote.canStart && remote.state != "RECORDING"))
                    Text(remote.message).font(.caption)
                    Button("状態更新") { remote.send("STATUS") }
                }
            }.onAppear { remote.send("STATUS") }
        }
    }
}

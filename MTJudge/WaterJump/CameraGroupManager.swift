import Foundation
import UIKit
import MultipeerConnectivity
import CryptoKit

/// Membership/control-plane only. Video transfer and HTTP recording keep using
/// PeerDiscoveryManager and the existing WJ defaults (one shared configuration).
@objc public final class CameraGroupManager: NSObject {
    @objc public var changed: (() -> Void)?
    @objc public var settingsChanged: (() -> Void)?
    @objc public var approval: ((String, String, @escaping (Bool) -> Void) -> Void)?
    @objc public var canChangeSettings: (() -> Bool)?
    @objc public private(set) var groups: [[String:String]] = []
    @objc public private(set) var message = "未設定"
    @objc public var automatic: Bool { defaults.string(forKey:"WJConnectionMode") == "automatic" }
    @objc public var groupID: String { defaults.string(forKey:"WJCameraGroupID") ?? "" }
    @objc public var role: String { defaults.string(forKey:"WJGroupRole") ?? "" }
    @objc public var members: [[String:String]] {
        var result = roster
        for i in result.indices { result[i]["connected"] = authenticated[result[i]["id"] ?? ""] != nil ? "1" : "0" }
        return result
    }
    private let defaults = UserDefaults.standard
    private let discovery: PeerDiscoveryManager
    private let peer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var found: [String:(MCPeerID,[String:String])] = [:]
    private var authenticated: [String:MCPeerID] = [:]
    private var invitations: [String:String] = [:]
    private var enrollments = Set<String>()
    private var challenges: [String:String] = [:]
    private var descriptors: [String:[String:String]] = [:]
    private var invitedAt: [String:Date] = [:]
    private var timer: Timer?
    private var remote = ""
    private var active = false
    private var searching = false
    private var advertisement = ""
    private var retryPeerID = ""
    private var retryToken = ""
    private var lastRetryToken = ""
    private var roster: [[String:String]] {
        get { defaults.array(forKey:"WJGroupMembers") as? [[String:String]] ?? [] }
        set { defaults.set(newValue,forKey:"WJGroupMembers") }
    }
    private var mainID: String { defaults.string(forKey:"WJGroupMainID") ?? "" }
    private static let roles = ["CAMERA_1","CAMERA_2","CAMERA_3","RECEIVER"]
    private var ownName: String {
        let name = defaults.string(forKey:"WJCameraName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? UIDevice.current.name : name
    }
    private func keyName(_ id: String) -> String { "group-" + groupID + "-" + id }
    private func key(_ id: String) -> String? { PeerDiscoveryManager.secret(keyName(id)) }
    private func proof(_ key: String, _ text: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for:Data(text.utf8),using:SymmetricKey(data:Data(base64Encoded:key) ?? Data()))).base64EncodedString()
    }
    private func matches(_ value: String?, key: String, text: String) -> Bool {
        guard let value = value, let mac = Data(base64Encoded:value), let data = Data(base64Encoded:key) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac,authenticating:Data(text.utf8),using:SymmetricKey(data:data))
    }
    @objc public init(discovery: PeerDiscoveryManager) {
        self.discovery = discovery
        if let data = UserDefaults.standard.data(forKey:"WJGroupPeerIdentity"), let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass:MCPeerID.self,from:data), saved.displayName == discovery.deviceID { peer = saved }
        else { peer = MCPeerID(displayName:discovery.deviceID) }
        super.init()
        if let data = try? NSKeyedArchiver.archivedData(withRootObject:peer,requiringSecureCoding:true) { defaults.set(data,forKey:"WJGroupPeerIdentity") }
        makeSession()
        if automatic { rebuild() }
        timer = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in self?.tick() }
    }
    deinit { timer?.invalidate(); session?.disconnect() }
    private func makeSession() { session = MCSession(peer:peer,securityIdentity:nil,encryptionPreference:.required); session.delegate = self }
    @objc public func beginSearch() { searching = true; configure(active:true,remoteAddress:remote) }
    @objc public func configure(active: Bool, remoteAddress: String) {
        self.active = active; remote = remoteAddress
        guard active else { stopTransport(); return }
        if (searching || automatic) && browser == nil {
            browser = MCNearbyServiceBrowser(peer:peer,serviceType:"mtjudge-group")
            browser?.delegate = self; browser?.startBrowsingForPeers()
        }
        let signature = automatic && role == "MAIN" ? groupID + ownName + retryToken : ""
        if signature != advertisement {
            advertiser?.stopAdvertisingPeer(); advertiser = nil; advertisement = signature
            if !signature.isEmpty {
                advertiser = MCNearbyServiceAdvertiser(peer:peer,discoveryInfo:["group":groupID,"name":defaults.string(forKey:"WJCameraGroupName") ?? ownName,"main":discovery.deviceID,"retryPeer":retryPeerID,"retry":retryToken],serviceType:"mtjudge-group")
                advertiser?.delegate = self; advertiser?.startAdvertisingPeer()
            }
        }
    }
    private func stopTransport() {
        browser?.stopBrowsingForPeers(); browser = nil
        advertiser?.stopAdvertisingPeer(); advertiser = nil; advertisement = ""
        session.disconnect(); authenticated.removeAll(); descriptors.removeAll(); challenges.removeAll(); invitations.removeAll(); enrollments.removeAll(); invitedAt.removeAll()
        found.removeAll(); groups.removeAll()
        if automatic { rebuild() }
        message = automatic ? "再接続待ち" : "従来方式"; changed?()
    }
    @objc public func createGroup(_ name: String) -> Bool {
        guard canChangeSettings?() != false else { message = "録画・転送・受信の終了後に変更してください"; changed?(); return false }
        clearConfiguration()
        defaults.set(UUID().uuidString,forKey:"WJCameraGroupID")
        defaults.set(name.isEmpty ? ownName : name,forKey:"WJCameraGroupName")
        defaults.set(discovery.deviceID,forKey:"WJGroupMainID")
        defaults.set("MAIN",forKey:"WJGroupRole"); defaults.set("automatic",forKey:"WJConnectionMode")
        applyRole(); message = "グループ作成済み・参加待ち"; settingsChanged?(); return true
    }
    @objc public func joinGroup(_ id: String, role requested: String) -> Bool {
        guard canChangeSettings?() != false, Self.roles.contains(requested), let entry = found[id] else { message = "グループを再検索してください（処理中は変更できません）"; changed?(); return false }
        let info = entry.1, host = entry.0
        clearConfiguration()
        defaults.set(id,forKey:"WJCameraGroupID"); defaults.set(info["name"],forKey:"WJCameraGroupName")
        defaults.set(host.displayName,forKey:"WJGroupMainID"); defaults.set(requested,forKey:"WJGroupRole")
        defaults.set("automatic",forKey:"WJConnectionMode")
        found[id] = (host,info)
        applyRole(); settingsChanged?(); invite(host); return true
    }
    @objc public func useManual() -> Bool {
        guard canChangeSettings?() != false else { return false }
        // Clear membership and credentials first; no automatic/manual destination mixing.
        clearConfiguration(); defaults.set("manual",forKey:"WJConnectionMode")
        message = "従来方式へ切り替えました。QRまたはURLで登録してください"; settingsChanged?(); return true
    }
    @objc public func reset() -> Bool {
        guard canChangeSettings?() != false else { message = "録画・転送・受信の終了後にリセットしてください。未転送動画は保持されます"; changed?(); return false }
        for p in authenticated.values { send(["type":"reset"],to:p) }
        clearConfiguration(); defaults.removeObject(forKey:"WJConnectionMode")
        message = "設定をリセットしました"; settingsChanged?(); return true
    }
    @objc public func removeMember(_ id: String) -> Bool {
        guard role == "MAIN", canChangeSettings?() != false else { return false }
        if let p = authenticated[id] { send(["type":"reset"],to:p) }
        authenticated.removeValue(forKey:id); descriptors.removeValue(forKey:id); invitations.removeValue(forKey:id)
        roster = roster.filter { $0["id"] != id }
        PeerDiscoveryManager.removeSecret(keyName(id)); PeerDiscoveryManager.removeSecret("sender-"+id)
        rebuild(); return true
    }
    private func clearConfiguration() {
        for p in authenticated.values { send(["type":"leave"],to:p) }
        stopTransport(); makeSession()
        // Explicit communication-only allowlist; never remove files or recording metadata.
        for name in ["WJCameraGroupID","WJCameraGroupName","WJGroupRole","WJGroupMainID","WJGroupMembers","WJGroupAllowedSenders","WJCameraRole","WJPeerID","WJPeerName","WJPeerRegistrations","WJTransferEndpoint","WJRemoteToken","WJSessionID","WJRemoteStartInProgress","WJSubCameraURL","WJSubCamera2URL","WJSubCamera3URL"] { defaults.removeObject(forKey:name) }
        for name in ["WJMode","WJWeb","WJWatch","WJTransfer","WJReceive","WJTagBeforeTransfer","WJUseSubCamera","WJUseSubCamera2","WJUseSubCamera3"] { defaults.set(false,forKey:name) }
        defaults.set(UUID().uuidString,forKey:"WJConnectionGeneration")
        discovery.clearRegistrationsAndCredentials()
    }
    private func applyRole() {
        defaults.set(role != "RECEIVER",forKey:"WJMode")
        defaults.set(role != "RECEIVER",forKey:"WJWeb")
        defaults.set(role == "MAIN" || role == "RECEIVER",forKey:"WJReceive")
        defaults.set(role != "RECEIVER",forKey:"WJTransfer")
        defaults.set(role.hasPrefix("CAMERA_") ? "SUB_CAMERA" : "MAIN_CAMERA",forKey:"WJCameraRole")
        if role.hasPrefix("CAMERA_") { defaults.set(false,forKey:"WJTagBeforeTransfer") }
    }
    @objc public func reconnectMember(_ id: String) -> Bool {
#if DEBUG
        NSLog("[CameraGroup] reconnect requested role=%@ peer=%@",role,id)
#endif
        guard automatic, roster.contains(where: { $0["id"] == id }) else { message = "接続端末一覧を開き直してください"; changed?(); return false }
        if authenticated[id] != nil { message = "すでに接続されています"; changed?(); return true }
        if role == "MAIN" {
            // Retry only the selected member; keep other connections and all credentials.
            if let p = session.connectedPeers.first(where: { $0.displayName == id }) { session.cancelConnectPeer(p) }
            invitations.removeValue(forKey:id); challenges.removeValue(forKey:id); enrollments.remove(id)
            retryPeerID = id; retryToken = UUID().uuidString
            configure(active:true,remoteAddress:remote)
        } else {
            guard id == mainID else { return false }
            browser?.stopBrowsingForPeers(); browser = nil
            configure(active:true,remoteAddress:remote)
            if let host = found[groupID]?.0 { retryHost(host) }
            else { invitedAt.removeValue(forKey:mainID) }
        }
        message = "再接続を試みています。相手端末でアプリを開いてください。承認が必要な場合はメイン端末で許可してください。"
        changed?(); return true
    }
    private func retryHost(_ host: MCPeerID) {
        guard authenticated[host.displayName] == nil else { return }
#if DEBUG
        NSLog("[CameraGroup] retry host=%@",host.displayName)
#endif
        invitedAt.removeValue(forKey:host.displayName)
        session.cancelConnectPeer(host)
        let currentSession = session
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in
            guard let self = self, self.session === currentSession, self.automatic, self.mainID == host.displayName, self.authenticated[host.displayName] == nil else { return }
            self.invitedAt.removeValue(forKey:host.displayName); self.invite(host)
        }
    }
    private func invite(_ host: MCPeerID) {
        guard automatic, role != "MAIN", host.displayName == mainID, !session.connectedPeers.contains(host) else { return }
        if let date = invitedAt[mainID], Date().timeIntervalSince(date) < 35 { return }
        invitedAt[mainID] = Date()
        let info = ["group":groupID,"role":role,"name":ownName,"enroll":key(mainID) == nil ? "1":"0"]
        browser?.invitePeer(host,to:session,withContext:try? JSONSerialization.data(withJSONObject:info),timeout:30)
        message = "メイン端末の参加承認／接続を待っています"; changed?()
    }
    private func descriptor() -> [String:String] {
        var info = ["id":discovery.deviceID,"role":role,"name":ownName,"remote":role.hasPrefix("CAMERA_") ? remote : "","ready":discovery.listenerReady ? "1":"0"]
        if role == "MAIN" || role == "RECEIVER" { info["pairing"] = discovery.pairingCode }
        return info
    }
    private func send(_ info: [String:Any], to target: MCPeerID) {
        var packet = info; packet["group"] = groupID
        guard let data = try? JSONSerialization.data(withJSONObject:packet), data.count <= 65536 else { return }
        do { try session.send(data,toPeers:[target],with:.reliable) }
        catch { message = "設定交換に失敗しました。再接続待ち"; changed?() }
    }
    private func tick() {
        guard active, automatic else { return }
        if role != "MAIN", let host = found[groupID]?.0 { invite(host) }
        for p in authenticated.values { send(["type":"descriptor","device":descriptor()],to:p) }
        rebuild()
    }
    private func acceptDescriptor(_ d: [String:String], from p: MCPeerID) {
        guard d["id"] == p.displayName, d["name",default:""].count <= 100 else { return }
        if role == "MAIN" {
            guard roster.contains(where:{$0["id"] == p.displayName && $0["role"] == d["role"]}) else { return }
        } else { guard p.displayName == mainID, d["role"] == "MAIN" else { return } }
        if role != "MAIN" { roster = [["id":p.displayName,"role":"MAIN","name":d["name"] ?? "MTJudge"]] }
        else if let name = d["name"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Refresh the saved list as well as the live descriptor after a camera is renamed.
            var members = roster
            if let index = members.firstIndex(where: { $0["id"] == p.displayName }), members[index]["name"] != name {
                members[index]["name"] = name; roster = members
            }
        }
        descriptors[p.displayName] = d; rebuild()
    }
    private func rebuild() {
        guard automatic else { return }
        var targets: [[String:String]] = [], allowed: [String] = []
        if role == "MAIN" {
            for index in 1...3 {
                let suffix = index == 1 ? "" : String(index)
                let d = descriptors.values.first { $0["role"] == "CAMERA_\(index)" }
                let url = d?["remote"] ?? ""
                let valid = URLComponents(string:url).flatMap { c in c.scheme == "http" && c.host != nil && !(c.fragment ?? "").isEmpty ? c : nil } != nil
                defaults.set(valid ? url : "",forKey:"WJSubCamera\(suffix)URL")
                defaults.set(valid,forKey:"WJUseSubCamera\(suffix)")
                if let id = d?["id"] { allowed.append(id) }
            }
            targets = descriptors.values.filter { $0["role"] == "RECEIVER" && $0["ready"] == "1" }
        } else if let main = descriptors[mainID], main["ready"] == "1" {
            if role == "RECEIVER" { allowed = [mainID] }
            else { targets = [main] }
        }
        // Keep identities for offline approved receivers, never a stale IP address.
        let expected = role == "MAIN" ? roster.filter { $0["role"] == "RECEIVER" } : (role.hasPrefix("CAMERA_") ? roster.filter { $0["id"] == mainID } : [])
        var registrations = discovery.registeredPeers.filter { entry in entry["groupID"] == groupID && expected.contains { $0["id"] == entry["id"] } }
        for d in targets {
            guard let id = d["id"], let code = d["pairing"], code.hasPrefix(id+":"), discovery.storeRegistration(name:d["name"] ?? "MTJudge",code:code) else { continue }
            registrations.removeAll { $0["id"] == id }
            registrations.append(["id":id,"name":d["name"] ?? "MTJudge","endpoint":"bonjour://"+id,"groupID":groupID])
        }
        defaults.set(registrations,forKey:"WJPeerRegistrations")
        defaults.set(registrations.first?["id"] ?? "",forKey:"WJPeerID")
        defaults.set(registrations.first?["name"] ?? "",forKey:"WJPeerName")
        defaults.set(registrations.first?["endpoint"] ?? "",forKey:"WJTransferEndpoint")
        defaults.set(allowed,forKey:"WJGroupAllowedSenders")
        if role == "MAIN" { message = authenticated.isEmpty ? "グループ作成済み・参加待ち" : "認証済み \(authenticated.count)台（接続状態は端末一覧で確認）" }
        else if descriptors[mainID] == nil { message = "未接続・メイン端末を検索中" }
        else if role == "RECEIVER" ? discovery.listenerReady : !registrations.isEmpty && discovery.peerAvailable && URLComponents(string:remote)?.host != nil { message = "接続設定完了（撮影端末はカメラ画面を開いてください）" }
        else { message = "認証済み・通信サービスの準備待ち" }
        changed?()
    }
}

extension CameraGroupManager: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String:String]?) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.browser(browser,foundPeer:p,withDiscoveryInfo:info) }; return }
        guard self.browser === browser else { return }
        guard let info = info, let id = info["group"], UUID(uuidString:id) != nil, info["main"] == p.displayName, p != peer else { return }
        found[id] = (p,info); groups = found.values.map{$0.1}; changed?()
        if automatic, groupID == id, mainID == p.displayName {
            if info["retryPeer"] == discovery.deviceID, let token = info["retry"], !token.isEmpty, token != lastRetryToken {
                lastRetryToken = token; retryHost(p)
            } else { invite(p) }
        }
    }
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.browser(browser,lostPeer:p) }; return }; guard self.browser === browser else { return }; found = found.filter{$0.value.0 != p}; groups = found.values.map{$0.1}; changed?() }
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) { DispatchQueue.main.async { self.message = "グループ検索に失敗: \(error.localizedDescription)"; self.changed?() } }
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) { DispatchQueue.main.async { self.message = "グループ公開に失敗: \(error.localizedDescription)"; self.changed?() } }
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.advertiser(advertiser,didReceiveInvitationFromPeer:p,withContext:context,invitationHandler:invitationHandler) }; return }
        guard self.advertiser === advertiser else { invitationHandler(false,nil); return }
        guard automatic, role == "MAIN", let context = context, context.count <= 4096,
              let request = (try? JSONSerialization.jsonObject(with:context)) as? [String:String],
              request["group"] == groupID, let requested = request["role"], Self.roles.contains(requested), UUID(uuidString:p.displayName) != nil else { invitationHandler(false,nil); return }
        // Count identities, not connections: reconnecting members keep their slot,
        // and pending approvals reserve slots without counting an identity twice.
        let occupants = Set(roster.filter { $0["role"] == requested }.compactMap { $0["id"] })
            .union(invitations.filter { $0.value == requested }.map { $0.key })
            .subtracting([p.displayName])
        let collision = occupants.count >= (requested == "RECEIVER" ? 3 : 1)
        guard !collision else { message = requested == "RECEIVER" ? "追加の受信端末は最大3台です" : "役割が重複しています: \(requested)"; changed?(); invitationHandler(false,nil); return }
        let gid = groupID
        invitations[p.displayName] = requested
        let finish: (Bool) -> Void = { [weak self] approved in
            guard let self = self else { invitationHandler(false,nil); return }
            guard approved, self.automatic, self.groupID == gid, self.role == "MAIN" else { self.invitations.removeValue(forKey:p.displayName); invitationHandler(false,nil); return }
            if request["enroll"] == "1" || !self.roster.contains(where:{$0["id"] == p.displayName}) || self.key(p.displayName) == nil { self.enrollments.insert(p.displayName) }
            invitationHandler(true,self.session)
        }
        if request["enroll"] != "1", roster.contains(where:{$0["id"] == p.displayName && $0["role"] == requested}), key(p.displayName) != nil { finish(true) }
        else if let approval = approval { approval(request["name"] ?? p.displayName,requested,finish) }
        else { finish(false) }
    }
    public func session(_ session: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.session === session, self.automatic else { return }
            if state == .connected, self.role == "MAIN", self.invitations[p.displayName] != nil {
                var secret = self.key(p.displayName)
                let enrolling = self.enrollments.contains(p.displayName)
                if enrolling { secret = SymmetricKey(size:.bits256).withUnsafeBytes { Data($0).base64EncodedString() }; guard PeerDiscoveryManager.store(secret!,self.keyName(p.displayName)) else { return } }
                guard let secret = secret else { return }
                let nonce = UUID().uuidString; self.challenges[p.displayName] = nonce
                var packet = ["type":"challenge","nonce":nonce,"proof":self.proof(secret,"host|"+self.groupID+"|"+nonce)]
                if enrolling { packet["enrollmentKey"] = secret }
                self.send(packet,to:p)
            } else if state == .notConnected {
                self.authenticated.removeValue(forKey:p.displayName); self.descriptors.removeValue(forKey:p.displayName); self.invitations.removeValue(forKey:p.displayName); self.challenges.removeValue(forKey:p.displayName); self.enrollments.remove(p.displayName)
                self.rebuild()
            }
        }
    }
    public func session(_ session: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
        guard data.count <= 65536 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.session === session, self.automatic,
                  let packet = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any], packet["group"] as? String == self.groupID,
                  let type = packet["type"] as? String else { return }
            if type == "challenge", p.displayName == self.mainID, self.role != "MAIN", let nonce = packet["nonce"] as? String {
                if self.key(p.displayName) == nil, let secret = packet["enrollmentKey"] as? String, Data(base64Encoded:secret)?.count == 32 { guard PeerDiscoveryManager.store(secret,self.keyName(p.displayName)) else { return } }
                guard let secret = self.key(p.displayName), self.matches(packet["proof"] as? String,key:secret,text:"host|"+self.groupID+"|"+nonce) else { self.message = "メイン端末の認証に失敗しました"; self.changed?(); return }
                self.authenticated[p.displayName] = p
                self.send(["type":"authenticate","proof":self.proof(secret,"member|"+self.groupID+"|"+nonce),"device":self.descriptor()],to:p)
            } else if type == "authenticate", self.role == "MAIN", let nonce = self.challenges.removeValue(forKey:p.displayName), let secret = self.key(p.displayName), self.matches(packet["proof"] as? String,key:secret,text:"member|"+self.groupID+"|"+nonce), let d = packet["device"] as? [String:String], d["id"] == p.displayName, d["role"] == self.invitations[p.displayName] {
                var members = self.roster; members.removeAll{$0["id"] == p.displayName}; members.append(["id":p.displayName,"role":d["role"]!,"name":d["name"] ?? "MTJudge"]); self.roster = members
                self.authenticated[p.displayName] = p; self.acceptDescriptor(d,from:p)
#if DEBUG
                NSLog("[CameraGroup] authenticated member=%@",p.displayName)
#endif
                self.send(["type":"descriptor","device":self.descriptor()],to:p)
            } else if self.authenticated[p.displayName] == p {
                if type == "descriptor", let d = packet["device"] as? [String:String] { self.acceptDescriptor(d,from:p) }
                else if type == "reset" || type == "leave" {
                    self.authenticated.removeValue(forKey:p.displayName); self.descriptors.removeValue(forKey:p.displayName)
                    var members = self.roster; members.removeAll{$0["id"] == p.displayName}; self.roster = members
                    PeerDiscoveryManager.removeSecret(self.keyName(p.displayName)); self.rebuild()
                }
            }
        }
    }
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

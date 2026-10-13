import Foundation
import Network
import Security
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 13.0, *)
@objc public final class PeerDiscoveryManager: NSObject {
    @objc public var changed: (() -> Void)?
    var accepted: ((NWConnection) -> Void)?
    @objc public private(set) var peers: [[String: String]] = []
    @objc public private(set) var message = ""
    #if DEBUG
    static var testKeychainService: String?
    #endif
    private static var keychainService: String {
        #if DEBUG
        if let value = testKeychainService { return value }
        #endif
        return "MTJudge.WaterJump"
    }
    private var browser: NWBrowser?
    private var listener: NWListener?
    @objc public private(set) var listenerReady = false
    private var advertisementSignature = ""
    private var endpoints: [String: NWEndpoint] = [:]
    @objc public var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "WJDeviceID") { return id }
        let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "WJDeviceID"); return id
    }
    @objc public var pairingCode: String {
        let name = "receiver-" + deviceID
        let secret: String
        if let existing = Self.secret(name) { secret = existing }
        else {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
            secret = Data(bytes).base64EncodedString()
            guard Self.store(secret, name) else { return "" }
        }
        return deviceID + ":" + secret
    }
    @objc public var selectedName: String { UserDefaults.standard.string(forKey: "WJPeerName") ?? "未登録" }
    @objc public var selectedID: String { UserDefaults.standard.string(forKey: "WJPeerID") ?? "" }
    @objc public var peerAvailable: Bool { endpoints[selectedID] != nil }
    @objc public var registeredPeers: [[String: String]] {
        (UserDefaults.standard.array(forKey: "WJPeerRegistrations") as? [[String: String]]) ?? []
    }
    func storeRegistration(name: String, code: String) -> Bool {
        let parts = code.split(separator:":",maxSplits:1).map(String.init)
        guard parts.count == 2, UUID(uuidString:parts[0]) != nil, parts[0] != deviceID, Data(base64Encoded:parts[1])?.count == 32 else { return false }
        return Self.store(parts[1],"sender-"+parts[0])
    }
    @objc public func clearRegistrationsAndCredentials() {
        browser?.cancel(); browser = nil; listener?.cancel(); listener = nil; listenerReady = false
        endpoints.removeAll(); peers.removeAll(); advertisementSignature = ""
        var q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Self.keychainService,kSecReturnAttributes as String:true,kSecMatchLimit as String:kSecMatchLimitAll]
        var result: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess, let entries = result as? [[String:Any]] {
            for entry in entries { if let account = entry[kSecAttrAccount as String] as? String, account.hasPrefix("sender-") || account.hasPrefix("receiver-") || account.hasPrefix("group-") { Self.removeSecret(account) } }
        }
        q.removeAll()
        UserDefaults.standard.removeObject(forKey:"WJPeerRegistrations")
        UserDefaults.standard.removeObject(forKey:"WJPeerID"); UserDefaults.standard.removeObject(forKey:"WJPeerName")
    }
    @objc public func registerPeer(_ name: String, code: String) -> Bool {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, UUID(uuidString: parts[0]) != nil, parts[0] != deviceID,
              Data(base64Encoded: parts[1])?.count == 32, Self.store(parts[1], "sender-" + parts[0]) else { return false }
        var registrations = registeredPeers
        registrations.removeAll { $0["id"] == parts[0] }
        registrations.append(["id": parts[0], "name": name])
        if registrations.count > 3 { registrations = Array(registrations.suffix(3)) }
        UserDefaults.standard.set(registrations, forKey: "WJPeerRegistrations")
        // 既存の単一転送先設定は保持し、最後に登録した端末を選択先にする。
        UserDefaults.standard.set(parts[0], forKey: "WJPeerID")
        UserDefaults.standard.set(name, forKey: "WJPeerName")
        changed?(); return true
    }
    // DNS-SD service names have a 63-byte UTF-8 limit, including the UUID.
    static func serviceNamePrefix(_ value: String, bytes: Int) -> String {
        var result = ""
        for character in value { let next = result + String(character); if next.utf8.count > bytes { break }; result = next }
        return result
    }
    @objc public func configure(receiving: Bool, browsing: Bool) {
        if browsing && browser == nil {
            let browser = NWBrowser(for: .bonjour(type: "_mtjudge-wj._tcp", domain: nil), using: .tcp)
            self.browser = browser
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self = self else { return }
                self.endpoints.removeAll(); self.peers.removeAll()
                for result in results {
                    guard case .service(let name, _, _, _) = result.endpoint,
                          let id = name.split(separator: "~").last.map(String.init), UUID(uuidString: id) != nil, id != self.deviceID else { continue }
                    let parts = name.split(separator: "~").map(String.init)
                    // 新形式: groupToken~roleCode~groupName~deviceID（短いBonjour名）
                    // 旧形式: deviceName~groupID~role~groupName~deviceID
                    let shortFormat = parts.count == 4 && UUID(uuidString: parts.last ?? "") != nil
                    let advertisedGroup = shortFormat ? parts[0] : (parts.count >= 4 ? parts[1] : "")
                    let localGroup = UserDefaults.standard.string(forKey: "WJCameraGroupID") ?? ""
                    let localToken = localGroup.count > 12 ? String(localGroup.prefix(8)) : localGroup
                    if UserDefaults.standard.string(forKey:"WJConnectionMode") != "automatic", !localToken.isEmpty && !advertisedGroup.isEmpty && localToken != advertisedGroup { continue }
                    self.endpoints[id] = result.endpoint
                    var peer: [String: String] = ["id": id, "name": shortFormat ? (parts[2].isEmpty ? "MTJudge" : parts[2]) : (parts.first ?? "MTJudge")]
                    if advertisedGroup.count > 0 { peer["groupID"] = advertisedGroup }
                    if shortFormat {
                        peer["role"] = parts[1] == "S" ? "SUB_CAMERA" : "MAIN_CAMERA"
                        peer["groupName"] = parts[2]
                    } else {
                        if parts.count >= 4 { peer["role"] = parts[2] }
                        if parts.count >= 5 { peer["groupName"] = parts[3] }
                    }
                    self.peers.append(peer)
                }
                self.peers.sort { ($0["name"] ?? "") < ($1["name"] ?? "") }; self.changed?()
            }
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state { self?.message = "端末検索エラー: \(error.localizedDescription)"; self?.changed?() }
                if case .waiting(_) = state { self?.message = "Wi-Fi接続とローカルネットワーク許可を確認してください"; self?.changed?() }
            }
            browser.start(queue: .main)
        } else if !browsing { browser?.cancel(); browser = nil; endpoints.removeAll(); peers.removeAll() }
        // グループ参加端末を検出できるよう、受信待機がOFFでも
        // グループ設定済み端末はBonjour広告だけ開始する。
        // 実際の受信は self.receiving == true の場合だけ accepted で処理する。
        let configuredGroup = UserDefaults.standard.string(forKey: "WJCameraGroupID") ?? ""
        let shouldAdvertise = receiving || (browsing && !configuredGroup.isEmpty)
        let signature = configuredGroup + (UserDefaults.standard.string(forKey:"WJCameraRole") ?? "") + (UserDefaults.standard.string(forKey:"WJCameraGroupName") ?? "")
        if signature != advertisementSignature { listener?.cancel(); listener = nil; listenerReady = false; advertisementSignature = signature }
        if shouldAdvertise && listener == nil {
            let code = pairingCode.components(separatedBy: ":")
            guard code.count == 2, let params = Self.parameters(code[1]) else { message = "ペアリング鍵を作成できません"; changed?(); return }
            do {
                let listener = try NWListener(using: params)
                self.listener = listener
                #if canImport(UIKit)
                let deviceName = UIDevice.current.name
                #else
                let deviceName = ProcessInfo.processInfo.hostName
                #endif
                var group = UserDefaults.standard.string(forKey: "WJCameraGroupID") ?? ""
                if group.count > 12 { group = String(group.prefix(8)) }
                let groupName = UserDefaults.standard.string(forKey: "WJCameraGroupName") ?? ""
                let role = UserDefaults.standard.string(forKey: "WJCameraRole") ?? "MAIN_CAMERA"
                let safeGroup = group.replacingOccurrences(of: "~", with: "-")
                let safeGroupName = groupName.replacingOccurrences(of: "~", with: "-")
                let roleCode = role == "SUB_CAMERA" ? "S" : "M"
                let name = safeGroup.isEmpty ? (Self.serviceNamePrefix(deviceName,bytes:26) + "~" + deviceID) : (safeGroup + "~" + roleCode + "~" + Self.serviceNamePrefix(safeGroupName,bytes:15) + "~" + deviceID)
                listener.service = NWListener.Service(name: name, type: "_mtjudge-wj._tcp")
                listener.newConnectionHandler = { [weak self] connection in
                    guard let accepted = self?.accepted else { connection.cancel(); return }; accepted(connection)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self = self, let listener = listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.listenerReady = true; self.message = "受信待機中"
                    case .failed(let error): self.listenerReady = false; self.message = "受信待受エラー: \(error.localizedDescription)"
                    case .waiting(_): self.message = "Wi-Fiとローカルネットワーク許可を確認してください"
                    default: break
                    }
                    self.changed?()
                }
                listener.start(queue: .main)
            } catch { message = error.localizedDescription }
        } else if !shouldAdvertise { listener?.cancel(); listener = nil; listenerReady = false }
        changed?()
    }
    func connection(to id: String) -> NWConnection? {
        guard let endpoint = endpoints[id], let key = Self.secret("sender-" + id), let params = Self.parameters(key) else { return nil }
        return NWConnection(to: endpoint, using: params)
    }
    static func parameters(_ secret: String) -> NWParameters? {
        guard let data = Data(base64Encoded: secret), data.count == 32 else { return nil }
        let tls = NWProtocolTLS.Options()
        let psk = data.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("MTJudge-WJ-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, psk as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_add_tls_ciphersuite(tls.securityProtocolOptions, TLS_PSK_WITH_AES_128_GCM_SHA256)
        let tcp = NWProtocolTCP.Options(); tcp.connectionTimeout = 15
        return NWParameters(tls: tls, tcp: tcp)
    }
    static func removeSecret(_ name: String) { SecItemDelete(query(name) as CFDictionary) }
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:Self.keychainService, kSecAttrAccount as String:name]
    }
    static func secret(_ name: String) -> String? {
        var q = query(name); q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func store(_ secret: String, _ name: String) -> Bool {
        let q = query(name), value = Data(secret.utf8)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String:value] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = q; add[kSecValueData as String] = value; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

// Dedicated executable: isolated preferences, Keychain service and temporary data.
import Foundation
import MultipeerConnectivity

@main struct CameraGroupRegression {
    static func require(_ value: @autoclosure () -> Bool, _ text: String) {
        guard value() else { fatalError("FAIL: " + text) }; print("PASS: " + text)
    }
    static func main() throws {
        let d = UserDefaults.standard
        let keys = d.dictionaryRepresentation().keys.filter { $0.hasPrefix("WJ") }
        for key in keys { d.removeObject(forKey:key) }
        PeerDiscoveryManager.testKeychainService = "MTJudge.GroupRegression." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MTJudge-group-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        ReceivedVideoManager.testDirectory = root
        let files = ["keep.MOV","keep.MOV.tags.json","keep.MOV.drawing.json","keep.MOV.wj.json"]
        for file in files { try Data(("sentinel:"+file).utf8).write(to:root.appendingPathComponent(file)) }
        d.set("My camera",forKey:"WJCameraName"); d.set(["tag1"],forKey:"SelectedTags"); d.set(30,forKey:"WJDuration")
        require(PeerDiscoveryManager.serviceNamePrefix("カメラグループ🎥🎥🎥",bytes:15).utf8.count <= 15,"Japanese/emoji Bonjour name stays within byte limit")
        let discovery = PeerDiscoveryManager(), group = CameraGroupManager(discovery:PeerDiscoveryManager())
        group.canChangeSettings = { true }
        require(group.createGroup("A"),"create main group without URL entry")
        let id = group.groupID, generation = d.string(forKey:"WJConnectionGeneration")
        require(UUID(uuidString:id) != nil && id.count == 36,"full unique group ID retained")
        require(group.automatic && group.role == "MAIN","main role and automatic mode persisted")
        require(d.bool(forKey:"WJMode") && d.bool(forKey:"WJReceive") && d.bool(forKey:"WJTransfer"),"main simultaneously records, receives and forwards")
        let restored = CameraGroupManager(discovery:discovery)
        require(restored.groupID == id && restored.role == "MAIN","new manager restores group and role from shared settings")
        group.canChangeSettings = { false }
        require(!group.reset() && group.groupID == id,"busy reset rejected without modifying group")
        require(!group.createGroup("D") && group.groupID == id,"busy group change rejected")
        group.canChangeSettings = { true }
        d.set("http://old/#token",forKey:"WJSubCameraURL"); d.set("stale",forKey:"WJPeerID")
        require(group.createGroup("D"),"group can be replaced")
        require(group.groupID != id && d.string(forKey:"WJConnectionGeneration") != generation,"replacement invalidates old group and queue generation")
        require(d.string(forKey:"WJSubCameraURL") == nil && d.string(forKey:"WJPeerID") == nil,"old communication targets cleared")
        let member = UUID().uuidString
        d.set([["id":member,"role":"CAMERA_1","name":"Camera"]],forKey:"WJGroupMembers")
        require(group.removeMember(member) && group.members.isEmpty,"explicit member removal frees occupied role")
        require(group.useManual() && !group.automatic,"manual mode explicitly disables automatic membership")
        require(group.reset(),"idle communication reset succeeds")
        require(group.groupID.isEmpty && group.role.isEmpty && !d.bool(forKey:"WJReceive") && !d.bool(forKey:"WJWeb"),"reset clears membership and communication toggles")
        require(d.string(forKey:"WJCameraName") == "My camera" && d.integer(forKey:"WJDuration") == 30 && d.stringArray(forKey:"SelectedTags") == ["tag1"],"reset preserves camera preferences and user tags")
        for file in files {
            let data = try Data(contentsOf:root.appendingPathComponent(file))
            require(data == Data(("sentinel:"+file).utf8),"reset preserves file bytes: " + file)
        }
        discovery.clearRegistrationsAndCredentials()
        print("ALL GROUP CONFIGURATION TESTS PASSED; artifacts: " + root.path)
    }
}

from pathlib import Path
import hashlib,plistlib
p=Path('MTJudge.xcodeproj/project.pbxproj');s=p.read_text()
def uid(x):return hashlib.sha1(('watch'+x).encode()).hexdigest()[:24].upper()
def add(section, text):
 global s
 marker='/* End '+section+' section */'
 if marker not in s:s=s.replace('/* Begin PBXFileReference section */','/* Begin '+section+' section */\n'+text+'\n'+marker+'\n/* Begin PBXFileReference section */')
 else:s=s.replace(marker,text+'\n'+marker)
target=uid('target');src=uid('source');prod=uid('product');phase=uid('sources');fw=uid('frameworks');res=uid('resources');configs=uid('configs');copy=uid('copy');dep=uid('dependency');proxy=uid('proxy')
if target not in s:
 add('PBXFileReference', f'{src} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MTJudgeWatch/MTJudgeWatchApp.swift; sourceTree = SOURCE_ROOT; }};\n{prod} = {{isa = PBXFileReference; explicitFileType = wrapper.application; path = MTJudgeWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
 add('PBXBuildFile',f'{uid("sourcebuild")} = {{isa = PBXBuildFile; fileRef = {src}; }};\n{uid("embedbuild")} = {{isa = PBXBuildFile; fileRef = {prod}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')
 add('PBXSourcesBuildPhase',f'{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("sourcebuild")},); runOnlyForDeploymentPostprocessing = 0; }};')
 for section,ident in [('PBXFrameworksBuildPhase',fw),('PBXResourcesBuildPhase',res)]:add(section,f'{ident} = {{isa = {section}; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};')
 add('PBXNativeTarget',f'{target} = {{isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = ({phase},{fw},{res},); buildRules = (); dependencies = (); name = MTJudgeWatch; productName = MTJudgeWatch; productReference = {prod}; productType = "com.apple.product-type.application"; }};')
 for config in ['Debug','Release']:
  settings='CODE_SIGN_IDENTITY = "Apple Development"; SDKROOT = watchos; SUPPORTED_PLATFORMS = "watchos watchsimulator"; WATCHOS_DEPLOYMENT_TARGET = 10.0; TARGETED_DEVICE_FAMILY = 4; SWIFT_VERSION = 5.0; PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = ganasonic.tool.app.MTJudge.watchkitapp; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = UM9N74S758; INFOPLIST_FILE = MTJudgeWatch/Info.plist; GENERATE_INFOPLIST_FILE = NO; SWIFT_EMIT_LOC_STRINGS = YES;'
  add('XCBuildConfiguration',f'{uid(config)} = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {config}; }};')
 add('XCConfigurationList',f'{configs} = {{isa = XCConfigurationList; buildConfigurations = ({uid("Debug")},{uid("Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
 # Modern single-target watch app embedded in companion iOS app.
 add('PBXCopyFilesBuildPhase',f'{copy} = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = ({uid("embedbuild")},); name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0; }};')
 add('PBXContainerItemProxy',f'{proxy} = {{isa = PBXContainerItemProxy; containerPortal = 0E359826226550C80093671C; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = MTJudgeWatch; }};')
 add('PBXTargetDependency',f'{dep} = {{isa = PBXTargetDependency; target = {target}; targetProxy = {proxy}; }};')
 start=s.index('0E35982D226550C80093671C /* MTJudge */ = {',s.index('/* Begin PBXNativeTarget section */'))
 idx=s.index('buildPhases = (',start)+len('buildPhases = (');s=s[:idx]+copy+','+s[idx:]
 idx=s.index('dependencies = (',start)+len('dependencies = (');s=s[:idx]+dep+','+s[idx:]
 idx=s.index('targets = (')+len('targets = (');s=s[:idx]+target+','+s[idx:]
 idx=s.index('children = (',s.index('/* Begin PBXGroup section */'))+len('children = (');s=s[:idx]+src+','+prod+','+s[idx:]
 p.write_text(s)
info={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName':'MTJudgeWatch','CFBundleDisplayName':'MTJudge Remote','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'3.93','CFBundleVersion':'20','WKApplication':True,'WKCompanionAppBundleIdentifier':'ganasonic.tool.app.MTJudge','WKRunsIndependentlyOfCompanionApp':False}
Path('MTJudgeWatch/Info.plist').write_bytes(plistlib.dumps(info))

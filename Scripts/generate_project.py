#!/usr/bin/env python3
"""Generate a dependency-free Xcode project with an embedded keyboard extension."""
import argparse
import hashlib
import json
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--shared-container", action="store_true", help="Enable App Groups for a paid Apple team")
options = parser.parse_args()

class Ref(str):
    pass

objects = {}
def identifier(label):
    return Ref(hashlib.sha1(label.encode()).hexdigest()[:24].upper())

def add(label, isa, **values):
    key = identifier(label)
    objects[key] = {"isa": isa, **values}
    return key

def encode(value, indent=0):
    space = "\t" * indent
    if isinstance(value, Ref): return str(value)
    if isinstance(value, dict):
        rows = [f'{space}\t{encode(k)} = {encode(v, indent + 1)};' for k, v in value.items()]
        return "{\n" + "\n".join(rows) + "\n" + space + "}"
    if isinstance(value, list): return "(\n" + "\n".join(f'{space}\t{encode(v, indent + 1)},' for v in value) + "\n" + space + ")"
    if isinstance(value, int): return str(value)
    return json.dumps(str(value), ensure_ascii=False)

def write_plist(name, value):
    path = ROOT / "Configuration" / name
    path.parent.mkdir(exist_ok=True)
    path.write_bytes(plistlib.dumps(value, sort_keys=False))

common_info = {
    "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)", "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "ITSAppUsesNonExemptEncryption": False
}
write_plist("App-Info.plist", {
    **common_info, "CFBundleDisplayName": "WianTribe Keyboard", "CFBundlePackageType": "APPL",
    "LSRequiresIPhoneOS": True, "UILaunchScreen": {},
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "NSMicrophoneUsageDescription": "Record your voice only when you start recording in the Voice editor.",
    "NSSpeechRecognitionUsageDescription": "Turn the voice you choose to record into text you can review and copy."
})
write_plist("Keyboard-Info.plist", {
    **common_info, "CFBundleDisplayName": "WianTribe Keyboard", "CFBundlePackageType": "XPC!",
    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.keyboard-service",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).KeyboardViewController",
                    "NSExtensionAttributes": {"IsASCIICapable": True, "PrimaryLanguage": "mul",
                                               "RequestsOpenAccess": True, "PrefersRightToLeft": False}}
})
write_plist("Stickers-Info.plist", {
    # Xcode copies Apple's Messages stub executable into sticker packs, so the key is required.
    **common_info, "CFBundleDisplayName": "WianTribe Stickers", "CFBundlePackageType": "XPC!",
    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.message-payload-provider",
                    "NSExtensionPrincipalClass": "StickerBrowserViewController"}
})
write_plist("Share-Info.plist", {
    **common_info, "CFBundleDisplayName": "Save to WianTribe", "CFBundlePackageType": "XPC!",
    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": {"NSExtensionActivationRule": {"NSExtensionActivationSupportsText": True,
                                                                            "NSExtensionActivationSupportsWebURLWithMaxCount": 1}}}
})
write_plist("Sideload.entitlements", {})
write_plist("Shared.entitlements", {"com.apple.security.application-groups": ["group.com.wiantribe.keyboard"]})
write_plist("AppShared.entitlements", {"com.apple.security.application-groups": ["group.com.wiantribe.keyboard"], "com.apple.developer.applesignin": ["Default"]})
write_plist("PrivacyInfo.xcprivacy", {
    "NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [
        {"NSPrivacyCollectedDataType": kind, "NSPrivacyCollectedDataTypeLinked": True,
         "NSPrivacyCollectedDataTypeTracking": False,
         "NSPrivacyCollectedDataTypePurposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]}
        for kind in ["NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeProductInteraction"]
    ],
    "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                                   "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "1C8F.1"]}]
})

project_id = identifier("project")
app_id = identifier("target-app")
keyboard_id = identifier("target-keyboard")
stickers_id = identifier("target-stickers")
share_id = identifier("target-share")
sticker_catalog = "Sources/Stickers/Stickers.xcstickers"
all_files = sorted({str(p.relative_to(ROOT)) for p in (ROOT / "Sources").rglob("*.swift")})
resources = ["Sources/Core/Resources/Languages.json", "Configuration/PrivacyInfo.xcprivacy"]
# Dictionaries and emoji data are only needed by the keyboard, so the app stays small.
keyboard_data = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Sources/Core/Resources").glob("*") if p.is_file() and p.name != "Languages.json")
media = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Sources/Keyboard/Media").glob("*") if p.is_file())
all_paths = all_files + resources + keyboard_data + media + ["Sources/App/Assets.xcassets", "Configuration/App-Info.plist", "Configuration/Keyboard-Info.plist", "Configuration/Stickers-Info.plist", "Configuration/Share-Info.plist", sticker_catalog, "Sources/App/Localizable.xcstrings", "Sources/App/InfoPlist.xcstrings", "Configuration/Sideload.entitlements", "Configuration/Shared.entitlements", "Configuration/AppShared.entitlements"]
refs = {}
for path in all_paths:
    suffix = pathlib.Path(path).suffix
    filetype = {".swift": "sourcecode.swift", ".json": "text.json", ".txt": "text", ".png": "image.png", ".gif": "image.gif", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements", ".xcprivacy": "text.xml", ".xcassets": "folder.assetcatalog", ".xcstickers": "folder.stickers", ".xcstrings": "text.json.xcstrings"}[suffix]
    refs[path] = add("file-" + path, "PBXFileReference", lastKnownFileType=filetype, path=path, sourceTree="<group>")
app_product = add("product-app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="WianTribeKeyboard.app", sourceTree="BUILT_PRODUCTS_DIR")
keyboard_product = add("product-keyboard", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0, path="WianTribeKeyboardExtension.appex", sourceTree="BUILT_PRODUCTS_DIR")
stickers_product = add("product-stickers", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0, path="WianTribeStickers.appex", sourceTree="BUILT_PRODUCTS_DIR")
share_product = add("product-share", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0, path="WianTribeShare.appex", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[app_product, keyboard_product, stickers_product, share_product], name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=list(refs.values()) + [products], sourceTree="<group>")

def phase(label, isa, paths):
    files = [add(label + "-" + path, "PBXBuildFile", fileRef=refs[path]) for path in paths]
    return add(label, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)

app_sources = phase("app-sources", "PBXSourcesBuildPhase", [p for p in all_files if not p.startswith(("Sources/Keyboard/", "Sources/Share/"))])
keyboard_sources = phase("keyboard-sources", "PBXSourcesBuildPhase", [p for p in all_files if not p.startswith(("Sources/App/", "Sources/Share/"))])
# The Share extension only needs the shared model and storage.
share_sources = phase("share-sources", "PBXSourcesBuildPhase", [p for p in all_files if p.startswith(("Sources/Core/", "Sources/Share/")) or p == "Sources/Shared/KeyboardStore.swift"])
share_resources = phase("share-resources", "PBXResourcesBuildPhase", resources)
share_frameworks = phase("share-frameworks", "PBXFrameworksBuildPhase", [])
app_resources = phase("app-resources", "PBXResourcesBuildPhase", resources + ["Sources/App/Assets.xcassets", "Sources/App/Localizable.xcstrings", "Sources/App/InfoPlist.xcstrings"])
keyboard_resources = phase("keyboard-resources", "PBXResourcesBuildPhase", resources + keyboard_data + media)
app_frameworks = phase("app-frameworks", "PBXFrameworksBuildPhase", [])
keyboard_frameworks = phase("keyboard-frameworks", "PBXFrameworksBuildPhase", [])
stickers_resources = phase("stickers-resources", "PBXResourcesBuildPhase", [sticker_catalog])
embed_file = add("embed-file", "PBXBuildFile", fileRef=keyboard_product, settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
embed_stickers = add("embed-stickers-file", "PBXBuildFile", fileRef=stickers_product, settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
embed_share = add("embed-share-file", "PBXBuildFile", fileRef=share_product, settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
embed = add("embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed_file, embed_stickers, embed_share], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
proxy = add("dependency-proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=keyboard_id, remoteInfo="WianTribeKeyboardExtension")
dependency = add("dependency", "PBXTargetDependency", target=keyboard_id, targetProxy=proxy)
stickers_proxy = add("dependency-stickers-proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=stickers_id, remoteInfo="WianTribeStickers")
stickers_dependency = add("dependency-stickers", "PBXTargetDependency", target=stickers_id, targetProxy=stickers_proxy)
share_proxy = add("dependency-share-proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=share_id, remoteInfo="WianTribeShare")
share_dependency = add("dependency-share", "PBXTargetDependency", target=share_id, targetProxy=share_proxy)

project_settings = {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
                    "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted",
                    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17"}

def configurations(label, settings):
    configs = []
    for name in ["Debug", "Release"]:
        build = {**settings, "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
                 "SWIFT_COMPILATION_MODE": "singlefile" if name == "Debug" else "wholemodule",
                 "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym"}
        if name == "Debug": build.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES"})
        configs.append(add(label + "-" + name, "XCBuildConfiguration", buildSettings=build, name=name))
    return add(label + "-config-list", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_configs = configurations("project", project_settings)
common_target = {"CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_ENTITLEMENTS": "Configuration/Shared.entitlements" if options.shared_container else "Configuration/Sideload.entitlements",
                 "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.2.0", "TARGETED_DEVICE_FAMILY": "1,2",
                 "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "GENERATE_INFOPLIST_FILE": "NO",
                 "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"], "PRODUCT_NAME": "$(TARGET_NAME)"}
app_configs = configurations("app", {**common_target, "CODE_SIGN_ENTITLEMENTS": "Configuration/AppShared.entitlements" if options.shared_container else "Configuration/Sideload.entitlements", "PRODUCT_BUNDLE_IDENTIFIER": "com.wiantribe.keyboard", "INFOPLIST_FILE": "Configuration/App-Info.plist",
                                       "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor"})
keyboard_configs = configurations("keyboard", {**common_target, "PRODUCT_BUNDLE_IDENTIFIER": "com.wiantribe.keyboard.extension", "INFOPLIST_FILE": "Configuration/Keyboard-Info.plist",
                                                "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                                                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
stickers_configs = configurations("stickers", {**common_target, "PRODUCT_BUNDLE_IDENTIFIER": "com.wiantribe.keyboard.stickers", "INFOPLIST_FILE": "Configuration/Stickers-Info.plist",
                                                "ASSETCATALOG_COMPILER_APPICON_NAME": "iMessage App Icon", "SKIP_INSTALL": "YES", "PRODUCT_NAME": "WianTribeStickers",
                                                "CODE_SIGN_ENTITLEMENTS": "Configuration/Sideload.entitlements"})  # stickers need no App Group
share_configs = configurations("share", {**common_target, "PRODUCT_BUNDLE_IDENTIFIER": "com.wiantribe.keyboard.share", "INFOPLIST_FILE": "Configuration/Share-Info.plist",
                                          "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES", "PRODUCT_NAME": "WianTribeShare",
                                          "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
add("target-app", "PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=[app_sources, app_frameworks, app_resources, embed], buildRules=[], dependencies=[dependency, stickers_dependency, share_dependency], name="WianTribeKeyboard", productName="WianTribeKeyboard", productReference=app_product, productType="com.apple.product-type.application")
add("target-keyboard", "PBXNativeTarget", buildConfigurationList=keyboard_configs, buildPhases=[keyboard_sources, keyboard_frameworks, keyboard_resources], buildRules=[], dependencies=[], name="WianTribeKeyboardExtension", productName="WianTribeKeyboardExtension", productReference=keyboard_product, productType="com.apple.product-type.app-extension")
add("target-stickers", "PBXNativeTarget", buildConfigurationList=stickers_configs, buildPhases=[stickers_resources], buildRules=[], dependencies=[], name="WianTribeStickers", productName="WianTribeStickers", productReference=stickers_product, productType="com.apple.product-type.app-extension.messages-sticker-pack")
add("target-share", "PBXNativeTarget", buildConfigurationList=share_configs, buildPhases=[share_sources, share_frameworks, share_resources], buildRules=[], dependencies=[], name="WianTribeShare", productName="WianTribeShare", productReference=share_product, productType="com.apple.product-type.app-extension")
add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "TargetAttributes": {app_id: {"CreatedOnToolsVersion": "16.0"}, keyboard_id: {"CreatedOnToolsVersion": "16.0"}, stickers_id: {"CreatedOnToolsVersion": "16.0"}, share_id: {"CreatedOnToolsVersion": "16.0"}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base", "es", "fr", "pt", "de", "ar"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_id, keyboard_id, stickers_id, share_id])

project = ROOT / "WianTribeKeyboard.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="WianTribeKeyboard.app" BlueprintName="WianTribeKeyboard" ReferencedContainer="container:WianTribeKeyboard.xcodeproj"/>'
(schemes / "WianTribeKeyboard.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated app and keyboard project (" + ("shared container" if options.shared_container else "sideload compatible") + ")")

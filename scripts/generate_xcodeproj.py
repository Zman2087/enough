#!/usr/bin/env python3
"""Write Enough.xcodeproj and the neutral app icons.

Run from the repository root: python3 scripts/generate_xcodeproj.py
"""

import hashlib
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def oid(name):
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()


class Ref:
    def __init__(self, id_, comment):
        self.id = id_
        self.comment = comment


class Project:
    def __init__(self):
        self.objects = {}

    def add(self, comment, body, name):
        id_ = oid(name)
        if id_ in self.objects:
            raise SystemExit(f"duplicate id for {name}")
        self.objects[id_] = (comment, body)
        return Ref(id_, comment)


def quote(value):
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


# Characters Xcode accepts in an unquoted pbxproj string. `+` is not one of them:
# `CLANG_CXX_LANGUAGE_STANDARD = gnu++20` will not open in Xcode 27.
UNQUOTED_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")


def emit_string(value):
    if len(value) == 24 and all(c in "0123456789ABCDEF" for c in value):
        return value
    if value and all(c in UNQUOTED_CHARS for c in value):
        return value
    return quote(value)


def emit(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, Ref):
        return f"{value.id} /* {value.comment} */"
    if isinstance(value, bool):
        return "YES" if value else "NO"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return emit_string(value)
    if isinstance(value, list):
        if not value:
            return "()"
        lines = [f"{pad}\t{emit(item, indent + 1)}," for item in value]
        return "(\n" + "\n".join(lines) + f"\n{pad})"
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = [f"{pad}\t{key} = {emit(item, indent + 1)};" for key, item in value.items()]
        return "{\n" + "\n".join(lines) + f"\n{pad}}}"
    raise TypeError(type(value))


def write_png(path, size):
    bg = (0x24, 0x33, 0x30, 255)
    fg = (0xE6, 0xE1, 0xD6, 255)
    margin = int(size * 0.27)
    bar_h = max(2, int(size * 0.085))
    y0 = (size - bar_h) // 2
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            color = fg if margin <= x < size - margin and y0 <= y < y0 + bar_h else bg
            raw.extend(color)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(blob)


def file_type(path):
    ext = os.path.splitext(path)[1]
    return {
        ".swift": "sourcecode.swift",
        ".json": "text.json",
        ".js": "sourcecode.javascript",
        ".css": "text.css",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".xcprivacy": "text.xml",
        ".xcassets": "folder.assetcatalog",
        ".png": "image.png",
    }[ext]


def main():
    os.chdir(ROOT)
    write_png("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png", 1024)
    sys.path.insert(0, os.path.dirname(__file__))
    from launch_mark import write_assets
    write_assets(ROOT)
    for size in (48, 96, 128, 256, 512):
        write_png(f"Extensions/Safari/Resources/icon-{size}.png", size)

    p = Project()
    files = {}

    def add_file(path):
        ref = p.add(os.path.basename(path), {
            "isa": "PBXFileReference",
            "lastKnownFileType": file_type(path),
            "path": os.path.basename(path),
            "sourceTree": "<group>",
        }, f"file:{path}")
        files[path] = ref
        if not os.path.exists(path):
            raise SystemExit(f"missing {path}")
        return ref

    engine_swift = [
        "Sources/FilterEngine/DayBoundary.swift",
        "Sources/FilterEngine/EngineResources.swift",
        "Sources/FilterEngine/EnoughConstants.swift",
        "Sources/FilterEngine/EnoughSettings.swift",
        "Sources/FilterEngine/Navigation.swift",
        "Sources/FilterEngine/Permalink.swift",
        "Sources/FilterEngine/SelectorConfig.swift",
        "Sources/FilterEngine/SettingsLock.swift",
        "Sources/FilterEngine/Storage.swift",
        "Sources/FilterEngine/UsageStore.swift",
    ]
    engine_resources = [
        "Sources/FilterEngine/Resources/filter.js",
        "Sources/FilterEngine/Resources/hide.css",
        "Sources/FilterEngine/Resources/selectors.json",
    ]
    app_swift = [
        "App/ContentView.swift",
        "App/FeedModel.swift",
        "App/FeedWebView.swift",
        "App/PINLock.swift",
        "App/SettingsView.swift",
    ]
    app_meta = [
        "App/Enough.entitlements",
        "App/Info.plist",
        "App/PrivacyInfo.xcprivacy",
        "App/Assets.xcassets",
    ]
    test_swift = [
        "Tests/FilterEngineTests/DayBoundaryTests.swift",
        "Tests/FilterEngineTests/FixturePaths.swift",
        "Tests/FilterEngineTests/PolicyTests.swift",
        "Tests/FilterEngineTests/SelectorConfigTests.swift",
        "Tests/FilterEngineTests/SettingsLockTests.swift",
        "Tests/FilterEngineTests/UsageStoreTests.swift",
    ]
    safari_swift = ["Extensions/Safari/SafariWebExtensionHandler.swift"]
    safari_meta = [
        "Extensions/Safari/EnoughSafari.entitlements",
        "Extensions/Safari/Info.plist",
    ]
    safari_resources = [
        "Extensions/Safari/Resources/content.js",
        "Extensions/Safari/Resources/manifest.json",
        "Extensions/Safari/Resources/icon-48.png",
        "Extensions/Safari/Resources/icon-96.png",
        "Extensions/Safari/Resources/icon-128.png",
        "Extensions/Safari/Resources/icon-256.png",
        "Extensions/Safari/Resources/icon-512.png",
    ]
    shield_swift = ["Extensions/Shield/ShieldConfigurationExtension.swift"]
    shield_meta = [
        "Extensions/Shield/EnoughShield.entitlements",
        "Extensions/Shield/Info.plist",
    ]
    for path in (
        engine_swift + engine_resources + app_swift + app_meta + test_swift
        + safari_swift + safari_meta + safari_resources + shield_swift + shield_meta
        + ["Tests/FilterEngineTests/Fixtures/routes.json"]
    ):
        add_file(path)

    def group(name, children, key, path=None):
        body = {
            "isa": "PBXGroup",
            "children": children,
            "sourceTree": "<group>",
        }
        if path:
            body["path"] = path
        else:
            body["name"] = name
        return p.add(name, body, key)

    engine_res_group = group("Resources", [files[path] for path in engine_resources], "group:engine-resources", "Resources")
    engine_group = group(
        "FilterEngine",
        [files[path] for path in engine_swift] + [engine_res_group],
        "group:engine",
        "FilterEngine",
    )
    sources_group = group("Sources", [engine_group], "group:sources", "Sources")
    app_group = group("App", [files[path] for path in app_swift + app_meta], "group:app", "App")
    fixtures_group = group(
        "Fixtures",
        [files["Tests/FilterEngineTests/Fixtures/routes.json"]],
        "group:fixtures",
        "Fixtures",
    )
    tests_group = group(
        "FilterEngineTests",
        [files[path] for path in test_swift] + [fixtures_group],
        "group:tests-inner",
        "FilterEngineTests",
    )
    tests_root = group("Tests", [tests_group], "group:tests", "Tests")
    safari_res_group = group(
        "Resources",
        [files[path] for path in safari_resources],
        "group:safari-resources",
        "Resources",
    )
    safari_group = group(
        "Safari",
        [files[path] for path in safari_swift + safari_meta] + [safari_res_group],
        "group:safari",
        "Safari",
    )
    shield_group = group("Shield", [files[path] for path in shield_swift + shield_meta], "group:shield", "Shield")
    extensions_group = group("Extensions", [safari_group, shield_group], "group:extensions", "Extensions")

    def sdk(name):
        return p.add(name, {
            "isa": "PBXFileReference",
            "lastKnownFileType": "wrapper.framework",
            "name": name,
            "path": f"System/Library/Frameworks/{name}",
            "sourceTree": "SDKROOT",
        }, f"sdk:{name}")

    webkit = sdk("WebKit.framework")
    safari_services = sdk("SafariServices.framework")
    managed_settings = sdk("ManagedSettings.framework")
    managed_settings_ui = sdk("ManagedSettingsUI.framework")
    frameworks_group = group(
        "Frameworks",
        [webkit, safari_services, managed_settings, managed_settings_ui],
        "group:frameworks",
    )

    def product(filename, kind):
        return p.add(filename, {
            "isa": "PBXFileReference",
            "explicitFileType": kind,
            "includeInIndex": 0,
            "path": filename,
            "sourceTree": "BUILT_PRODUCTS_DIR",
        }, f"product:{filename}")

    framework_product = product("FilterEngine.framework", "wrapper.framework")
    app_product = product("Enough.app", "wrapper.application")
    test_product = product("FilterEngineTests.xctest", "wrapper.cfbundle")
    safari_product = product("EnoughSafariExtension.appex", "wrapper.app-extension")
    shield_product = product("EnoughShieldExtension.appex", "wrapper.app-extension")
    products_group = group(
        "Products",
        [app_product, framework_product, test_product, safari_product, shield_product],
        "group:products",
    )
    root_group = p.add("Enough", {
        "isa": "PBXGroup",
        "children": [app_group, sources_group, tests_root, extensions_group, frameworks_group, products_group],
        "sourceTree": "<group>",
    }, "group:root")

    def build_ref(file_ref, key, attributes=None):
        body = {"isa": "PBXBuildFile", "fileRef": file_ref}
        if attributes:
            body["settings"] = {"ATTRIBUTES": attributes}
        return p.add(file_ref.comment, body, key)

    def phase(isa, comment, key, file_refs, extra=None):
        body = {
            "isa": isa,
            "buildActionMask": 2147483647,
            "files": file_refs,
            "runOnlyForDeploymentPostprocessing": 0,
        }
        if extra:
            body.update(extra)
        return p.add(comment, body, key)

    framework_sources_phase = phase(
        "PBXSourcesBuildPhase", "Sources", "sources:FilterEngine",
        [build_ref(files[path], f"build:FilterEngine:{path}") for path in engine_swift],
    )
    framework_resources_phase = phase(
        "PBXResourcesBuildPhase", "Resources", "resources:FilterEngine",
        [build_ref(files[path], f"build:FilterEngine-res:{path}") for path in engine_resources],
    )
    app_sources_phase = phase(
        "PBXSourcesBuildPhase", "Sources", "sources:Enough",
        [build_ref(files[path], f"build:Enough:{path}") for path in app_swift],
    )
    app_frameworks_phase = phase(
        "PBXFrameworksBuildPhase", "Frameworks", "frameworks:Enough",
        [
            build_ref(framework_product, "link:Enough:FilterEngine"),
            build_ref(webkit, "link:Enough:WebKit"),
        ],
    )
    app_resources_phase = phase(
        "PBXResourcesBuildPhase", "Resources", "resources:Enough",
        [
            build_ref(files["App/Assets.xcassets"], "build:Enough:assets"),
            build_ref(files["App/PrivacyInfo.xcprivacy"], "build:Enough:privacy"),
        ],
    )
    embed_frameworks = phase(
        "PBXCopyFilesBuildPhase", "Embed Frameworks", "embed:Enough:frameworks",
        [build_ref(framework_product, "embed:Enough:FilterEngine", ["CodeSignOnCopy", "RemoveHeadersOnCopy"])],
        {"dstPath": "", "dstSubfolderSpec": 10, "name": "Embed Frameworks"},
    )
    embed_extensions = phase(
        "PBXCopyFilesBuildPhase", "Embed Foundation Extensions", "embed:Enough:extensions",
        [
            build_ref(safari_product, "embed:Enough:Safari", ["CodeSignOnCopy", "RemoveHeadersOnCopy"]),
            build_ref(shield_product, "embed:Enough:Shield", ["CodeSignOnCopy", "RemoveHeadersOnCopy"]),
        ],
        {"dstPath": "", "dstSubfolderSpec": 13, "name": "Embed Foundation Extensions"},
    )
    test_sources_phase = phase(
        "PBXSourcesBuildPhase", "Sources", "sources:Tests",
        [build_ref(files[path], f"build:Tests:{path}") for path in test_swift],
    )
    test_frameworks_phase = phase(
        "PBXFrameworksBuildPhase", "Frameworks", "frameworks:Tests",
        [build_ref(framework_product, "link:Tests:FilterEngine")],
    )
    safari_sources_phase = phase(
        "PBXSourcesBuildPhase", "Sources", "sources:Safari",
        [build_ref(files[path], f"build:Safari:{path}") for path in safari_swift],
    )
    safari_frameworks_phase = phase(
        "PBXFrameworksBuildPhase", "Frameworks", "frameworks:Safari",
        [build_ref(safari_services, "link:Safari:SafariServices")],
    )
    safari_resources_phase = phase(
        "PBXResourcesBuildPhase", "Resources", "resources:Safari",
        [build_ref(files[path], f"build:Safari-res:{path}") for path in safari_resources + engine_resources],
    )
    shield_sources_phase = phase(
        "PBXSourcesBuildPhase", "Sources", "sources:Shield",
        [build_ref(files[path], f"build:Shield:{path}") for path in shield_swift],
    )
    shield_frameworks_phase = phase(
        "PBXFrameworksBuildPhase", "Frameworks", "frameworks:Shield",
        [
            build_ref(managed_settings, "link:Shield:ManagedSettings"),
            build_ref(managed_settings_ui, "link:Shield:ManagedSettingsUI"),
        ],
    )

    project_id = oid("project")
    project_ref = Ref(project_id, "Project object")

    def dependency(owner, target_ref, target_name):
        proxy = p.add("PBXContainerItemProxy", {
            "isa": "PBXContainerItemProxy",
            "containerPortal": project_ref,
            "proxyType": 1,
            "remoteGlobalIDString": target_ref.id,
            "remoteInfo": target_name,
        }, f"proxy:{owner}:{target_name}")
        return p.add("PBXTargetDependency", {
            "isa": "PBXTargetDependency",
            "target": target_ref,
            "targetProxy": proxy,
        }, f"dep:{owner}:{target_name}")

    def configs(settings, key):
        debug = p.add("Debug", {
            "isa": "XCBuildConfiguration",
            "buildSettings": settings,
            "name": "Debug",
        }, f"config:{key}:Debug")
        release = p.add("Release", {
            "isa": "XCBuildConfiguration",
            "buildSettings": settings,
            "name": "Release",
        }, f"config:{key}:Release")
        # Same target settings as Debug. PERSONAL_BUILD comes from the project
        # Personal configuration and is not repeated here, so Release cannot inherit it.
        personal = p.add("Personal", {
            "isa": "XCBuildConfiguration",
            "buildSettings": settings,
            "name": "Personal",
        }, f"config:{key}:Personal")
        return p.add("Build configuration list", {
            "isa": "XCConfigurationList",
            "buildConfigurations": [debug, release, personal],
            "defaultConfigurationIsVisible": 0,
            "defaultConfigurationName": "Release",
        }, f"configs:{key}")

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "MARKETING_VERSION": "0.1.0",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    debug_settings = dict(common)
    debug_settings.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_COMPILATION_MODE": "incremental",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })
    release_settings = dict(common)
    release_settings.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    })
    project_debug = p.add("Debug", {
        "isa": "XCBuildConfiguration",
        "buildSettings": debug_settings,
        "name": "Debug",
    }, "config:project:Debug")
    project_release = p.add("Release", {
        "isa": "XCBuildConfiguration",
        "buildSettings": release_settings,
        "name": "Release",
    }, "config:project:Release")
    personal_settings = dict(debug_settings)
    personal_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG PERSONAL_BUILD"
    project_personal = p.add("Personal", {
        "isa": "XCBuildConfiguration",
        "buildSettings": personal_settings,
        "name": "Personal",
    }, "config:project:Personal")
    project_configs = p.add("Build configuration list", {
        "isa": "XCConfigurationList",
        "buildConfigurations": [project_debug, project_release, project_personal],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }, "configs:project")

    runpath_app = "$(inherited) @executable_path/Frameworks"
    runpath_framework = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"
    runpath_extension = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"

    framework_settings = {
        "CODE_SIGN_STYLE": "Automatic",
        "DEFINES_MODULE": "YES",
        "DYLIB_COMPATIBILITY_VERSION": "1",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "LD_RUNPATH_SEARCH_PATHS": runpath_framework,
        "PRODUCT_BUNDLE_IDENTIFIER": "app.enough.FilterEngine",
        "PRODUCT_MODULE_NAME": "FilterEngine",
        "PRODUCT_NAME": "FilterEngine",
        "SKIP_INSTALL": "YES",
    }
    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "App/Enough.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "App/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": runpath_app,
        "PRODUCT_BUNDLE_IDENTIFIER": "app.enough.ios",
        "PRODUCT_NAME": "Enough",
    }
    test_settings = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": runpath_framework,
        "PRODUCT_BUNDLE_IDENTIFIER": "app.enough.ios.tests",
        "PRODUCT_NAME": "FilterEngineTests",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Enough.app/Enough",
    }
    safari_settings = {
        "CODE_SIGN_ENTITLEMENTS": "Extensions/Safari/EnoughSafari.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Extensions/Safari/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": runpath_extension,
        "PRODUCT_BUNDLE_IDENTIFIER": "app.enough.ios.safari",
        "PRODUCT_NAME": "EnoughSafariExtension",
        "SKIP_INSTALL": "YES",
    }
    shield_settings = {
        "CODE_SIGN_ENTITLEMENTS": "Extensions/Shield/EnoughShield.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Extensions/Shield/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": runpath_extension,
        "PRODUCT_BUNDLE_IDENTIFIER": "app.enough.ios.shield",
        "PRODUCT_NAME": "EnoughShieldExtension",
        "SKIP_INSTALL": "YES",
    }

    framework_configs = configs(framework_settings, "FilterEngine")
    app_configs = configs(app_settings, "Enough")
    test_configs = configs(test_settings, "Tests")
    safari_configs = configs(safari_settings, "Safari")
    shield_configs = configs(shield_settings, "Shield")

    def target(name, product_type, product_ref, phases, key):
        # Placeholder dependencies filled after all targets exist.
        return p.add(name, {
            "isa": "PBXNativeTarget",
            "buildConfigurationList": None,
            "buildPhases": phases,
            "buildRules": [],
            "dependencies": [],
            "name": name,
            "productName": name,
            "productReference": product_ref,
            "productType": product_type,
        }, key)

    framework_target = target(
        "FilterEngine", "com.apple.product-type.framework", framework_product,
        [framework_sources_phase, framework_resources_phase], "target:FilterEngine",
    )
    app_target = target(
        "Enough", "com.apple.product-type.application", app_product,
        [app_sources_phase, app_frameworks_phase, app_resources_phase, embed_frameworks, embed_extensions],
        "target:Enough",
    )
    test_target = target(
        "FilterEngineTests", "com.apple.product-type.bundle.unit-test", test_product,
        [test_sources_phase, test_frameworks_phase], "target:Tests",
    )
    safari_target = target(
        "EnoughSafariExtension", "com.apple.product-type.app-extension", safari_product,
        [safari_sources_phase, safari_frameworks_phase, safari_resources_phase],
        "target:Safari",
    )
    shield_target = target(
        "EnoughShieldExtension", "com.apple.product-type.app-extension", shield_product,
        [shield_sources_phase, shield_frameworks_phase], "target:Shield",
    )

    # Fill configuration lists and dependencies now that target refs exist.
    bodies = {ref.id: p.objects[ref.id][1] for ref in (
        framework_target, app_target, test_target, safari_target, shield_target
    )}
    bodies[framework_target.id]["buildConfigurationList"] = framework_configs
    bodies[app_target.id]["buildConfigurationList"] = app_configs
    bodies[test_target.id]["buildConfigurationList"] = test_configs
    bodies[safari_target.id]["buildConfigurationList"] = safari_configs
    bodies[shield_target.id]["buildConfigurationList"] = shield_configs
    bodies[app_target.id]["dependencies"] = [
        dependency("Enough", framework_target, "FilterEngine"),
        dependency("Enough", safari_target, "EnoughSafariExtension"),
        dependency("Enough", shield_target, "EnoughShieldExtension"),
    ]
    bodies[test_target.id]["dependencies"] = [
        dependency("Tests", app_target, "Enough"),
        dependency("Tests", framework_target, "FilterEngine"),
    ]

    if project_id in p.objects:
        raise SystemExit("project id collided")
    p.objects[project_id] = ("Project object", {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": "YES",
            "LastSwiftUpdateCheck": "1600",
            "LastUpgradeCheck": "1600",
            "TargetAttributes": {
                framework_target.id: {"CreatedOnToolsVersion": "16.0"},
                app_target.id: {"CreatedOnToolsVersion": "16.0"},
                test_target.id: {"CreatedOnToolsVersion": "16.0"},
                safari_target.id: {"CreatedOnToolsVersion": "16.0"},
                shield_target.id: {"CreatedOnToolsVersion": "16.0"},
            },
        },
        "buildConfigurationList": project_configs,
        "compatibilityVersion": "Xcode 14.0",
        "developmentRegion": "en",
        "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base"],
        "mainGroup": root_group,
        "productRefGroup": products_group,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [app_target, framework_target, test_target, safari_target, shield_target],
    })

    lines = ["// !$*UTF8*$!", "{"]
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    by_isa = {}
    for id_, (comment, body) in p.objects.items():
        by_isa.setdefault(body["isa"], []).append((id_, comment, body))
    isa_order = [
        "PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase", "PBXFileReference",
        "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget", "PBXProject",
        "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "PBXTargetDependency",
        "XCBuildConfiguration", "XCConfigurationList",
    ]
    chunks = []
    for isa in isa_order:
        entries = sorted(by_isa.get(isa, []), key=lambda item: item[0])
        if not entries:
            continue
        chunks.append(f"\n/* Begin {isa} section */")
        for id_, comment, body in entries:
            chunks.append(f"\t\t{id_} /* {comment} */ = {emit(body, 2)};")
        chunks.append(f"/* End {isa} section */")
    lines.append("\n".join(chunks))
    lines.append("\t};")
    lines.append(f"\trootObject = {project_id} /* Project object */;")
    lines.append("}")
    text = "\n".join(lines) + "\n"
    # The empty-string appends above leave blank lines. Collapse the triple gaps a bit.
    text = text.replace("\n\n\n", "\n\n")
    project_dir = os.path.join(ROOT, "Enough.xcodeproj")
    os.makedirs(project_dir, exist_ok=True)
    with open(os.path.join(project_dir, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write(text)

    scheme_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    scheme = scheme_xml(app_target.id, test_target.id, framework_target.id, safari_target.id, shield_target.id)
    with open(os.path.join(scheme_dir, "Enough.xcscheme"), "w", encoding="utf-8") as handle:
        handle.write(scheme)
    personal_scheme = scheme_xml(
        app_target.id, test_target.id, framework_target.id, safari_target.id, shield_target.id,
        test="Personal", run="Personal", profile="Personal", analyze="Personal", archive="Personal",
    )
    with open(os.path.join(scheme_dir, "Enough Personal.xcscheme"), "w", encoding="utf-8") as handle:
        handle.write(personal_scheme)
    workspace = os.path.join(project_dir, "project.xcworkspace")
    os.makedirs(workspace, exist_ok=True)
    with open(os.path.join(workspace, "contents.xcworkspacedata"), "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<Workspace\n'
            '   version = "1.0">\n'
            '   <FileRef\n'
            '      location = "self:">\n'
            '   </FileRef>\n'
            '</Workspace>\n'
        )
    print(f"Wrote {len(p.objects)} objects")


def buildable(name, filename, target_id):
    return f"""         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{filename}"
            BlueprintName = "{name}"
            ReferencedContainer = "container:Enough.xcodeproj">
         </BuildableReference>"""


def entry(name, filename, target_id, testing, running, profiling, archiving, analyzing):
    flags = [
        ("buildForTesting", testing),
        ("buildForRunning", running),
        ("buildForProfiling", profiling),
        ("buildForArchiving", archiving),
        ("buildForAnalyzing", analyzing),
    ]
    attrs = "\n".join(f'            {key} = "{"YES" if value else "NO"}"' for key, value in flags)
    return f"""      <BuildActionEntry
{attrs}>
{buildable(name, filename, target_id)}
      </BuildActionEntry>"""


def scheme_xml(app_id, test_id, framework_id, safari_id, shield_id, test="Debug", run="Debug", profile="Release", analyze="Debug", archive="Release"):
    entries = "\n".join([
        entry("Enough", "Enough.app", app_id, True, True, True, True, True),
        entry("FilterEngine", "FilterEngine.framework", framework_id, True, True, True, True, True),
        entry("FilterEngineTests", "FilterEngineTests.xctest", test_id, True, False, False, False, True),
        entry("EnoughSafariExtension", "EnoughSafariExtension.appex", safari_id, False, False, False, True, False),
        entry("EnoughShieldExtension", "EnoughShieldExtension.appex", shield_id, False, False, False, True, False),
    ])
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
{entries}
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "{test}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
{buildable("FilterEngineTests", "FilterEngineTests.xctest", test_id)}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "{run}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{buildable("Enough", "Enough.app", app_id)}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "{profile}"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{buildable("Enough", "Enough.app", app_id)}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "{analyze}">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "{archive}"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    main()

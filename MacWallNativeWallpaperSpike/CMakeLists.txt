cmake_minimum_required(VERSION 3.26)

project(MacWallNativeWallpaperSpike LANGUAGES Swift)

set(CMAKE_XCODE_GENERATE_TOP_LEVEL_PROJECT_ONLY TRUE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "26.0")

set(MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../test/3589742531/【哲风壁纸】夕阳花海-短发-等待.mp4")
set(MACWALL_NATIVE_WALLPAPER_EXTENSION_RESOURCES)
if(EXISTS "${MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE}")
    set(MACWALL_NATIVE_SAMPLE_VIDEO_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/macwall-native-wallpaper-sample.mp4")
    configure_file("${MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE}" "${MACWALL_NATIVE_SAMPLE_VIDEO_RESOURCE}" COPYONLY)
    set_source_files_properties("${MACWALL_NATIVE_SAMPLE_VIDEO_RESOURCE}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    list(APPEND MACWALL_NATIVE_WALLPAPER_EXTENSION_RESOURCES "${MACWALL_NATIVE_SAMPLE_VIDEO_RESOURCE}")
else()
    message(WARNING "Native wallpaper sample video not found; extension will use generated-frame probe fallback.")
endif()

add_executable(MacWallNativeWallpaperExtension MACOSX_BUNDLE
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperRuntimeIdentity.swift
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperVideoSource.swift
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperVideoSourceMode.generated.swift
    MacWallNativeWallpaperExtension/MacWallRemoteContextProbe.swift
    MacWallNativeWallpaperExtension/MacWallSnapshotProbeMode.generated.swift
    MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift
    MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift
    MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift
    MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift
    MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift
    MacWallNativeWallpaperExtension/MacWallWallpaperExtensionConfiguration.swift
    MacWallNativeWallpaperExtension/MacWallWallpaperSettingsViewModelStub.swift
    MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift
    MacWallNativeWallpaperExtension/MacWallWallpaperXPCIntrospection.swift
    MacWallNativeWallpaperExtension/MacWallWallpaperXPCProtocols.swift
    ${MACWALL_NATIVE_WALLPAPER_EXTENSION_RESOURCES}
)

set_target_properties(MacWallNativeWallpaperExtension PROPERTIES
    BUNDLE_EXTENSION "appex"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperExtension/Info.plist"
    XCODE_EXPLICIT_FILE_TYPE "wrapper.extensionkit-extension"
    XCODE_PRODUCT_TYPE "com.apple.product-type.extensionkit-extension"
    XCODE_ATTRIBUTE_APPLICATION_EXTENSION_API_ONLY "YES"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Manual"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "YES"
    XCODE_ATTRIBUTE_ENABLE_APP_SANDBOX "YES"
    XCODE_ATTRIBUTE_INFOPLIST_FILE "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperExtension/Info.plist"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.mingyu1715.macwall.native-wallpaper-spike.extension"
    XCODE_ATTRIBUTE_PRODUCT_NAME "MacWallNativeWallpaperExtension"
    XCODE_ATTRIBUTE_SWIFT_VERSION "6.0"
)

add_executable(MacWallNativeWallpaperSpikeApp MACOSX_BUNDLE
    MacWallNativeWallpaperSpikeApp/main.swift
)

set_target_properties(MacWallNativeWallpaperSpikeApp PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperSpikeApp/Info.plist"
    XCODE_EMBED_EXTENSIONKIT_EXTENSIONS "MacWallNativeWallpaperExtension"
    XCODE_EMBED_EXTENSIONKIT_EXTENSIONS_CODE_SIGN_ON_COPY "YES"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperSpikeApp/MacWallNativeWallpaperSpikeApp.entitlements"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Manual"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "YES"
    XCODE_ATTRIBUTE_ENABLE_APP_SANDBOX "YES"
    XCODE_ATTRIBUTE_INFOPLIST_FILE "${CMAKE_CURRENT_SOURCE_DIR}/MacWallNativeWallpaperSpikeApp/Info.plist"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.mingyu1715.macwall.native-wallpaper-spike"
    XCODE_ATTRIBUTE_PRODUCT_NAME "MacWallNativeWallpaperSpikeApp"
    XCODE_ATTRIBUTE_SWIFT_VERSION "6.0"
)

add_executable(MacWallNativeWallpaperRuntimeIdentityTests
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperRuntimeIdentity.swift
    MacWallNativeWallpaperExtension/MacWallNativeWallpaperVideoSource.swift
    MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift
    MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift
    Tests/MacWallNativeWallpaperRuntimeIdentityTests.swift
    Tests/NativeVideoPlaybackTimingTests.swift
)

set_target_properties(MacWallNativeWallpaperRuntimeIdentityTests PROPERTIES
    XCODE_ATTRIBUTE_SWIFT_VERSION "6.0"
)

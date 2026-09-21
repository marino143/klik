// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Klik",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "CWebRTCAEC3",
            path: "Sources/CWebRTCAEC3",
            exclude: [
                "LICENSE.webrtc-aec3",
                "UPSTREAM.md",
                "audio_processing/resampler/sinc_resampler_sse.cc",
                "audio_processing/aec3/adaptive_fir_filter_avx2.cc",
                "audio_processing/aec3/fft_data_avx2.cc",
                "audio_processing/aec3/matched_filter_avx2.cc",
                "audio_processing/aec3/adaptive_fir_filter_erl_avx2.cc",
                "audio_processing/aec3/vector_math_avx2.cc",
                "common_audio/third_party/ooura/fft_size_128/ooura_fft_sse2.cc",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("WEBRTC_MAC"),
                .define("WEBRTC_POSIX"),
                .headerSearchPath("."),
                .headerSearchPath("api"),
                .headerSearchPath("base"),
                .headerSearchPath("base/rtc_base"),
                .headerSearchPath("base/system_wrappers/include"),
                .headerSearchPath("base/jsoncpp/include"),
                .headerSearchPath("absl"),
                .headerSearchPath("audio_processing"),
                .headerSearchPath("audio_processing/aec3"),
                .headerSearchPath("audio_processing/include"),
                .headerSearchPath("audio_processing/logging"),
                .headerSearchPath("audio_processing/resampler"),
                .headerSearchPath("audio_processing/utility"),
                .headerSearchPath("common_audio"),
                .headerSearchPath("common_audio/third_party/ooura/fft_size_128"),
                .headerSearchPath("rtc_base/experiments"),
            ],
            cxxSettings: [
                .define("WEBRTC_MAC"),
                .define("WEBRTC_POSIX"),
                .unsafeFlags(["-fexceptions", "-Wno-deprecated-declarations"]),
            ]
        ),
        .executableTarget(
            name: "Klik",
            dependencies: ["Sparkle", "CWebRTCAEC3"],
            path: "Sources/Klik"
        ),
        .testTarget(
            name: "CWebRTCAEC3Tests",
            dependencies: ["CWebRTCAEC3", "Klik"],
            path: "Tests/CWebRTCAEC3Tests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)

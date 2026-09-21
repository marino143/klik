# WebRTC AEC3 source

This directory vendors the standalone WebRTC Acoustic Echo Canceller 3
extraction from <https://github.com/Enaium/webrtc-aec3> at commit
`2cec2f52e26646f93bd2d5498bbabf59cba18da9`.

Klik adds `klik_aec3_wrapper.cc` and `include/klik_aec3.h` as a small C API for
Swift. The upstream source remains under the BSD 3-Clause license in
`LICENSE.webrtc-aec3`. The release build copies that license into the app
bundle.

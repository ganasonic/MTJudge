# OpenCV for MTJudge overlay comparison

Pinned official release: **4.12.0**, Apache-2.0 (see `LICENSE`).

Source: https://github.com/opencv/opencv/releases/tag/4.12.0
Archive: `opencv-4.12.0-ios-framework.zip` (211 MB compressed, 582 MB unpacked).
SHA-256: `86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70`.

Run `sh ThirdParty/OpenCV/setup.sh` from a fresh checkout before a device build.
The framework is ignored by Git; the setup script verifies the full archive checksum.
Do not embed this static framework: Xcode links the referenced C++ routines into MTJudge only.
A copy of LICENSE is included as `OpenCV-LICENSE.txt` in the app bundle.

The official archive has arm64 for iOS devices and legacy Intel Simulator slices,
**not arm64 Simulator**. To preserve existing Simulator builds, MTJudge links OpenCV
only for iphoneos. Simulator supports the manual overlay, but automatic registration
and optical-flow analysis require a real device. No app-wide architecture exclusion
or deployment-target change is made. A future source-built minimal XCFramework can
add arm64 Simulator support without changing the registration interface.

No custom Core ML model is bundled: the current implementation uses Apple's Vision
person segmentation, human rectangles and body pose. Detection quality on skis,
poles, boards and spray needs human evaluation with real footage.

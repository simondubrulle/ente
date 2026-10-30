# Ensu for iOS

Source code for the Ensu iOS app.

## Building from source

1. Install [Xcode](https://developer.apple.com/xcode/), [Rust](https://www.rust-lang.org/tools/install), [Node.js 24](https://nodejs.org/), and CMake (e.g. `brew install cmake`).

2. Generate the Swift bindings:

    ```sh
    node .github/scripts/ensu-codegen.mjs
    ```

    Run this from the repository root. The helper uses Photos' checksum-pinned Ente ONNX Runtime installer to supply the host library needed by the binding generator. Xcode links the packaged iOS XCFramework when building the app.

3. Open `Ensu.xcodeproj` in Xcode and run the `Ensu` scheme.

That's it. Apart from generating the bindings, this is a normal iOS project. Xcode compiles and statically links the Rust libraries automatically when building the app.

> [!NOTE]
>
> Re-run the helper whenever the UniFFI-exported surface under `rust/bindings/uniffi/` changes. Internal Rust changes (function bodies, private helpers) are picked up by the normal Xcode build.
>
> From anywhere in the repo:
>
> ```sh
> (cd "$(git rev-parse --show-toplevel)" && node .github/scripts/ensu-codegen.mjs)
> ```

## Terminal builds

> [!NOTE]
>
> If you'd rather not open Xcode, this section is for you.

Build and run on the simulator:

```sh
open -a Simulator

cd apple/apps/ensu
xcodebuild -scheme Ensu -destination 'platform=iOS Simulator,name=iPhone 17'

xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/Ensu-*/Build/Products/Debug-iphonesimulator/Ensu.app
xcrun simctl launch booted io.ente.ensu
```

Create a release archive:

```sh
xcodebuild archive -scheme Ensu \
  -destination 'generic/platform=iOS' \
  -archivePath build/Ensu.xcarchive
```

Export an IPA from the archive:

```sh
xcodebuild -exportArchive \
  -archivePath build/Ensu.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist scripts/ExportOptions-AppStore.plist
```

### Tests

Run the app-hosted inference integration test with these environment variables:

```sh
TEST_RUNNER_ENSU_TEST_MODEL=/path/to/model.gguf \
TEST_RUNNER_ENSU_TEST_MMPROJ=/path/to/mmproj.gguf \
TEST_RUNNER_ENSU_TEST_IMAGE=/path/to/image.png \
xcodebuild test -scheme Ensu \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

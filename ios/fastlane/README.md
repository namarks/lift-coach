fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload an already-built IPA to TestFlight (run scripts/upload-testflight.sh first to build)

### ios submit_for_review

```sh
[bundle exec] fastlane ios submit_for_review
```

Submit an explicitly selected version and build for review, with manual release. Requires separate submission authorization. Pass `version:1.0 build_number:<verified-build-number>`.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

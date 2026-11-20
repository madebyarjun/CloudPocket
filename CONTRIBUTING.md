# Contributing

For a bug, include the CloudPocket version, device and Android version, network mode, and steps that reproduce it. Remove invite tokens, PINs, public tunnel URLs and personal filenames from logs.

Use Flutter 3.50.0. After cloning, run `git lfs pull` and `flutter pub get`. Keep changes focused and preserve streaming file I/O and room expiry behavior. Run `flutter analyze`, `flutter test`, and `node --test test/web/client.test.cjs` before opening a pull request. Include screenshots for visible changes and distinguish automated coverage from physical-device tests.

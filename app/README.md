# Fiend app

The Flutter Windows interface for Fiend. It talks to the Rust engine in `../core` through
`lib/core/native_bridge.dart`; `flutter run -d windows` builds the engine with cargo and
bundles `fiend_core.dll` next to `Fiend.exe`.

See the [main README](../README.md) for features, build steps and flags.

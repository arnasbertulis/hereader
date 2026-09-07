import 'package:flutter/foundation.dart';

/// A human-recognisable label for this device, derived from the platform
/// Flutter reports building for.
///
/// Distinct from `AuthStore.deviceId`: that is an opaque identifier stamped
/// into every synced change, generated once and never shown after that. This
/// label is display-only, recomputed on every read, and never sent anywhere
/// — it says "Windows" rather than a random string, so a same-book conflict
/// prompt across two devices is answerable at a glance instead of by
/// guesswork.
String devicePlatformLabel({TargetPlatform? platform, bool isWeb = kIsWeb}) {
  final resolved = platform ?? defaultTargetPlatform;

  final base = switch (resolved) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone or iPad',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };

  return isWeb ? '$base (browser)' : base;
}

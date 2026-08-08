/// Coercion helpers for JSON written by some other build.
///
/// A profile can reach this device through sync from a client that is newer,
/// older, or configured differently. The constructors in this package assert
/// on ranges, which catches a bug in app code and is wrong at a
/// deserialisation boundary: the sync client's pull loop catches a throw,
/// counts the event as skipped, and advances `sync.last_seq` past it. No later
/// pull returns that event, so the reader loses the change for good.
///
/// Every helper here degrades instead. A number outside its range moves to the
/// nearest bound, a value of the wrong type falls back, and the profile stays
/// readable.
///
/// A cast such as `json['anchorX'] as num?` throws when the value is a string,
/// which is the failure these exist to avoid. Each helper tests the type
/// rather than casting.
///
/// Deliberately not exported from the package barrel. These serve this
/// package's own `fromJson` factories.
library;

/// Reads a double, falling back when the value is missing, not a number, or
/// not finite. Values outside [min] or [max] move to that bound.
double coerceDouble(Object? raw, double fallback, {double? min, double? max}) {
  if (raw is! num) return fallback;

  final value = raw.toDouble();
  if (!value.isFinite) return fallback;

  if (min != null && value < min) return min;
  if (max != null && value > max) return max;
  return value;
}

/// Reads an int, falling back when the value is missing or not a number.
/// Values outside [min] or [max] move to that bound.
int coerceInt(Object? raw, int fallback, {int? min, int? max}) {
  if (raw is! num) return fallback;
  // toInt() on a NaN or an infinity throws, so this is checked before the
  // conversion rather than after it.
  if (raw is double && !raw.isFinite) return fallback;

  final value = raw.toInt();
  if (min != null && value < min) return min;
  if (max != null && value > max) return max;
  return value;
}

bool coerceBool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

/// Reads an optional string. Anything that is not a string reads as absent,
/// which is what an optional field means anyway.
String? coerceStringOrNull(Object? raw) => raw is String ? raw : null;

String coerceString(Object? raw, String fallback) =>
    raw is String && raw.isNotEmpty ? raw : fallback;

/// Reads a nested object. `jsonDecode` produces `Map<String, dynamic>`, so a
/// value of any other shape is not one this package wrote.
Map<String, dynamic>? coerceMap(Object? raw) =>
    raw is Map<String, dynamic> ? raw : null;

/// Resolves an enum by name, falling back rather than throwing.
///
/// A device running an older build may receive a profile from a newer one
/// through sync. An unknown value degrades to the default instead of making
/// the whole profile unreadable.
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;

  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

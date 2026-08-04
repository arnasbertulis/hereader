import 'dart:math' as math;

/// A hybrid logical clock stamp.
///
/// Wall clocks disagree between devices, so ordering writes by timestamp can
/// pick the older one. A pure counter orders correctly but loses any relation
/// to real time. An HLC is both: a millisecond, a counter for stamps landing
/// in the same millisecond, and a device id to break remaining ties.
///
/// The format is fixed-width so lexicographic comparison gives the same
/// answer as comparing the parts. That is what lets the server order by the
/// string in SQL without parsing it, and it is why the widths here must match
/// the server's exactly.
///
/// Format: `{millis:013d}-{counter:05d}-{deviceId}`
class HlcStamp implements Comparable<HlcStamp> {
  /// Milliseconds since the Unix epoch, as claimed by the writing device.
  final int millis;

  /// Distinguishes stamps within one millisecond.
  final int counter;

  /// Which device produced this. Also the final tie-breaker.
  final String deviceId;

  const HlcStamp({
    required this.millis,
    required this.counter,
    required this.deviceId,
  });

  /// 13 digits covers milliseconds until the year 2286, and the server's
  /// pattern requires exactly that many.
  static const int millisWidth = 13;
  static const int counterWidth = 5;

  static final RegExp _format = RegExp(
    r'^(\d{13})-(\d{5})-([A-Za-z0-9_-]{1,64})$',
  );

  static HlcStamp parse(String value) {
    final match = _format.firstMatch(value);
    if (match == null) {
      throw FormatException('Malformed clock stamp', value);
    }

    return HlcStamp(
      millis: int.parse(match.group(1)!),
      counter: int.parse(match.group(2)!),
      deviceId: match.group(3)!,
    );
  }

  static HlcStamp? tryParse(String value) {
    try {
      return parse(value);
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      '${millis.toString().padLeft(millisWidth, '0')}'
      '-${counter.toString().padLeft(counterWidth, '0')}'
      '-$deviceId';

  @override
  int compareTo(HlcStamp other) {
    // Spelled out rather than comparing strings, so the intent survives a
    // change to the widths above.
    final byTime = millis.compareTo(other.millis);
    if (byTime != 0) return byTime;

    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;

    return deviceId.compareTo(other.deviceId);
  }

  bool operator >(HlcStamp other) => compareTo(other) > 0;
  bool operator <(HlcStamp other) => compareTo(other) < 0;
  bool operator >=(HlcStamp other) => compareTo(other) >= 0;
  bool operator <=(HlcStamp other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is HlcStamp &&
      other.millis == millis &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(millis, counter, deviceId);
}

/// Issues stamps for this device, and keeps up with stamps seen from others.
///
/// Not thread-safe, which is fine: Dart is single-threaded per isolate and
/// every write goes through the same instance.
class HybridLogicalClock {
  final String deviceId;

  /// Injectable so tests can control time rather than sleeping.
  final DateTime Function() _now;

  int _lastMillis = 0;
  int _counter = 0;

  HybridLogicalClock({required this.deviceId, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    if (deviceId.isEmpty || deviceId.length > 64) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'must be 1 to 64 characters',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'must contain only letters, digits, underscore and hyphen',
      );
    }
  }

  /// The stamp for a write happening now.
  ///
  /// Never returns a value less than or equal to one it returned before,
  /// even if the system clock moves backwards. A clock that went backwards
  /// would let a later write lose to an earlier one on this same device,
  /// which no amount of server-side ordering could fix.
  HlcStamp issue() {
    final wall = _now().millisecondsSinceEpoch;

    if (wall > _lastMillis) {
      _lastMillis = wall;
      _counter = 0;
    } else {
      // Same millisecond, or the clock went backwards. Either way, keep the
      // millisecond we already used and distinguish by counter.
      _counter++;
    }

    return HlcStamp(millis: _lastMillis, counter: _counter, deviceId: deviceId);
  }

  /// Folds a stamp from another device into this clock.
  ///
  /// After observing a remote stamp, the next stamp this device issues sorts
  /// after it. Without this, two devices whose clocks disagree would keep
  /// producing stamps that interleave confusingly rather than reflecting the
  /// order in which each learned of the other's writes.
  void observe(HlcStamp remote) {
    final wall = _now().millisecondsSinceEpoch;
    final ceiling = math.max(math.max(wall, _lastMillis), remote.millis);

    if (ceiling == _lastMillis && ceiling == remote.millis) {
      _counter = math.max(_counter, remote.counter) + 1;
    } else if (ceiling == _lastMillis) {
      _counter++;
    } else if (ceiling == remote.millis) {
      _counter = remote.counter + 1;
    } else {
      _counter = 0;
    }

    _lastMillis = ceiling;
  }

  /// Restores the clock after a restart.
  ///
  /// Without this, a device that wrote at 12:00 and restarted at 11:59 (a
  /// clock correction, a timezone bug, a manual change) would issue stamps
  /// that lose to its own earlier writes.
  void restoreFrom(HlcStamp last) {
    if (last.millis > _lastMillis) {
      _lastMillis = last.millis;
      _counter = last.counter;
    } else if (last.millis == _lastMillis) {
      _counter = math.max(_counter, last.counter);
    }
  }

  /// The last stamp issued, for persisting across restarts. Null before any
  /// stamp has been issued.
  HlcStamp? get lastIssued => _lastMillis == 0
      ? null
      : HlcStamp(millis: _lastMillis, counter: _counter, deviceId: deviceId);
}

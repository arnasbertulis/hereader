/// How long ago a sync finished, in words.
///
/// Coarse on purpose. The reader is deciding whether to press Sync now, and
/// "4 minutes ago" and "6 minutes ago" lead to the same decision; a clock
/// time would make them read a timestamp and do the subtraction themselves.
///
/// [at] is the stored `sync.last_synced_at` value rather than the one on
/// `SyncState`. The state's copy is set on the successful emit and is null
/// on every other status, so a device that failed its last run would report
/// never having synced.
String describeLastSynced(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not synced on this device yet';

  final elapsed = (now ?? DateTime.now()).difference(at);

  // A stored time ahead of this clock. Devices disagree about the hour more
  // often than anyone expects, and "in 3 hours" is a worse answer than a
  // vague one.
  if (elapsed.isNegative) return 'Synced recently';

  if (elapsed.inMinutes < 1) return 'Synced just now';
  if (elapsed.inMinutes < 60) {
    return 'Synced ${_count(elapsed.inMinutes, 'minute')} ago';
  }
  if (elapsed.inHours < 24) {
    return 'Synced ${_count(elapsed.inHours, 'hour')} ago';
  }

  return 'Synced ${_count(elapsed.inDays, 'day')} ago';
}

String _count(int value, String unit) =>
    value == 1 ? '1 $unit' : '$value ${unit}s';

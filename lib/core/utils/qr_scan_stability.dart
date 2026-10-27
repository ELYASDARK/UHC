/// Requires repeated, consistent reads before submitting a QR value.
/// This is a camera debounce, not a replacement for server validation.
class QrScanStability {
  String? _value;
  DateTime? _firstSeen;
  DateTime? _lastSeen;
  int _reads = 0;

  bool accept(String? value, DateTime now) {
    if (value == null || value.isEmpty) {
      _value = null;
      _reads = 0;
      return false;
    }
    if (value != _value ||
        _lastSeen == null ||
        now.difference(_lastSeen!) > const Duration(milliseconds: 750)) {
      _value = value;
      _firstSeen = now;
      _reads = 0;
    }
    _lastSeen = now;
    _reads++;
    return _reads >= 3 &&
        now.difference(_firstSeen!) >= const Duration(milliseconds: 650);
  }
}

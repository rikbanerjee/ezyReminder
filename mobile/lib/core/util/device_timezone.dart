import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiet_hours.dart';

/// The iPhone's own time zone and whether the account follows it. While it
/// does, the app copies the phone's zone into `user_settings.timezone`, which
/// the server, Focus, Side Gig dates and quiet hours all use. Saving a zone by
/// hand in Settings stops following, so a deliberate choice is never undone.
class DeviceTimezone {
  static const _channel = MethodChannel('ezyreminder/device');
  static const _followKey = 'timezone.follow_device';

  /// The IANA name, e.g. America/New_York; null when unavailable.
  /// Replaceable in tests.
  static Future<String?> Function() read = _readNative;

  static Future<String?> _readNative() async {
    try {
      final zone = await _channel.invokeMethod<String>('timeZone');
      return zone != null && isValidTimeZone(zone) ? zone : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> follows() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_followKey) ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setFollows(bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_followKey, value);
    } catch (_) {}
  }
}

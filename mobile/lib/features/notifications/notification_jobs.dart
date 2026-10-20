import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'reminder_alerts.dart';

/// Entry point for the background engine iOS starts when the app isn't
/// running: Done / Snooze 1h from the lock screen, and background refresh.
/// It uses the same persisted session as the app. Swift names this function
/// and library, so keep them in step with `ReminderNotifications.swift`.
@pragma('vm:entry-point')
Future<void> notificationJobsMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  final platform = MethodChannelAlertPlatform();
  Future<ReminderAlerts>? ready;
  await platform.attach((method, args) async {
    if (method != 'job' || args is! Map) return null;
    if (url.isEmpty || key.isEmpty) return null;
    final alerts = await (ready ??= () async {
      await Supabase.initialize(url: url, publishableKey: key);
      return ReminderAlerts(
        source: SupabaseAlertSource(Supabase.instance.client),
        platform: platform,
      );
    }());
    await alerts.run(args);
    return null;
  });
}

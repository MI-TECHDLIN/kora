import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';

/// Starts the signed-in driver's profile sync without placing failures over
/// the app UI. The provider logs failures and tries again on the next sign-in
/// or restored session.
class DriverProfileNotice extends ConsumerWidget {
  const DriverProfileNotice({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(driverProfileProvider);
    return child;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../data/auth_repository.dart';
import 'auth_controls.dart';

/// Tells the driver when their `drivers` row couldn't be created after a
/// sign-in, so a half-set-up account never passes for a finished one.
/// Sits above the router (the notice outlives the sign-up screen, which the
/// auth gate replaces as soon as the session lands).
class DriverProfileNotice extends ConsumerWidget {
  const DriverProfileNotice({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<DriverProfileException?>(driverProfileProvider, (_, failure) {
      if (failure == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(authNotice(failure.message));
    });
    return child;
  }
}

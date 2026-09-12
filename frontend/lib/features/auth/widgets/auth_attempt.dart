import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../data/auth_repository.dart';

/// Busy and error state shared by the auth forms. One attempt runs at a
/// time; an [AuthFailure] becomes [error] and stays up until the next try.
mixin AuthAttempt<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  /// Runs [call], or returns null without running it while another attempt
  /// is in flight or when it fails. A successful sign-in needs no handling
  /// here: the router's auth gate moves on by itself.
  Future<R?> attempt<R>(Future<R> Function(AuthRepository auth) call) async {
    if (busy) return null;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      return await call(ref.read(authRepositoryProvider));
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

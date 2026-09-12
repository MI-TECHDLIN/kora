import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voiceops/features/auth/data/auth_repository.dart';
import 'package:voiceops/providers/auth_provider.dart';

/// An offline stand-in for Supabase Auth: no network, no platform channels.
/// Records every call; set [failure] or [profileFailure] to script errors.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false});

  bool signedIn;
  SignUpResult signUpResult = SignUpResult.signedIn;

  /// Thrown by the next sign-up / sign-in / Google call while set.
  AuthFailure? failure;

  /// Thrown by [ensureDriverProfile] while set.
  DriverProfileException? profileFailure;

  SignUpDetails? lastSignUp;
  ({String email, String password})? lastSignIn;
  int googleCalls = 0;
  int profileChecks = 0;

  final _changes = StreamController<AuthChangeEvent>.broadcast();

  /// A session lands, as when Supabase finishes a sign-in.
  void completeSignIn() {
    signedIn = true;
    _changes.add(AuthChangeEvent.signedIn);
  }

  void _failIfScripted() {
    if (failure case final f?) throw f;
  }

  @override
  bool get hasValidSession => signedIn;

  @override
  Stream<AuthChangeEvent> get changes => _changes.stream;

  @override
  Future<SignUpResult> signUp(SignUpDetails details) async {
    lastSignUp = details;
    _failIfScripted();
    if (signUpResult == SignUpResult.signedIn) completeSignIn();
    return signUpResult;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastSignIn = (email: email, password: password);
    _failIfScripted();
    completeSignIn();
  }

  @override
  Future<void> signInWithGoogle() async {
    googleCalls++;
    _failIfScripted();
  }

  @override
  Future<void> ensureDriverProfile() async {
    profileChecks++;
    if (profileFailure case final f?) throw f;
  }
}

/// Boots the app already signed in, past the auth gate.
List<Override> signedInOverrides() => [
  authRepositoryProvider.overrideWithValue(FakeAuthRepository(signedIn: true)),
];

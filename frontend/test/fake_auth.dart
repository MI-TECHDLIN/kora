import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voiceops/features/auth/data/auth_repository.dart';
import 'package:voiceops/providers/auth_provider.dart';

/// An offline stand-in for Supabase Auth: no network, no platform channels.
/// Records every call; set [failure] to script errors. Driver-row creation
/// is a backend call now (`KoraApi.ensureDriverProfile`, see `fake_voice.dart`'s
/// `FakeKoraApi`), not part of this fake.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false});

  bool signedIn;
  SignUpResult signUpResult = SignUpResult.signedIn;

  /// Thrown by the next auth call while set.
  AuthFailure? failure;

  SignUpDetails? lastSignUp;
  ({String email, String password})? lastSignIn;
  int googleCalls = 0;
  int signOutCalls = 0;

  final _changes = StreamController<AuthChangeEvent>.broadcast();

  /// A session lands, as when Supabase finishes a sign-in.
  void completeSignIn() {
    signedIn = true;
    _changes.add(AuthChangeEvent.signedIn);
  }

  /// The session ends and Supabase's signed-out event reaches every listener.
  @override
  Future<void> signOut() async {
    signOutCalls++;
    _failIfScripted();
    signedIn = false;
    _changes.add(AuthChangeEvent.signedOut);
  }

  void _failIfScripted() {
    if (failure case final f?) throw f;
  }

  @override
  bool get hasValidSession => signedIn;

  @override
  String? get accessToken => signedIn ? 'test-access-token' : null;

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
}

/// Boots the app already signed in, past the auth gate.
List<Override> signedInOverrides() => [
  authRepositoryProvider.overrideWithValue(FakeAuthRepository(signedIn: true)),
];

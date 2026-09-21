import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/voice_onboarding/screens/voice_onboarding_screen.dart';
import 'package:voiceops/features/voice_onboarding/widgets/voice_character_rive.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

class _FakeArt implements VoiceArt {
  _FakeArt(this.voice, this.selected, this.speaking);
  final CoRiderVoice voice;
  bool selected;
  bool speaking;
  bool disposed = false;

  @override
  void update({required bool selected, required bool speaking}) {
    this.selected = selected;
    this.speaking = speaking;
  }

  @override
  void dispose() => disposed = true;

  @override
  Widget build() => SizedBox(key: Key('fake-art-${voice.name}'));
}

/// Regression: the preview card kept the first voice's Rive artboard after
/// the selection changed, because the slot built its art once per file.
void main() {
  setUpAll(disableGoogleFontsFetching);

  final created = <_FakeArt>[];
  bool failFor(CoRiderVoice v) => false;
  var shouldFail = failFor;

  setUp(() {
    created.clear();
    shouldFail = failFor;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        ...offlineOverrides(
          coRiderVoiceStore: FakeCoRiderVoiceStore(),
          voiceOnboardingStore: FakeVoiceOnboardingStore(),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        voiceArtFactoryProvider.overrideWithValue((
          voice, {
          required selected,
          required speaking,
        }) {
          if (shouldFail(voice)) return null;
          final art = _FakeArt(voice, selected, speaking);
          created.add(art);
          return art;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(body: VoiceOnboardingScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> select(WidgetTester tester, CoRiderVoice v) async {
    final f = find.byKey(Key('voice-onboarding-option-${v.name}'));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  /// The card is the one slot whose art is not disposed and is `selected`
  /// and shown at size 48.
  Finder cardArt(CoRiderVoice v) => find.descendant(
    of: find.ancestor(
      of: find.byKey(Key('voice-onboarding-preview-${v.name}')),
      matching: find.byType(Row),
    ),
    matching: find.byKey(Key('fake-art-${v.name}')),
  );

  testWidgets('the preview card recreates its art for each new voice', (
    tester,
  ) async {
    await pump(tester);
    final first = CoRiderVoice.fallback;
    expect(cardArt(first), findsOneWidget);

    final next = CoRiderVoice.values.firstWhere((v) => v != first);
    await select(tester, next);
    expect(cardArt(next), findsOneWidget, reason: 'card shows the new voice');
    expect(cardArt(first), findsNothing);
    final old = created.lastWhere((a) => a.voice == first && a.disposed);
    expect(old.disposed, isTrue);

    final third = CoRiderVoice.values.firstWhere(
      (v) => v != first && v != next,
    );
    await select(tester, third);
    expect(cardArt(third), findsOneWidget);
    expect(cardArt(next), findsNothing);
  });

  testWidgets('quick successive taps leave the card on the last voice', (
    tester,
  ) async {
    await pump(tester);
    final others = CoRiderVoice.values
        .where((v) => v != CoRiderVoice.fallback)
        .take(3)
        .toList();
    for (final v in others) {
      final f = find.byKey(Key('voice-onboarding-option-${v.name}'));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pump();
    }
    await settle(tester);
    expect(cardArt(others.last), findsOneWidget);
    for (final v in others.take(2)) {
      expect(cardArt(v), findsNothing);
    }
  });

  testWidgets('a failed creation falls back to the placeholder', (
    tester,
  ) async {
    await pump(tester);
    final first = CoRiderVoice.fallback;
    final next = CoRiderVoice.values.firstWhere((v) => v != first);
    shouldFail = (v) => v == next;
    await select(tester, next);
    expect(cardArt(first), findsNothing, reason: 'no stale artboard');
    expect(cardArt(next), findsNothing);
    expect(find.text(next.label), findsWidgets);
  });

  testWidgets('all art is disposed when the screen exits', (tester) async {
    await pump(tester);
    await select(
      tester,
      CoRiderVoice.values.firstWhere((v) => v != CoRiderVoice.fallback),
    );
    await tester.pumpWidget(const SizedBox());
    expect(created, isNotEmpty);
    expect(created.every((a) => a.disposed), isTrue);
  });
}

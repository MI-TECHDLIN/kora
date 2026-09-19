import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/primary_button.dart';
import 'package:voiceops/features/settings/widgets/co_rider_voice_picker.dart';
import 'package:voiceops/features/voice_onboarding/screens/voice_onboarding_screen.dart';
import 'package:voiceops/features/voice_onboarding/widgets/voice_character_rive.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';
import 'package:voiceops/providers/voice_preview_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

/// The voice pickers' preview (bundled clips, no mic), draft-vs-saved
/// behaviour, and the Rive-with-placeholder-fallback character slots.
void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeVoicePreviewPlayer player;
  late FakeVoiceConnector connector;
  late FakeRecorder recorder;
  late FakeVoiceOpsApi api;
  late FakeCoRiderVoiceStore store;
  late FakeVoiceOnboardingStore onboardingStore;
  late ProviderContainer container;
  var fileReads = 0;

  setUp(() {
    player = FakeVoicePreviewPlayer();
    connector = FakeVoiceConnector();
    recorder = FakeRecorder();
    api = FakeVoiceOpsApi();
    store = FakeCoRiderVoiceStore();
    onboardingStore = FakeVoiceOnboardingStore();
    fileReads = 0;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...offlineOverrides(
          connector: connector,
          recorder: recorder,
          api: api,
          coRiderVoiceStore: store,
          voicePreviewPlayer: player,
          voiceOnboardingStore: onboardingStore,
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        // Counts loads, and stands in for "the .riv isn't there yet".
        voiceCharactersFileProvider.overrideWith((ref) async {
          fileReads++;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Finder onboardingOption(CoRiderVoice v) =>
      find.byKey(Key('voice-onboarding-option-${v.name}'));
  Finder onboardingPreview(CoRiderVoice v) =>
      find.byKey(Key('voice-onboarding-preview-${v.name}'));

  /// Nothing in the live-conversation path ran.
  void expectNoConversation() {
    expect(recorder.starts, 0);
    expect(recorder.permissionRequests, 0);
    expect(connector.sockets, isEmpty);
    expect(api.shiftCalls, 0);
    expect(container.read(pushToTalkProvider), PushToTalkState.idle);
    expect(
      container.read(voiceSessionProvider).connection,
      VoiceConnection.disconnected,
    );
  }

  group('onboarding preview', () {
    // Bug 1: the preview button called the app-wide push-to-talk, which
    // opened the mic, connected the voice socket (starting a shift) and put
    // the shared push-to-talk state into `recording` for the main screen.
    testWidgets('plays the clip and never opens the mic, socket or shift', (
      tester,
    ) async {
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingPreview(CoRiderVoice.anna));

      expect(player.played, [CoRiderVoice.anna]);
      expect(container.read(voicePreviewProvider).playing, CoRiderVoice.anna);
      expectNoConversation();

      player.finish();
      await settle(tester);
      expect(container.read(voicePreviewProvider).playing, isNull);
      expectNoConversation();
    });

    testWidgets('previews the draft, and stops when another voice is picked', (
      tester,
    ) async {
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingOption(CoRiderVoice.michael));
      await tap(tester, onboardingPreview(CoRiderVoice.michael));
      expect(player.played, [CoRiderVoice.michael]);
      expect(player.isPlaying, isTrue);

      await tap(tester, onboardingOption(CoRiderVoice.eve));
      expect(player.isPlaying, isFalse);
      expect(container.read(voicePreviewProvider).playing, isNull);
      // Still only a draft: nothing saved, nothing conversational.
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);
      expectNoConversation();
    });

    testWidgets('a second tap stops the clip', (tester) async {
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingPreview(CoRiderVoice.anna));
      expect(player.isPlaying, isTrue);
      await tap(tester, onboardingPreview(CoRiderVoice.anna));
      expect(player.isPlaying, isFalse);
      expect(player.played, hasLength(1));
    });

    testWidgets('leaving the screen stops the clip', (tester) async {
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingPreview(CoRiderVoice.anna));
      expect(player.isPlaying, isTrue);

      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      expect(player.isPlaying, isFalse);
    });

    testWidgets('a voice with no clip is disabled and says so, no crash', (
      tester,
    ) async {
      player.available = {CoRiderVoice.eve};
      await pump(tester, const VoiceOnboardingScreen());

      final anna = tester.widget<IconButton>(
        onboardingPreview(CoRiderVoice.anna),
      );
      expect(anna.onPressed, isNull);
      expect(find.text('Preview coming soon'), findsOneWidget);
      await tester.tap(
        onboardingPreview(CoRiderVoice.anna),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(player.played, isEmpty);

      // Another voice that does have a clip still works.
      await tap(tester, onboardingOption(CoRiderVoice.eve));
      expect(find.text('Tap to hear a short preview'), findsOneWidget);
      await tap(tester, onboardingPreview(CoRiderVoice.eve));
      expect(player.played, [CoRiderVoice.eve]);
    });

    testWidgets('with no clips at all every preview is disabled', (
      tester,
    ) async {
      player.available = {};
      await pump(tester, const VoiceOnboardingScreen());
      expect(
        tester
            .widget<IconButton>(onboardingPreview(CoRiderVoice.anna))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a clip that fails to play degrades to unavailable', (
      tester,
    ) async {
      player.broken.add(CoRiderVoice.anna);
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingPreview(CoRiderVoice.anna));

      expect(tester.takeException(), isNull);
      expect(container.read(voicePreviewProvider).playing, isNull);
      expect(
        tester
            .widget<IconButton>(onboardingPreview(CoRiderVoice.anna))
            .onPressed,
        isNull,
      );
      expect(find.text('Preview coming soon'), findsOneWidget);
    });
  });

  group('onboarding draft and save', () {
    testWidgets('a tap is a draft; Save commits it and finishes the step', (
      tester,
    ) async {
      await pump(tester, const VoiceOnboardingScreen());
      await tap(tester, onboardingOption(CoRiderVoice.michael));

      expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);
      expect(store.value, isNull);
      expect(find.text('Save'), findsOneWidget);
      // The draft is what's highlighted and previewed.
      expect(
        tester.getSemantics(onboardingOption(CoRiderVoice.michael)),
        matchesSemantics(
          label: 'Michael',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
        ),
      );

      await tap(tester, find.byKey(const Key('voice-onboarding-save')));
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
      expect(store.value, CoRiderVoice.michael);
      expect(onboardingStore.shown, isTrue);
    });

    testWidgets('continuing without a change still completes with the '
        'fallback voice', (tester) async {
      await pump(tester, const VoiceOnboardingScreen());
      expect(find.text('Continue'), findsOneWidget);
      await tap(tester, find.byKey(const Key('voice-onboarding-save')));
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.fallback);
      expect(onboardingStore.shown, isTrue);
    });

    testWidgets('a live session is told to switch when Save is tapped', (
      tester,
    ) async {
      await pump(tester, const VoiceOnboardingScreen());
      // A conversation already open (say, resumed from a previous run).
      container.read(voiceSessionProvider.notifier).startConversation();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final socket = connector.last;
      expect(socket.uri.queryParameters, {'voice': 'anna'});

      await tap(tester, onboardingOption(CoRiderVoice.paul));
      await tap(tester, find.byKey(const Key('voice-onboarding-save')));
      expect(socket.sentText, [
        {'event': 'change_voice', 'voice': 'paul'},
      ]);

      container.read(voiceSessionProvider.notifier).disconnect();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('settings draft and save', () {
    final save = find.byKey(const Key('co-rider-voice-save'));
    Finder row(String label) => find.bySemanticsLabel(label);

    testWidgets('Save enables on a draft, commits, and shows the new voice', (
      tester,
    ) async {
      await pump(
        tester,
        const SingleChildScrollView(child: CoRiderVoicePicker()),
      );
      bool saveEnabled() =>
          tester.widget<PrimaryButton>(save).onPressed != null;
      expect(saveEnabled(), isFalse);
      expect(find.text('Your co-rider speaks as Anna.'), findsOneWidget);

      await tap(tester, row('Michael'));
      expect(find.text('Save to switch to Michael.'), findsOneWidget);
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);
      expect(store.value, isNull);
      expect(saveEnabled(), isTrue);

      // Tapping back to the saved voice clears the pending change.
      await tap(tester, row('Anna'));
      expect(find.text('Your co-rider speaks as Anna.'), findsOneWidget);

      await tap(tester, row('Michael'));
      await tap(tester, save);
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
      expect(store.value, CoRiderVoice.michael);
      expect(
        find.text("Michael is now your co-rider's voice."),
        findsOneWidget,
      );
    });

    testWidgets('previews use the draft and never start a conversation', (
      tester,
    ) async {
      await pump(
        tester,
        const SingleChildScrollView(child: CoRiderVoicePicker()),
      );
      await tap(tester, find.byKey(const Key('co-rider-voice-preview-jane')));
      expect(player.played, [CoRiderVoice.jane]);
      expect(find.text('Save to switch to Jane.'), findsOneWidget);
      expectNoConversation();

      await tap(tester, row('Vera'));
      expect(player.isPlaying, isFalse);
    });

    testWidgets('a voice with no clip has a disabled preview', (tester) async {
      player.available = {};
      await pump(
        tester,
        const SingleChildScrollView(child: CoRiderVoicePicker()),
      );
      final button = tester.widget<IconButton>(
        find.byKey(const Key('co-rider-voice-preview-anna')),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings never loads the Rive character file', (tester) async {
      await pump(
        tester,
        const SingleChildScrollView(child: CoRiderVoicePicker()),
      );
      expect(fileReads, 0);
    });
  });

  group('Rive character slots', () {
    testWidgets('onboarding asks for the file and falls back to the '
        'placeholder while it is missing', (tester) async {
      await pump(tester, const VoiceOnboardingScreen());
      expect(fileReads, 1);
      // Every voice still renders its initial, selected one included.
      for (final voice in CoRiderVoice.values) {
        expect(
          find.descendant(
            of: onboardingOption(voice),
            matching: find.text(voice.label[0]),
          ),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
    });

    test(
      'the real loader yields null, not an error, when the .riv is absent',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect(await c.read(voiceCharactersFileProvider.future), isNull);
      },
    );

    test(
      'the contract names match docs/kora-voice-characters-rive-spec.md',
      () {
        expect(voiceCharactersAsset, 'assets/rive/voice_characters.riv');
        expect(voiceStateMachine, 'Voice');
        expect(selectedInput, 'selected');
        expect(speakingInput, 'speaking');
        expect(
          CoRiderVoice.values.map((v) => v.name),
          containsAll([
            'alba', 'eve', 'george', 'jane', 'jean', 'mary', //
            'michael', 'anna', 'charles', 'paul', 'vera',
          ]),
        );
      },
    );
  });
}

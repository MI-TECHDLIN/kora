import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/primary_button.dart';
import 'package:voiceops/features/auth/data/auth_repository.dart';
import 'package:voiceops/features/auth/screens/sign_in_screen.dart';
import 'package:voiceops/features/auth/screens/sign_up_screen.dart';
import 'package:voiceops/features/auth/widgets/auth_text_field.dart';
import 'package:voiceops/providers/auth_provider.dart';

import 'fake_auth.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  for (final form in [
    (
      screen: const SignUpScreen(),
      title: SignUpScreen.title,
      fields: {
        'Full name': 'Ada Obi',
        'Email': 'ada@voiceops.test',
        'Password': 'correct-horse',
        'Phone number': '+2348012345678',
      },
    ),
    (
      screen: const SignInScreen(),
      title: SignInScreen.title,
      fields: {'Email': 'ada@voiceops.test', 'Password': 'correct-horse'},
    ),
  ]) {
    final fields = [
      for (final label in form.fields.keys)
        find.widgetWithText(AuthTextField, label),
    ];
    final submit = find.widgetWithText(PrimaryButton, form.title);
    final items = [...fields, submit];

    List<double> opacities(WidgetTester tester) => [
      for (final item in items)
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(of: item, matching: find.byType(FadeTransition))
                  .first,
            )
            .opacity
            .value,
    ];

    Future<FakeAuthRepository> pumpForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeAuthRepository()
        ..failure = const AuthFailure('Please try again.');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
          child: MaterialApp(theme: buildKoraTheme(), home: form.screen),
        ),
      );
      return auth;
    }

    Future<void> verifyInteraction(
      WidgetTester tester,
      FakeAuthRepository auth,
    ) async {
      expect(opacities(tester), everyElement(1.0));
      for (final entry in form.fields.entries) {
        final editable = find.descendant(
          of: find.widgetWithText(AuthTextField, entry.key),
          matching: find.byType(EditableText),
        );
        await tester.ensureVisible(editable);
        await tester.pump();
        expect(editable.hitTestable(), findsOneWidget);
        await tester.tap(editable);
        await tester.pump();
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );
        await tester.enterText(editable, entry.value);
        await tester.pump(KoraMotion.slow);
      }
      if (form.screen is SignUpScreen) {
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
      }
      await tester.ensureVisible(submit);
      await tester.pump();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await tester.pump();
      if (form.screen is SignUpScreen) {
        expect(auth.lastSignUp?.email, 'ada@voiceops.test');
      } else {
        expect(auth.lastSignIn?.email, 'ada@voiceops.test');
      }
      expect(find.text('Please try again.'), findsOneWidget);
      // Busy/error/terms rebuilds must not replay the entrance.
      expect(opacities(tester), everyElement(1.0));
      expect(tester.takeException(), isNull);
    }

    testWidgets('${form.title} arrives top to bottom and stays interactive', (
      tester,
    ) async {
      final auth = await pumpForm(tester);
      final initialPositions = items.map(tester.getTopLeft).toList();
      expect(opacities(tester), everyElement(0.0));

      final firstVisible = List<int?>.filled(items.length, null);
      final step = KoraMotion.fast ~/ 2;
      for (
        var elapsed = step;
        elapsed <= KoraMotion.stagger;
        elapsed += step
      ) {
        await tester.pump(step);
        final values = opacities(tester);
        for (var i = 0; i < values.length; i++) {
          if (values[i] > 0) firstVisible[i] ??= elapsed.inMicroseconds;
        }
        if (elapsed == step) {
          // A visible field can already take focus while later fields wait.
          final editable = find.descendant(
            of: fields.first,
            matching: find.byType(EditableText),
          );
          await tester.tap(editable);
          await tester.pump();
          expect(
            tester.widget<EditableText>(editable).focusNode.hasFocus,
            isTrue,
          );
        }
      }
      for (var i = 1; i < firstVisible.length; i++) {
        expect(firstVisible[i], greaterThan(firstVisible[i - 1]!));
      }
      expect(opacities(tester), everyElement(1.0));
      for (var i = 0; i < items.length; i++) {
        final end = tester.getTopLeft(items[i]);
        expect(end.dx, initialPositions[i].dx);
        expect(
          end.dy,
          closeTo(initialPositions[i].dy + KoraSpacing.md, 0.01),
        );
      }
      await verifyInteraction(tester, auth);
    });

    testWidgets('${form.title} is immediately usable with reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final auth = await pumpForm(tester);
      expect(opacities(tester), everyElement(1.0));
      expect(tester.binding.transientCallbackCount, 0);
      await verifyInteraction(tester, auth);
    });

    testWidgets('${form.title} settles when reduced motion is enabled', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.pump(KoraMotion.fast);
      expect(opacities(tester).first, inExclusiveRange(0.0, 1.0));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(opacities(tester), everyElement(1.0));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: false);
      await tester.pump();
      expect(opacities(tester), everyElement(1.0));
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}

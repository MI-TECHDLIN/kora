import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/pill_chip.dart';
import 'package:voiceops/core/widgets/primary_button.dart';
import 'package:voiceops/core/widgets/section_header.dart';

import 'test_fonts.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildVoiceOpsTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('kit primitives are const-constructible and render', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(title: 'Today', actionLabel: 'See all'),
            PillChip(
              icon: TablerIcons.route,
              label: 'Next stop',
              accent: VoiceOpsColors.blue,
            ),
            PillChip(
              icon: TablerIcons.phone,
              label: 'Call customer',
              accent: VoiceOpsColors.pink,
              filled: true,
            ),
            PrimaryButton(label: 'Get started', onPressed: null),
          ],
        ),
      ),
    );
    expect(find.text('Next stop'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    final chip = tester.getSize(find.byType(PillChip).first);
    expect(chip.height, greaterThanOrEqualTo(VoiceOpsSize.touchTarget));
  });

  testWidgets('PillChip refuses the live lime accent', (tester) async {
    await tester.pumpWidget(
      _host(
        const PillChip(
          icon: TablerIcons.microphone,
          label: 'Nope',
          accent: VoiceOpsColors.live,
        ),
      ),
    );
    expect(tester.takeException(), isAssertionError);
  });
}

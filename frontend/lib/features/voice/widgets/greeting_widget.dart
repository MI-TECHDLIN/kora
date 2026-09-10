import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';

class GreetingWidget extends StatelessWidget {
  const GreetingWidget({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Hello, $name!', style: VoiceOpsText.greetingSmall),
        const SizedBox(height: 2),
        Text(
          'How can I help you today?',
          style: VoiceOpsText.greetingLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

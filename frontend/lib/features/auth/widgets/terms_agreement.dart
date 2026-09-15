import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../legal_document.dart';
import 'legal_document_viewer.dart';

export '../legal_document.dart';

/// Sign-up's agreement gate: a checkbox plus the policy links. The account
/// can't be created until [value] is true; [showError] flags a submit
/// attempt without it.
class TermsAgreement extends StatefulWidget {
  const TermsAgreement({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
    this.enabled = true,
  });

  static const errorText = 'Agree to the terms to create your account';

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showError;
  final bool enabled;

  @override
  State<TermsAgreement> createState() => _TermsAgreementState();
}

class _TermsAgreementState extends State<TermsAgreement> {
  late final _links = {
    for (final doc in LegalDocument.values)
      doc: TapGestureRecognizer()..onTap = () => _open(doc),
  };

  @override
  void dispose() {
    for (final link in _links.values) {
      link.dispose();
    }
    super.dispose();
  }

  void _open(LegalDocument doc) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: VoiceOpsColors.canvas,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: LegalDocumentViewer(document: doc),
      ),
    );
  }

  void _toggle() {
    if (widget.enabled) widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final link = VoiceOpsText.weight(
      VoiceOpsText.body,
      FontWeight.w700,
    ).copyWith(color: VoiceOpsColors.primaryLight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: widget.value,
              isError: widget.showError,
              onChanged: widget.enabled
                  ? (checked) => widget.onChanged(checked ?? false)
                  : null,
              semanticLabel:
                  'I agree to the Terms of Service and Privacy Policy',
              activeColor: VoiceOpsColors.primary,
              checkColor: VoiceOpsColors.onPrimary,
              side: const BorderSide(
                color: VoiceOpsColors.textMuted,
                width: VoiceOpsGlass.borderWidth,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(VoiceOpsSpacing.xs),
              ),
            ),
            const SizedBox(width: VoiceOpsSpacing.xs),
            Expanded(
              // Tapping the sentence (outside the links) toggles the box too.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: Text.rich(
                  TextSpan(
                    text: 'I agree to the ',
                    style: VoiceOpsText.bodyMuted,
                    children: [
                      TextSpan(
                        text: LegalDocument.terms.title,
                        style: link,
                        recognizer: _links[LegalDocument.terms],
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: LegalDocument.privacy.title,
                        style: link,
                        recognizer: _links[LegalDocument.privacy],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.showError)
          _Note(TermsAgreement.errorText, color: VoiceOpsColors.danger),
      ],
    );
  }
}

/// A line under the sentence, read out by screen readers as it appears.
class _Note extends StatelessWidget {
  const _Note(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lines up under the sentence, past the checkbox's tap target.
      padding: const EdgeInsets.only(
        left: VoiceOpsSize.touchTarget + VoiceOpsSpacing.xs,
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(text, style: VoiceOpsText.label.copyWith(color: color)),
      ),
    );
  }
}

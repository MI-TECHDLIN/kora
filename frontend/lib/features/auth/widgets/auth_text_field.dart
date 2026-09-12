import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';

/// A labelled glass text field for the auth forms: the label sits above the
/// field, and [obscure] adds a show/hide toggle for passwords.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.obscure = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool obscure;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _hidden = widget.obscure;

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(VoiceOpsRadius.control),
    borderSide: BorderSide(color: color, width: VoiceOpsGlass.borderWidth),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: VoiceOpsText.label.copyWith(color: VoiceOpsColors.textMuted),
        ),
        const SizedBox(height: VoiceOpsSpacing.sm),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          enabled: widget.enabled,
          obscureText: _hidden,
          enableSuggestions: !widget.obscure,
          autocorrect: false,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: widget.onSubmitted,
          style: VoiceOpsText.body,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: VoiceOpsText.body.copyWith(
              color: VoiceOpsColors.textFaint,
            ),
            errorStyle: VoiceOpsText.label.copyWith(
              color: VoiceOpsColors.danger,
            ),
            errorMaxLines: 2,
            filled: true,
            fillColor: VoiceOpsGlass.fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: VoiceOpsSpacing.lg,
              vertical: VoiceOpsSpacing.lg,
            ),
            prefixIcon: Icon(
              widget.icon,
              size: VoiceOpsSize.iconMd,
              color: VoiceOpsColors.textFaint,
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden ? TablerIcons.eye : TablerIcons.eyeOff,
                      size: VoiceOpsSize.iconMd,
                      color: VoiceOpsColors.textMuted,
                    ),
                  )
                : null,
            border: _outline(VoiceOpsGlass.border),
            enabledBorder: _outline(VoiceOpsGlass.border),
            disabledBorder: _outline(VoiceOpsColors.divider),
            focusedBorder: _outline(VoiceOpsColors.primaryLight),
            errorBorder: _outline(VoiceOpsColors.danger),
            focusedErrorBorder: _outline(VoiceOpsColors.danger),
          ),
        ),
      ],
    );
  }
}

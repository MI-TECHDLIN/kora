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
    borderRadius: BorderRadius.circular(KoraRadius.control),
    borderSide: BorderSide(color: color, width: KoraGlass.borderWidth),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: KoraText.label.copyWith(color: KoraColors.textMuted),
        ),
        const SizedBox(height: KoraSpacing.sm),
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
          style: KoraText.body,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: KoraText.body.copyWith(
              color: KoraColors.textFaint,
            ),
            errorStyle: KoraText.label.copyWith(
              color: KoraColors.danger,
            ),
            errorMaxLines: 2,
            filled: true,
            fillColor: KoraGlass.fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KoraSpacing.lg,
              vertical: KoraSpacing.lg,
            ),
            prefixIcon: Icon(
              widget.icon,
              size: KoraSize.iconMd,
              color: KoraColors.textFaint,
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden ? TablerIcons.eye : TablerIcons.eyeOff,
                      size: KoraSize.iconMd,
                      color: KoraColors.textMuted,
                    ),
                  )
                : null,
            border: _outline(KoraGlass.border),
            enabledBorder: _outline(KoraGlass.border),
            disabledBorder: _outline(KoraColors.divider),
            focusedBorder: _outline(KoraColors.primaryLight),
            errorBorder: _outline(KoraColors.danger),
            focusedErrorBorder: _outline(KoraColors.danger),
          ),
        ),
      ],
    );
  }
}

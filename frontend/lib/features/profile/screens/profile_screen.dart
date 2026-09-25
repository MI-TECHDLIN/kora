import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/api/voiceops_api.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/company_connection_provider.dart';
import '../../../providers/driver_details_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/widgets/auth_text_field.dart';

/// The driver's own details (`GET`/`PUT /v1/driver/profile`) and their
/// company link (`POST /v1/driver/connect`). Opened from the voice screen's
/// top-right icon; the vehicle itself is chosen in Settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverDetailsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KoraSpacing.gutter,
          KoraSpacing.sm,
          KoraSpacing.gutter,
          KoraSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('profile-back'),
                  tooltip: 'Back',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.voice),
                  icon: const Icon(
                    TablerIcons.arrowLeft,
                    size: KoraSize.iconLg,
                    color: KoraColors.textPrimary,
                  ),
                ),
                const SizedBox(width: KoraSpacing.xs),
                Text('Profile', style: KoraText.headline),
              ],
            ),
            const SizedBox(height: KoraSpacing.lg),
            ...profile.when(
              loading: () => [
                const _StatusCard(
                  key: Key('profile-loading'),
                  icon: TablerIcons.userCircle,
                  title: 'Your profile',
                  message: 'Loading your details…',
                ),
              ],
              error: (error, _) => [
                _StatusCard(
                  key: const Key('profile-error'),
                  icon: TablerIcons.alertCircle,
                  title: "Couldn't load your profile",
                  message: error is ApiException
                      ? error.message
                      : 'Something went wrong. Try again.',
                  actionLabel: 'Retry',
                  onAction: () => retryDriverDetails(ref),
                ),
              ],
              data: (driver) => [
                _Identity(driver: driver),
                const SizedBox(height: KoraSpacing.xl),
                Text('YOUR DETAILS', style: KoraText.caption),
                const SizedBox(height: KoraSpacing.sm),
                _DetailsCard(driver: driver),
                const SizedBox(height: KoraSpacing.xl),
                Text('YOUR COMPANY', style: KoraText.caption),
                const SizedBox(height: KoraSpacing.sm),
                _CompanyCard(driverId: driver.id),
              ],
            ),
            const SizedBox(height: KoraSpacing.xl),
            Text('ACCOUNT', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            const _SignOutCard(),
          ],
        ),
      ),
    );
  }
}

/// Ends the authenticated session after an explicit destructive confirmation.
class _SignOutCard extends ConsumerStatefulWidget {
  const _SignOutCard();

  @override
  ConsumerState<_SignOutCard> createState() => _SignOutCardState();
}

class _SignOutCardState extends ConsumerState<_SignOutCard> {
  bool _signingOut = false;
  String? _error;

  Future<void> _confirmAndSignOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your active voice session will end and you’ll return to the welcome screen.',
        ),
        actions: [
          TextButton(
            key: const Key('profile-sign-out-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('profile-sign-out-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: KoraColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _signingOut = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          key: const Key('profile-sign-out'),
          shadow: false,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _signingOut ? null : _confirmAndSignOut,
              borderRadius: BorderRadius.circular(KoraRadius.card),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: KoraSize.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoraSpacing.lg,
                    vertical: KoraSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        TablerIcons.logout,
                        size: KoraSize.iconMd,
                        color: KoraColors.danger,
                      ),
                      const SizedBox(width: KoraSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _signingOut ? 'Signing out…' : 'Sign out',
                              style: KoraText.label.copyWith(
                                color: KoraColors.danger,
                              ),
                            ),
                            Text(
                              'End this session on this device',
                              style: KoraText.caption,
                            ),
                          ],
                        ),
                      ),
                      if (_signingOut)
                        const SizedBox.square(
                          dimension: KoraSize.iconMd,
                          child: CircularProgressIndicator(
                            strokeWidth: KoraGlass.borderWidth,
                            color: KoraColors.danger,
                          ),
                        )
                      else
                        const Icon(
                          TablerIcons.chevronRight,
                          size: KoraSize.iconMd,
                          color: KoraColors.danger,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: KoraSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: const Key('profile-sign-out-error'),
              style: KoraText.label.copyWith(color: KoraColors.danger),
            ),
          ),
        ],
      ],
    );
  }
}

/// Avatar, name and how long the driver has ridden with Kora.
class _Identity extends StatelessWidget {
  const _Identity({required this.driver});

  final DriverProfile driver;

  @override
  Widget build(BuildContext context) {
    final since = driver.createdAt;
    return Row(
      children: [
        Container(
          width: KoraSize.avatar,
          height: KoraSize.avatar,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: KoraColors.primaryTint,
          ),
          child: const Icon(
            TablerIcons.user,
            size: KoraSize.iconLg,
            color: KoraColors.primaryLight,
          ),
        ),
        const SizedBox(width: KoraSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driver.name ?? 'Add your name',
                style: KoraText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                since == null
                    ? 'Your co-rider for every route'
                    : 'Driving with Kora since ${monthYear(since)}',
                key: const Key('profile-since'),
                style: KoraText.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "September 2026", in the device's local time.
@visibleForTesting
String monthYear(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.year}';
}

/// Editable name; the phone and vehicle are shown but changed elsewhere.
class _DetailsCard extends ConsumerStatefulWidget {
  const _DetailsCard({required this.driver});

  final DriverProfile driver;

  @override
  ConsumerState<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends ConsumerState<_DetailsCard> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.driver.name ?? '')
    ..addListener(_onNameChanged);
  _Outcome? _outcome;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // Re-evaluates the save button; the last save's result no longer
  // describes what's in the field.
  void _onNameChanged() => setState(() => _outcome = null);

  bool get _changed => _name.text.trim() != (widget.driver.name ?? '');

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _outcome = null;
    });
    _Outcome outcome;
    try {
      await ref.read(koraApiProvider).updateDriverName(_name.text.trim());
      outcome = const _Outcome.success('Name saved.');
    } on ApiException catch (e) {
      outcome = _Outcome.failure(e.message);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _outcome = outcome;
    });
    // Everything showing the name (Settings, the map card) picks it up.
    if (outcome.succeeded) ref.invalidate(driverDetailsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleModeProvider);
    return GlassCard(
      key: const Key('profile-details'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              key: const Key('profile-name'),
              label: 'Name',
              hint: 'Your full name',
              icon: TablerIcons.user,
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter the name your customers will hear.'
                  : null,
              onSubmitted: (_) => _changed && !_saving ? _save() : null,
            ),
            const SizedBox(height: KoraSpacing.md),
            PrimaryButton(
              key: const Key('profile-save'),
              label: _saving ? 'Saving…' : 'Save name',
              icon: TablerIcons.deviceFloppy,
              expand: true,
              onPressed: _changed && !_saving ? _save : null,
            ),
            if (_outcome case final outcome?) ...[
              const SizedBox(height: KoraSpacing.sm),
              _OutcomeLine(outcome, key: const Key('profile-save-result')),
            ],
            const SizedBox(height: KoraSpacing.lg),
            _ReadOnlyRow(
              key: const Key('profile-phone'),
              icon: TablerIcons.phone,
              label: 'Phone',
              value: widget.driver.phone ?? 'No phone on file',
              note: 'Your sign-in number. It can’t be changed here.',
              trailing: const Icon(
                TablerIcons.lock,
                size: KoraSize.iconSm,
                color: KoraColors.textFaint,
              ),
            ),
            const SizedBox(height: KoraSpacing.md),
            _ReadOnlyRow(
              key: const Key('profile-vehicle'),
              icon: vehicle.icon,
              label: 'Vehicle',
              value: vehicle.label,
              trailing: TextButton(
                key: const Key('profile-vehicle-settings'),
                onPressed: () => context.go(AppRoutes.settings),
                style: TextButton.styleFrom(
                  foregroundColor: KoraColors.primaryLight,
                  minimumSize: const Size(
                    KoraSize.touchTarget,
                    KoraSize.touchTarget,
                  ),
                ),
                child: Text(
                  'Change',
                  style: KoraText.label.copyWith(
                    color: KoraColors.primaryLight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The company the driver's connect code linked them to, and the code form.
class _CompanyCard extends ConsumerStatefulWidget {
  const _CompanyCard({required this.driverId});

  final String driverId;

  @override
  ConsumerState<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends ConsumerState<_CompanyCard> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  _Outcome? _outcome;
  bool _connecting = false;

  static final _codePattern = RegExp(r'^\d{6}$');

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _connecting = true;
      _outcome = null;
    });
    _Outcome outcome;
    try {
      final connection = await ref
          .read(koraApiProvider)
          .connectWithCode(_code.text.trim());
      await ref
          .read(companyConnectionStoreProvider)
          .save(widget.driverId, connection);
      outcome = _Outcome.success(
        'Connected to ${platformLabel(connection.platform)}.',
      );
    } on ApiException catch (e) {
      outcome = _Outcome.failure(e.message);
    }
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _outcome = outcome;
    });
    if (outcome.succeeded) {
      _code.clear();
      ref.invalidate(companyConnectionProvider(widget.driverId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(companyConnectionProvider(widget.driverId));
    final connection = stored.valueOrNull;
    return GlassCard(
      key: const Key('profile-company'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReadOnlyRow(
              key: const Key('profile-company-status'),
              icon: TablerIcons.buildingWarehouse,
              label: 'Company',
              value: switch (stored) {
                AsyncData(value: final c?) =>
                  'Connected to ${platformLabel(c.platform)}',
                AsyncLoading() => 'Checking your company link…',
                _ => 'Not linked to a company yet',
              },
              note: connection == null
                  ? 'Ask your dispatcher for your 6-digit connect code.'
                  : connection.connectedAt == null
                  ? null
                  : 'Linked ${_date(connection.connectedAt!)}',
            ),
            const SizedBox(height: KoraSpacing.lg),
            AuthTextField(
              key: const Key('profile-connect-code'),
              label: connection == null ? 'Connect code' : 'New connect code',
              hint: '6-digit code',
              icon: TablerIcons.key,
              controller: _code,
              enabled: !_connecting,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              validator: (value) => _codePattern.hasMatch((value ?? '').trim())
                  ? null
                  : 'Enter the 6 digits from your dispatcher.',
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: KoraSpacing.md),
            PrimaryButton(
              key: const Key('profile-connect'),
              label: _connecting ? 'Connecting…' : 'Connect company',
              icon: TablerIcons.link,
              expand: true,
              onPressed: _connecting ? null : _connect,
            ),
            if (_outcome case final outcome?) ...[
              const SizedBox(height: KoraSpacing.sm),
              _OutcomeLine(outcome, key: const Key('profile-connect-result')),
            ],
          ],
        ),
      ),
    );
  }

  static String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.day} ${monthYear(local)}';
  }
}

/// "onfleet" → "Onfleet", "my_platform" → "My platform".
@visibleForTesting
String platformLabel(String platform) {
  final words = platform.replaceAll('_', ' ').trim();
  if (words.isEmpty) return platform;
  return words[0].toUpperCase() + words.substring(1);
}

/// The result of a save or connect, shown under its button.
class _Outcome {
  const _Outcome.success(this.message) : succeeded = true;
  const _Outcome.failure(this.message) : succeeded = false;

  final String message;
  final bool succeeded;
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine(this.outcome, {super.key});

  final _Outcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = outcome.succeeded ? KoraColors.success : KoraColors.danger;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            outcome.succeeded
                ? TablerIcons.circleCheck
                : TablerIcons.alertCircle,
            size: KoraSize.iconSm,
            color: color,
          ),
          const SizedBox(width: KoraSpacing.sm),
          Expanded(
            child: Text(
              outcome.message,
              style: KoraText.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled value the driver reads but doesn't type into.
class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: KoraSize.iconMd, color: KoraColors.textFaint),
        const SizedBox(width: KoraSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: KoraText.label.copyWith(color: KoraColors.textMuted),
              ),
              Text(value, style: KoraText.body),
              if (note != null) Text(note!, style: KoraText.caption),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: KoraSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// Loading and error states: the header stays, the card explains.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyRow(icon: icon, label: title, value: message),
          if (actionLabel != null) ...[
            const SizedBox(height: KoraSpacing.md),
            PrimaryButton(
              label: actionLabel!,
              icon: TablerIcons.refresh,
              expand: true,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

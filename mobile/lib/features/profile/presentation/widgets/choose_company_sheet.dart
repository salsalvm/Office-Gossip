import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/domain/usecases/choose_company_usecase.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/presentation/tap_guard.dart';
import '../../../sign_up/presentation/widgets/company_picker_field.dart';
import '../cubit/profile_cubit.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF888992);

/// Lets a signed-in member join a listed company or request a new one, or
/// check on a pending request. Resolves to the updated user when it changed.
Future<AppUser?> showChooseCompanySheet(BuildContext context, AppUser user) =>
    showModalBottomSheet<AppUser>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => BlocProvider(
        create: (_) => sl<ProfileCubit>(),
        child: _ChooseCompanySheet(user: user),
      ),
    );

class _ChooseCompanySheet extends StatefulWidget {
  const _ChooseCompanySheet({required this.user});
  final AppUser user;

  @override
  State<_ChooseCompanySheet> createState() => _ChooseCompanySheetState();
}

class _ChooseCompanySheetState extends State<_ChooseCompanySheet> {
  final _formKey = GlobalKey<FormState>();
  final _companyName = TextEditingController();
  final _companyWebsite = TextEditingController();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  late bool _pending = widget.user.companyRequestPending;
  List<SignUpCompany> _companies = const [];
  bool _loading = false;
  String? _loadError;
  SignUpCompany? _selected;
  bool _requestNew = false;
  bool _checking = false;
  bool _registeredApplied = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    if (!_pending) _loadCompanies();
  }

  @override
  void dispose() {
    _companyName.dispose();
    _companyWebsite.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response =
          await sl<Dio>().get<List<dynamic>>(ApiEndpoints.publicCompanies);
      final companies = (response.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SignUpCompany.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        if (!companies.any((c) => c.id == _selected?.id)) _selected = null;
        _applyRegisteredCompany();
      });
    } on Object {
      if (mounted) {
        setState(() => _loadError =
            'Could not load the company list. Tap refresh to try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Starts from the company typed at sign-up: selected if it's listed now,
  /// otherwise prefilled as a new request. Applied once, before any edits.
  void _applyRegisteredCompany() {
    if (_registeredApplied) return;
    _registeredApplied = true;
    final name = widget.user.requestedCompanyName?.trim() ?? '';
    if (name.isEmpty || _selected != null) return;
    String key(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final match = _companies.where((c) => key(c.name) == key(name)).firstOrNull;
    if (match != null) {
      _selected = match;
      return;
    }
    _requestNew = true;
    _companyName.text = name;
    _companyWebsite.text = widget.user.requestedCompanyWebsite ?? '';
  }

  void _setRequestNew(bool value, {String prefill = ''}) {
    setState(() {
      _requestNew = value;
      _autovalidate = AutovalidateMode.disabled;
      if (value && prefill.isNotEmpty) _companyName.text = prefill;
    });
  }

  Future<void> _checkStatus() async {
    setState(() {
      _checking = true;
      _statusMessage = null;
    });
    final latest = await context.read<ProfileCubit>().refresh();
    if (!mounted) return;
    setState(() => _checking = false);
    if (latest?.company != null) {
      Navigator.of(context).pop(latest);
    } else if (latest != null && !latest.companyRequestPending) {
      setState(() {
        _pending = false;
        _registeredApplied = true;
        _statusMessage =
            'Your request was not approved. Choose another company below.';
      });
      _loadCompanies();
    } else {
      setState(() => _statusMessage =
          'Still waiting for approval. We’ll let you know once it’s approved.');
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final website = _companyWebsite.text.trim();
    final params = _requestNew
        ? ChooseCompanyParams.request(_companyName.text.trim(),
            companyWebsite: website.isEmpty ? null : website)
        : ChooseCompanyParams.join(_selected!.id);
    final user = await context.read<ProfileCubit>().chooseCompany(params);
    if (user != null && mounted) Navigator.of(context).pop(user);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          final saving = state.status == ProfileStatus.saving;
          final error =
              state.status == ProfileStatus.failure ? state.message : null;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: SingleChildScrollView(
              child: _pending
                  ? _buildPending()
                  : _buildPicker(saving: saving, error: error),
            ),
          );
        },
      );

  Widget _heading(String title, String detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR COMPANY',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: _muted)),
          const SizedBox(height: 6),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text(detail,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
          const SizedBox(height: 18),
        ],
      );

  Widget _buildPending() {
    final name = widget.user.pendingCompanyName ?? 'your company';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Waiting for approval',
            'You asked to bring “$name” to Office Gossip. Our team is reviewing it, and you can post as soon as it’s approved.'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF5E1A6)),
          ),
          child: Row(children: [
            const Icon(Icons.schedule_rounded, color: Color(0xFFB07D00)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Text('Pending admin approval',
                        style: TextStyle(fontSize: 12, color: _muted)),
                  ]),
            ),
          ]),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 12),
          AuthMessageBanner(message: _statusMessage!, isError: false),
        ],
        const SizedBox(height: 18),
        AuthSubmitButton(
            label: 'Check status',
            loading: _checking,
            onPressed: TapGuard.wrap(_checkStatus)),
        TextButton(
            onPressed: TapGuard.wrap(() => Navigator.of(context).pop()),
            child: const Text('Close')),
      ],
    );
  }

  Widget _buildPicker({required bool saving, String? error}) => Form(
        key: _formKey,
        autovalidateMode: _autovalidate,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('Choose your company',
                'Join your company community to see your coworkers’ posts and start sharing.'),
            if (_requestNew) ...[
              AuthTextField(
                controller: _companyName,
                label: 'Company name',
                icon: Icons.business_outlined,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.organizationName],
                enabled: !saving,
                validator: AuthValidators.company,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _companyWebsite,
                label: 'Company website (optional)',
                icon: Icons.language_outlined,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.url],
                hintText: defaultCompanyDomain(_companyName.text).isNotEmpty
                    ? defaultCompanyDomain(_companyName.text)
                    : 'yourcompany.com',
                helperText: _companyWebsite.text.trim().isNotEmpty
                    ? 'We’ll use this website for your company.'
                    : defaultCompanyDomain(_companyName.text).isNotEmpty
                        ? 'Leave blank to use ${defaultCompanyDomain(_companyName.text)}.'
                        : 'Leave blank and we’ll use your company name + .com.',
                enabled: !saving,
                validator: AuthValidators.companyWebsite,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              const Text(
                  'We’ll send this company to the Office Gossip team for review. You can post once it’s approved.',
                  style: TextStyle(fontSize: 12.5, color: _muted)),
            ] else
              CompanyPickerField(
                companies: _companies,
                selected: _selected,
                loading: _loading,
                loadError: _loadError,
                enabled: !saving,
                onRefresh: _loadCompanies,
                onSelected: (company) => setState(() => _selected = company),
                onNotListed: (query) => _setRequestNew(true, prefill: query),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: _accent),
                onPressed: saving ? null : () => _setRequestNew(!_requestNew),
                child: Text(_requestNew
                    ? '← Choose a listed company'
                    : 'My company isn’t listed'),
              ),
            ),
            if (_statusMessage != null) ...[
              AuthMessageBanner(message: _statusMessage!, isError: false),
              const SizedBox(height: 12),
            ],
            if (error != null) ...[
              AuthMessageBanner(message: error),
              const SizedBox(height: 12),
            ],
            AuthSubmitButton(
                label: _requestNew ? 'Request company' : 'Join company',
                loading: saving,
                onPressed: TapGuard.wrap(_submit)),
          ],
        ),
      );
}

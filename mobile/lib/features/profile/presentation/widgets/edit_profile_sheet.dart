import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';
import '../../../../core/di/injection_container.dart';
import '../cubit/profile_cubit.dart';
import '../../../../core/presentation/tap_guard.dart';

/// Opens the edit sheet; resolves to `true` when the profile was saved.
Future<bool> showEditProfileSheet(BuildContext context, AppUser user) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => BlocProvider(
      create: (_) => sl<ProfileCubit>(),
      child: EditProfileSheet(user: user),
    ),
  );
  return saved ?? false;
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key, required this.user});
  final AppUser user;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);
  late final _role = TextEditingController(text: widget.user.roleTitle ?? '');
  late final _bio = TextEditingController(text: widget.user.bio ?? '');
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    String? optional(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final saved = await context.read<ProfileCubit>().save(
          displayName: _name.text.trim(),
          roleTitle: optional(_role),
          bio: optional(_bio),
        );
    if (saved && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          final saving = state.status == ProfileStatus.saving;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidate,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit profile',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text(
                        'Coworkers see your name and role on posts you share publicly.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF888992))),
                    const SizedBox(height: 20),
                    AuthTextField(
                      controller: _name,
                      label: 'Display name *',
                      icon: Icons.person_outline,
                      textCapitalization: TextCapitalization.words,
                      enabled: !saving,
                      validator: AuthValidators.name,
                    ),
                    const SizedBox(height: 14),
                    AuthTextField(
                      controller: _role,
                      label: 'Role / title',
                      icon: Icons.badge_outlined,
                      helperText: 'Optional, e.g. Product Designer',
                      textCapitalization: TextCapitalization.words,
                      enabled: !saving,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _bio,
                      enabled: !saving,
                      maxLines: 3,
                      maxLength: 160,
                      textCapitalization: TextCapitalization.sentences,
                      decoration:
                          authInputDecoration('Bio', Icons.notes_outlined)
                              .copyWith(helperText: 'Optional'),
                    ),
                    if (state.status == ProfileStatus.failure &&
                        state.message != null) ...[
                      const SizedBox(height: 8),
                      AuthMessageBanner(message: state.message!),
                    ],
                    const SizedBox(height: 16),
                    AuthSubmitButton(
                        label: 'Save changes',
                        loading: saving,
                        onPressed: TapGuard.wrap(_save)),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

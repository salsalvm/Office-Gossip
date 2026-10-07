import 'package:flutter/material.dart';

import '../../../../core/auth/presentation/widgets/auth_form_components.dart';

class SignUpCompany {
  const SignUpCompany({required this.id, required this.name});

  factory SignUpCompany.fromJson(Map<String, dynamic> json) =>
      SignUpCompany(id: '${json['id']}', name: '${json['name'] ?? ''}');

  final String id;
  final String name;
}

/// Searchable picker over the active companies, with a refresh action and an
/// escape hatch for members whose company isn't listed yet.
class CompanyPickerField extends StatelessWidget {
  const CompanyPickerField({
    super.key,
    required this.companies,
    required this.selected,
    required this.loading,
    required this.loadError,
    required this.enabled,
    required this.onSelected,
    required this.onRefresh,
    required this.onNotListed,
    this.serverError,
  });

  final List<SignUpCompany> companies;
  final SignUpCompany? selected;
  final bool loading;
  final String? loadError;
  final bool enabled;
  final ValueChanged<SignUpCompany> onSelected;
  final VoidCallback onRefresh;

  /// Called with the search text (if any) so it can prefill the request form.
  final ValueChanged<String> onNotListed;
  final String? serverError;

  Future<void> _open(BuildContext context, FormFieldState<String> field) async {
    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) =>
          _CompanySearchSheet(companies: companies, selected: selected),
    );
    if (result == null) return;
    final company = result.company;
    if (company != null) {
      onSelected(company);
      field.didChange(company.id);
    } else {
      onNotListed(result.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = loading
        ? 'Loading companies…'
        : companies.isEmpty
            ? 'No companies available'
            : 'Select your company';
    final canOpen = enabled && !loading && companies.isNotEmpty;

    return FormField<String>(
      validator: (_) => selected == null ? 'Choose your company' : null,
      builder: (field) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canOpen ? () => _open(context, field) : null,
        child: InputDecorator(
          isEmpty: selected == null,
          decoration:
              authInputDecoration('Company', Icons.business_outlined).copyWith(
            enabled: enabled,
            hintText: hint,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: field.errorText ?? serverError ?? loadError,
            errorMaxLines: 2,
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              if (canOpen)
                const Icon(Icons.expand_more_rounded, color: Color(0xFF777880)),
              IconButton(
                tooltip: 'Refresh company list',
                onPressed: enabled && !loading ? onRefresh : null,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
            ]),
          ),
          child: selected == null
              ? null
              : Text(selected!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }
}

class _PickerResult {
  const _PickerResult.company(SignUpCompany this.company) : query = '';
  const _PickerResult.notListed(this.query) : company = null;
  final SignUpCompany? company;
  final String query;
}

class _CompanySearchSheet extends StatefulWidget {
  const _CompanySearchSheet({required this.companies, required this.selected});
  final List<SignUpCompany> companies;
  final SignUpCompany? selected;

  @override
  State<_CompanySearchSheet> createState() => _CompanySearchSheetState();
}

class _CompanySearchSheetState extends State<_CompanySearchSheet> {
  static const _accent = Color(0xFF7357E8);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.companies
        : widget.companies
            .where((company) => company.name.toLowerCase().contains(query))
            .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Find your company',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF292A30))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) => setState(() => _query = value),
              decoration: authInputDecoration('Search companies', Icons.search)
                  .copyWith(
                      labelText: null,
                      hintText: 'Search companies',
                      prefixIcon: const Icon(Icons.search, size: 20)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No companies match “${_query.trim()}”.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF888992))),
                    ),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final company = matches[index];
                      final isSelected = company.id == widget.selected?.id;
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFEFEBFF),
                          child: Text(
                              company.name.isEmpty
                                  ? '?'
                                  : company.name[0].toUpperCase(),
                              style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ),
                        title: Text(company.name),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _accent)
                            : null,
                        onTap: () => Navigator.pop(
                            context, _PickerResult.company(company)),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEDEB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextButton.icon(
              onPressed: () => Navigator.pop(
                  context, _PickerResult.notListed(_query.trim())),
              icon: const Icon(Icons.add_business_outlined, size: 20),
              label: Text(_query.trim().isEmpty || matches.isNotEmpty
                  ? 'My company isn’t listed'
                  : 'Request “${_query.trim()}”'),
            ),
          ),
        ]),
      ),
    );
  }
}

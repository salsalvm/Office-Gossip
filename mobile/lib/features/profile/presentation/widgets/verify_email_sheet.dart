import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_endpoints.dart';

const _ink = Color(0xFF1F1D2B);
const _accent = Color(0xFF7357E8);
const _muted = Color(0xFF7B7888);

/// Emails a one-time code and checks it. Resolves to true once verified.
Future<bool> showVerifyEmailSheet(BuildContext context, String email) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, 24 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: VerifyEmailForm(
            email: email, onVerified: () => Navigator.pop(sheet, true)),
      ),
    ) ??
    false;

/// Email OTP verification. With [autoSend] off, a "Verify email" button
/// sends the code first and the code box appears after it.
class VerifyEmailForm extends StatefulWidget {
  const VerifyEmailForm({
    super.key,
    required this.email,
    required this.onVerified,
    this.autoSend = true,
  });
  final String email;
  final VoidCallback onVerified;
  final bool autoSend;

  @override
  State<VerifyEmailForm> createState() => _VerifyEmailFormState();
}

class _VerifyEmailFormState extends State<VerifyEmailForm> {
  final _code = TextEditingController();
  late bool _codeSent = widget.autoSend;
  bool _sending = false;
  bool _checking = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  Dio get _dio => sl<Dio>();

  @override
  void initState() {
    super.initState();
    if (widget.autoSend) _send();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String _message(Object error, String fallback) =>
      error is DioException ? AppException.fromDio(error).message : fallback;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response =
          await _dio.post<Map<String, dynamic>>(ApiEndpoints.meEmailSendOtp);
      if (!mounted) return;
      if (response.data?['emailVerified'] == true) {
        widget.onVerified();
        return;
      }
      setState(() => _codeSent = true);
      _startCooldown();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error =
            _message(error, 'Could not send the code. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await _dio
          .post<dynamic>(ApiEndpoints.meEmailVerifyOtp, data: {'code': code});
      if (mounted) widget.onVerified();
    } on Object catch (error) {
      if (mounted) {
        setState(() =>
            _error = _message(error, 'That code is invalid or has expired.'));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: const Color(0xFFEFEBFF),
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.mark_email_unread_outlined,
              color: Color(0xFF5B45D1)),
        ),
        const SizedBox(height: 14),
        const Text('Verify your email',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: !_codeSent && !_sending
                    ? 'We’ll email a one-time code to '
                    : _sending && !_codeSent
                        ? 'Sending a code to '
                        : 'Enter the code we sent to '),
            TextSpan(
                text: widget.email,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          ]),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, height: 1.4, color: _muted),
        ),
        const SizedBox(height: 18),
        if (!_codeSent) ...[
          if (_error != null) ...[
            Text(_error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Color(0xFFC2453D), fontSize: 12.5)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.mark_email_read_outlined, size: 20),
              label: Text(_sending ? 'Sending code…' : 'Verify email',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ] else ...[
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _verify(),
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '••••••',
              filled: true,
              fillColor: const Color(0xFFF8F7FC),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Color(0xFFC2453D), fontSize: 12.5)),
          ],
          const SizedBox(height: 4),
          TextButton(
            onPressed: _resendIn > 0 || _sending || _checking ? null : _send,
            child: Text(
                _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code'),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _checking || _sending || _code.text.length != 6
                  ? null
                  : _verify,
              child: _checking
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Verify',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]);
}

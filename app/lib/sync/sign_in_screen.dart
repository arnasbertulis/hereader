import 'package:flutter/material.dart';

import 'api_client.dart';

/// Sign in or create an account.
///
/// Reachable from the library and always skippable. Reading works fully
/// signed out; an account only adds syncing a position between devices, and
/// blocking a reader from their books to collect an email would be a poor
/// trade.
class SignInScreen extends StatefulWidget {
  final ApiClient api;

  const SignInScreen({super.key, required this.api});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.contains('@') && _password.text.length >= 8 && !_busy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_registering) {
        await widget.api.register(_email.text.trim(), _password.text);
      } else {
        await widget.api.logIn(_email.text.trim(), _password.text);
      }

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on NetworkException {
      setState(() => _error = 'Could not reach the server. Try again later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_registering ? 'Create an account' : 'Sign in'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sync your place in a book',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'An account syncs reading positions and settings between '
                    'your devices. Books themselves stay on each device.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _canSubmit ? _submit() : null,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      helperText: _registering ? 'At least 8 characters' : null,
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_registering ? 'Create account' : 'Sign in'),
                  ),

                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                          }),
                    child: Text(
                      _registering
                          ? 'I already have an account'
                          : 'Create an account instead',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

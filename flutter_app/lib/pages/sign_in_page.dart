import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/shopify_config.dart';

enum _AuthAction { none, login, signup }

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _showSignUpForm = false;

  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  final _loginFormKey = GlobalKey<FormState>();

  final _signUpFormKey = GlobalKey<FormState>();
  final _signUpFirstNameCtrl = TextEditingController();
  final _signUpLastNameCtrl = TextEditingController();
  final _signUpEmailCtrl = TextEditingController();
  final _signUpPasswordCtrl = TextEditingController();
  final _signUpConfirmCtrl = TextEditingController();

  _AuthAction _pendingAction = _AuthAction.none;
  bool _showPass = false;
  bool _showSignUpPass = false;
  bool _showSignUpConfirm = false;
  String? _loginError;
  String? _signUpError;

  String get _shopDomainPreview => ShopifyConfig.domain;

  bool get _isBusy => _pendingAction != _AuthAction.none;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    _signUpFirstNameCtrl.dispose();
    _signUpLastNameCtrl.dispose();
    _signUpEmailCtrl.dispose();
    _signUpPasswordCtrl.dispose();
    _signUpConfirmCtrl.dispose();
    super.dispose();
  }

  String _messageFromFunctionException(FunctionException error) {
    final details = error.details;
    if (details is String && details.isNotEmpty) return details;
    if (details is Map) {
      final message = details['message'];
      if (message is String && message.isNotEmpty) return message;
      final errorMessage = details['error'];
      if (errorMessage is String && errorMessage.isNotEmpty) {
        return errorMessage;
      }
    }
    return 'Action impossible (code ${error.status}).';
  }

  Future<void> _signInWithShopifyAccount() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() {
      _pendingAction = _AuthAction.login;
      _loginError = null;
      _signUpError = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'shopify-login',
        body: <String, dynamic>{
          'email': emailCtrl.text.trim(),
          'password': passCtrl.text,
        },
      );

      final payload = response.data;
      if (payload is! Map) {
        throw const FormatException(
            'Réponse inattendue du service de connexion.');
      }

      final sessionJson = Map<String, dynamic>.from(payload);
      final refreshToken = sessionJson['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const FormatException(
            'Session invalide (refresh token manquant).');
      }

      await Supabase.instance.client.auth.setSession(refreshToken);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecté ✅')),
      );
    } on FunctionException catch (error) {
      final message = _messageFromFunctionException(error);
      final normalized = message.toLowerCase();
      if (normalized.contains("already been registered") ||
          normalized.contains("already exists")) {
        setState(
          () => _loginError = "Mot de passe invalide pour cet e-mail.",
        );
      } else if (normalized.contains("invalid") &&
          normalized.contains("password")) {
        setState(
          () => _loginError = "Mot de passe invalide pour cet e-mail.",
        );
      } else {
        setState(() => _loginError = message);
      }
    } on AuthException catch (error) {
      setState(() => _loginError = error.message);
    } on FormatException catch (error) {
      setState(() => _loginError = error.message);
    } catch (error) {
      setState(() => _loginError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _pendingAction = _AuthAction.none);
      }
    }
  }

  Future<void> _signUpWithShopifyAccount() async {
    final signupValid = _signUpFormKey.currentState?.validate() ?? false;
    if (!signupValid) return;

    setState(() {
      _pendingAction = _AuthAction.signup;
      _signUpError = null;
      _loginError = null;
    });
    final body = <String, dynamic>{
      'email': _signUpEmailCtrl.text.trim(),
      'password': _signUpPasswordCtrl.text,
      'firstName': _signUpFirstNameCtrl.text.trim(),
      'lastName': _signUpLastNameCtrl.text.trim(),
      'country': 'CA',
      'phone': null,
      'address1': null,
      'city': null,
      'province': null,
      'postalCode': null,
    };

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'shopify-signup',
        body: body,
      );

      final payload = response.data;
      if (payload is! Map) {
        throw const FormatException(
            'Réponse inattendue du service d’inscription.');
      }

      final sessionJson = Map<String, dynamic>.from(payload);
      final refreshToken = sessionJson['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const FormatException(
            'Session invalide (refresh token manquant).');
      }

      await Supabase.instance.client.auth.setSession(refreshToken);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte créé et connecté ✅')),
      );

      setState(() {
        _showSignUpForm = false;
      });

      _signUpFirstNameCtrl.clear();
      _signUpLastNameCtrl.clear();
      _signUpEmailCtrl.clear();
      _signUpPasswordCtrl.clear();
      _signUpConfirmCtrl.clear();
    } on FunctionException catch (error) {
      setState(() => _signUpError = _messageFromFunctionException(error));
    } on AuthException catch (error) {
      setState(() => _signUpError = error.message);
    } on FormatException catch (error) {
      setState(() => _signUpError = error.message);
    } catch (error) {
      setState(() => _signUpError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _pendingAction = _AuthAction.none);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 96,
        title: const Text('Connexion Logtek G&I'),
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Image.asset(
            'assets/images/logtek_logo_flat.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logtek_logo_flat.png',
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Bienvenue chez Logtek',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _showSignUpForm
                            ? _buildSignUpForm(theme)
                            : _buildLoginForm(theme),
                      ),
                      const SizedBox(height: 16),
                      if (!_showSignUpForm)
                        Text(
                          'Déjà client logtek.ca ? Utilise les champs email et mot de passe ci-dessus pour te connecter.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withAlpha(180),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      key: const ValueKey('login_form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Form(
          key: _loginFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Email requis';
                  if (!text.contains('@')) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    tooltip: _showPass ? 'Masquer' : 'Afficher',
                    onPressed: () => setState(() => _showPass = !_showPass),
                    icon: Icon(
                      _showPass ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Mot de passe requis';
                  }
                  if ((value ?? '').length < 6) {
                    return '6 caractères minimum';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Boutique (visuel): $_shopDomainPreview',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.textTheme.bodySmall?.color?.withAlpha(180),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_loginError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _loginError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isBusy ? null : _signInWithShopifyAccount,
                  child: _pendingAction == _AuthAction.login
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Se connecter'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _isBusy ? null : _openShopifyPasswordReset,
              child: const Text('Mot de passe oublié ?'),
            ),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () => setState(() => _showSignUpForm = true),
              child: const Text('Créer un compte'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignUpForm(ThemeData theme) {
    return Column(
      key: const ValueKey('signup_form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Créer un compte logtek.ca + G&I',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Un compte sera créé à la fois sur logtek.ca (Shopify) et dans Logtek G&I.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Form(
          key: _signUpFormKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _signUpFirstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Prénom',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Prénom requis';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _signUpLastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nom',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Nom requis';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _signUpEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Email requis';
                  if (!text.contains('@')) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _signUpPasswordCtrl,
                obscureText: !_showSignUpPass,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showSignUpPass = !_showSignUpPass),
                    icon: Icon(_showSignUpPass
                        ? Icons.visibility_off
                        : Icons.visibility),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').trim().length < 8) {
                    return 'Au moins 8 caractères';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _signUpConfirmCtrl,
                obscureText: !_showSignUpConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                        () => _showSignUpConfirm = !_showSignUpConfirm),
                    icon: Icon(_showSignUpConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                  ),
                ),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) {
                    return 'Confirmation requise';
                  }
                  if (text != _signUpPasswordCtrl.text) {
                    return 'Les mots de passe ne correspondent pas';
                  }
                  return null;
                },
              ),
              if (_signUpError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _signUpError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _pendingAction == _AuthAction.signup
                      ? null
                      : _signUpWithShopifyAccount,
                  child: _pendingAction == _AuthAction.signup
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Créer mon compte'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed:
                _isBusy ? null : () => setState(() => _showSignUpForm = false),
            child: const Text('Déjà un compte ? Se connecter'),
          ),
        ),
      ],
    );
  }

  Future<void> _openShopifyPasswordReset() async {
    final domain = ShopifyConfig.domain.trim();
    if (domain.isEmpty) {
      setState(
        () => _loginError =
            "Impossible d’ouvrir la réinitialisation : domaine Shopify manquant.",
      );
      return;
    }

    final uri = Uri.https(domain, '/account/login', {'reset': 'true'});
    final success = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!success && mounted) {
      setState(
        () => _loginError =
            "Impossible d’ouvrir la page de réinitialisation Shopify.",
      );
    }
  }
}

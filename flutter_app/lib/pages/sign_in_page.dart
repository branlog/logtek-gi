import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/shopify_config.dart';

class _AddressSuggestion {
  const _AddressSuggestion({required this.description, this.placeId});

  final String description;
  final String? placeId;
}

const Map<String, String> _provinceOptions = {
  'AB': 'Alberta',
  'BC': 'Colombie-Britannique',
  'MB': 'Manitoba',
  'NB': 'Nouveau-Brunswick',
  'NL': 'Terre-Neuve-et-Labrador',
  'NS': 'Nouvelle-Écosse',
  'NT': 'Territoires du Nord-Ouest',
  'NU': 'Nunavut',
  'ON': 'Ontario',
  'PE': 'Île-du-Prince-Édouard',
  'QC': 'Québec',
  'SK': 'Saskatchewan',
  'YT': 'Yukon',
};

const List<String> _addressSamples = [
  '123 Rue Principale, Montréal, QC',
  '456 Avenue du Parc, Québec, QC',
  '789 Boulevard René-Lévesque, Montréal, QC',
  '25 Chemin de la Gare, Laval, QC',
  '1000 Rue Sherbrooke Ouest, Montréal, QC',
  '350 Boulevard Charest Ouest, Québec, QC',
  '200 Rue Saint-Joseph, Gatineau, QC',
  '12 Rue King, Sherbrooke, QC',
  '77 Rue Principale Nord, Granby, QC',
  '415 Rue Saint-Paul, Trois-Rivières, QC',
];

enum _AuthAction { none, login, signup }

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _showSignUpForm = false;
  String? _signUpProvince;

  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  final _loginFormKey = GlobalKey<FormState>();

  final _signUpFormKey = GlobalKey<FormState>();
  final _signUpFirstNameCtrl = TextEditingController();
  final _signUpLastNameCtrl = TextEditingController();
  final _signUpPhoneCtrl = TextEditingController();
  final _signUpAddressCtrl = TextEditingController();
  final _signUpCityCtrl = TextEditingController();
  final _signUpPostalCtrl = TextEditingController();

  _AuthAction _pendingAction = _AuthAction.none;
  bool _showPass = false;
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
    _signUpPhoneCtrl.dispose();
    _signUpAddressCtrl.dispose();
    _signUpCityCtrl.dispose();
    _signUpPostalCtrl.dispose();
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
    final loginValid = _loginFormKey.currentState?.validate() ?? false;
    final signupValid = _signUpFormKey.currentState?.validate() ?? false;
    if (!loginValid || !signupValid) return;

    setState(() {
      _pendingAction = _AuthAction.signup;
      _signUpError = null;
      _loginError = null;
    });

    final province = (_signUpProvince ?? '').trim();
    final body = <String, dynamic>{
      'email': emailCtrl.text.trim(),
      'password': passCtrl.text,
      'firstName': _signUpFirstNameCtrl.text.trim(),
      'lastName': _signUpLastNameCtrl.text.trim(),
      'phone': _signUpPhoneCtrl.text.trim(),
      'address1': _signUpAddressCtrl.text.trim(),
      'city': _signUpCityCtrl.text.trim(),
      'province': province,
      'postalCode': _signUpPostalCtrl.text.trim().toUpperCase(),
      'country': 'CA',
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
        _signUpProvince = null;
      });

      _signUpFirstNameCtrl.clear();
      _signUpLastNameCtrl.clear();
      _signUpPhoneCtrl.clear();
      _signUpAddressCtrl.clear();
      _signUpCityCtrl.clear();
      _signUpPostalCtrl.clear();
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
                                  onPressed: () => setState(
                                    () => _showPass = !_showPass,
                                  ),
                                  icon: Icon(
                                    _showPass
                                        ? Icons.visibility_off
                                        : Icons.visibility,
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
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withValues(alpha: 0.8),
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
                                style:
                                    TextStyle(color: theme.colorScheme.error),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed:
                                    _isBusy ? null : _signInWithShopifyAccount,
                                child: _pendingAction == _AuthAction.login
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Se connecter'),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _isBusy ? null : _openShopifyPasswordReset,
                                child: const Text('Mot de passe oublié ?'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Divider(
                        color: theme.colorScheme.surfaceContainerHighest,
                        height: 1,
                      ),
                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: _isBusy
                            ? null
                            : () {
                                setState(
                                    () => _showSignUpForm = !_showSignUpForm);
                              },
                        icon: Icon(
                          _showSignUpForm
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        label: Text(
                          _showSignUpForm
                              ? 'Masquer la création de compte'
                              : 'Créer un compte logtek.ca + G&I',
                        ),
                      ),
                      AnimatedCrossFade(
                        crossFadeState: _showSignUpForm
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 250),
                        firstChild: const SizedBox.shrink(),
                        secondChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText: 'Prénom',
                                            prefixIcon:
                                                Icon(Icons.badge_outlined),
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
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText: 'Nom',
                                            prefixIcon:
                                                Icon(Icons.badge_outlined),
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
                                    controller: _signUpPhoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Téléphone',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Téléphone requis';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _AddressAutocompleteField(
                                    controller: _signUpAddressCtrl,
                                    enabled: !_isBusy,
                                    labelText: 'Adresse (numéro et rue)',
                                    onQuery: _fetchAddressSuggestions,
                                    onSuggestionSelected: (suggestion) async {
                                      await _applyAddressSuggestion(suggestion);
                                    },
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Adresse requise';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _signUpCityCtrl,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText: 'Ville',
                                            prefixIcon:
                                                Icon(Icons.location_city),
                                          ),
                                          validator: (value) {
                                            final text = value?.trim() ?? '';
                                            if (text.isEmpty) {
                                              return 'Ville requise';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _signUpProvince,
                                          decoration: const InputDecoration(
                                            labelText: 'Province',
                                            prefixIcon:
                                                Icon(Icons.map_outlined),
                                          ),
                                          isExpanded: true,
                                          items: _provinceOptions.entries
                                              .map((entry) =>
                                                  DropdownMenuItem<String>(
                                                    value: entry.key,
                                                    child: Text(
                                                        '${entry.key} • ${entry.value}'),
                                                  ))
                                              .toList(),
                                          onChanged: _isBusy
                                              ? null
                                              : (value) {
                                                  setState(() =>
                                                      _signUpProvince = value);
                                                },
                                          validator: (value) {
                                            if ((value ?? '').isEmpty) {
                                              return 'Province requise';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _signUpPostalCtrl,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      labelText: 'Code postal',
                                      prefixIcon: Icon(Icons.local_post_office),
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Code postal requis';
                                      }
                                      return null;
                                    },
                                  ),
                                  if (_signUpError != null) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _signUpError!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonal(
                                      onPressed: _isBusy
                                          ? null
                                          : _signUpWithShopifyAccount,
                                      child: _pendingAction ==
                                              _AuthAction.signup
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Créer mon compte'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Déjà client logtek.ca ? Utilise les champs email et mot de passe ci-dessus pour te connecter.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.textTheme.bodySmall?.color?.withAlpha(180),
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

  Future<List<_AddressSuggestion>> _fetchAddressSuggestions(
      String query) async {
    final trimmed = query.trim();

    final favorites = _addressSamples
        .where(
            (address) => address.toLowerCase().contains(trimmed.toLowerCase()))
        .map((address) =>
            _AddressSuggestion(description: address, placeId: null))
        .take(10)
        .toList();

    if (trimmed.length < 3) {
      return favorites;
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'google-places-autocomplete',
        body: <String, dynamic>{
          'query': trimmed,
          'country': 'CA',
          'language': 'fr',
        },
      );

      final payload = response.data;
      if (payload is List) {
        final suggestions = payload
            .whereType<Map>()
            .map((item) => _AddressSuggestion(
                  description: (item['description'] ?? '').toString(),
                  placeId: (item['placeId'] ?? item['place_id'])?.toString(),
                ))
            .where((suggestion) => suggestion.description.isNotEmpty)
            .toList();

        if (suggestions.isNotEmpty) {
          return suggestions;
        }
      }
    } catch (error) {
      debugPrint('adresse autocomplete error: $error');
    }

    return favorites;
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

  Future<void> _applyAddressSuggestion(_AddressSuggestion suggestion) async {
    setState(() {
      _signUpAddressCtrl.text = suggestion.description;
    });

    if (suggestion.placeId == null || suggestion.placeId!.isEmpty) {
      return;
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'google-place-details',
        body: <String, dynamic>{
          'placeId': suggestion.placeId,
          'language': 'fr',
        },
      );

      final payload = response.data;
      if (payload is! Map) return;

      setState(() {
        final address1 = (payload['address1'] ?? '') as String?;
        final city = (payload['city'] ?? '') as String?;
        final province = (payload['province'] ?? '') as String?;
        final postal = (payload['postalCode'] ?? '') as String?;

        if (address1 != null && address1.isNotEmpty) {
          _signUpAddressCtrl.text = address1;
        }
        if (city != null && city.isNotEmpty) {
          _signUpCityCtrl.text = city;
        }
        if (postal != null && postal.isNotEmpty) {
          _signUpPostalCtrl.text = postal.toUpperCase();
        }
        if (province != null && province.isNotEmpty) {
          final code = province.toUpperCase();
          if (_provinceOptions.containsKey(code)) {
            _signUpProvince = code;
          }
        }
      });
    } catch (error) {
      debugPrint('adresse details error: $error');
    }
  }
}

class _AddressAutocompleteField extends StatefulWidget {
  const _AddressAutocompleteField({
    required this.controller,
    required this.onQuery,
    required this.onSuggestionSelected,
    required this.validator,
    this.enabled = true,
    this.labelText,
  });

  final TextEditingController controller;
  final Future<List<_AddressSuggestion>> Function(String query) onQuery;
  final Future<void> Function(_AddressSuggestion suggestion)
      onSuggestionSelected;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final String? labelText;

  @override
  State<_AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<_AddressAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  final List<_AddressSuggestion> _favorites = _addressSamples
      .map((address) => _AddressSuggestion(description: address, placeId: null))
      .toList();

  List<_AddressSuggestion> _options = const [];
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleQuery(String query) {
    if (!widget.enabled) return;
    final normalized = query.trim();
    if (_lastQuery == normalized) return;
    _lastQuery = normalized;
    _debounce?.cancel();
    if (normalized.isEmpty) {
      setState(() => _options = _favorites);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await widget.onQuery(normalized);
      if (!mounted || _lastQuery != normalized) return;
      setState(() => _options = results);
    });
  }

  Iterable<_AddressSuggestion> _buildOptions(TextEditingValue value) {
    if (!widget.enabled) {
      return const Iterable<_AddressSuggestion>.empty();
    }
    final query = value.text.trim();
    _scheduleQuery(query);
    if (query.isEmpty) {
      return _favorites;
    }
    return _options;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth;
        return RawAutocomplete<_AddressSuggestion>(
          focusNode: _focusNode,
          textEditingController: widget.controller,
          optionsBuilder: _buildOptions,
          displayStringForOption: (option) => option.description,
          onSelected: (suggestion) async {
            widget.controller.text = suggestion.description;
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
            await widget.onSuggestionSelected(suggestion);
          },
          optionsViewBuilder: (context, onSelected, options) {
            final suggestionList = options.toList(growable: false);
            if (suggestionList.isEmpty) {
              return const SizedBox.shrink();
            }
            final theme = Theme.of(context);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 260,
                    maxWidth: fieldWidth,
                  ),
                  child: SizedBox(
                    width: fieldWidth,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: suggestionList.length,
                      itemBuilder: (context, index) {
                        final suggestion = suggestionList[index];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(suggestion.description),
                          onTap: () => onSelected(suggestion),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          titleTextStyle: theme.textTheme.bodyMedium,
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.words,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: widget.labelText,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              validator: widget.validator,
            );
          },
        );
      },
    );
  }
}

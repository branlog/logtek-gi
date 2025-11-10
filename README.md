# Logtek G&I — Starter Kit

Ce dépôt contient :
- **flutter_app/** : app Flutter (Auth Firebase + Company Gate + création d’entreprise & entrepôt par défaut)
- **functions/** : Firebase Functions (Express) avec `/nlp/route` (Structured Outputs) et `/actions/execute` (squelette)

## 1) Pré-requis
- Flutter SDK
- Compte Firebase (Firestore + Auth email/mot de passe activés)
- Node 18+
- Clé OpenAI dans `functions/.env`

## 2) Setup Flutter
```bash
cd flutter_app
flutter pub get
# Générez le fichier firebase_options.dart
dart pub global activate flutterfire_cli
flutterfire configure
# Lancer en injectant les secrets Supabase :
# (export SUPABASE_URL=... && export SUPABASE_ANON_KEY=... avant)
../tool/flutter_run_env.sh
```

### Compilation iOS (IPA)
```bash
# Depuis la racine du repo
export SUPABASE_URL=...
export SUPABASE_ANON_KEY=...
./tool/flutter_build_ipa_env.sh --release
```

## 3) Setup Firebase Functions
```bash
cd functions
npm i
# créer .env à partir de .env.example
# ensuite déployer (ou utiliser emulateurs)
```

## 4) Endpoints
- `POST /api/nlp/route` → { text, companyId? } → { action, payload }
- `POST /api/actions/execute` → { action, payload, userUid } → applique l’action (MVP: CreateCompany, CreateWarehouse)

## 5) Notes
- Le schéma Structured Outputs suit un JSON Schema strict.
- Ajoutez ensuite les actions: CreateItem, AdjustIn/Out, TransferStock.
- Intégration Shopify viendra après le MVP (OAuth + webhooks).

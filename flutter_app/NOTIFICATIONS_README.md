# 🔔 Système de Notifications - Logtek G&I

## Vue d'ensemble

Ce système de notifications fournit :

- ✅ **Notifications push** via Firebase Cloud Messaging (FCM)
- ✅ **Notifications locales** pour les alertes de stock faible
- ✅ **Préférences personnalisables** par l'utilisateur
- ✅ **Heures de silence** configurables
- ✅ **Support multi-plateformes** (iOS, Android)

## Fonctionnalités

### Types de notifications

1. **Stock faible** 📦 - Quand un article atteint son seuil minimum
2. **Demandes d'achat** 📝 - Nouvelles demandes et approbations
3. **Équipement** 🔧 - Assignations et maintenance
4. **Ajustements d'inventaire** 📊 - Modifications importantes
5. **Messages d'équipe** 💬 - Communications d'équipe
6. **Alertes système** 🔔 - Mises à jour importantes

## Configuration

### 1. Configuration Firebase

#### Étape 1: Créer un projet Firebase

1. Aller sur [Firebase Console](https://console.firebase.google.com/)
2. Créer un nouveau projet ou utiliser un existant
3. Ajouter votre application iOS et/ou Android

#### Étape 2: Télécharger les fichiers de configuration

- **iOS**: Télécharger `GoogleService-Info.plist` et le placer dans
  `ios/Runner/`
- **Android**: Télécharger `google-services.json` et le placer dans
  `android/app/`

#### Étape 3: Installer FlutterFire CLI

```bash
# Installer FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurer Firebase pour votre projet
flutterfire configure
```

Cette commande va :

- Créer automatiquement `lib/config/firebase_options.dart` avec les bonnes
  valeurs
- Configurer votre projet pour iOS et Android

### 2. Configuration iOS

#### Étape 1: Capacités

1. Ouvrir `ios/Runner.xcworkspace` dans Xcode
2. Sélectionner le target "Runner"
3. Onglet "Signing & Capabilities"
4. Cliquer sur "+ Capability" et ajouter :
   - **Push Notifications**
   - **Background Modes** (cocher "Remote notifications")

#### Étape 2: Certificat APN

1. Dans Firebase Console > Projet > Paramètres > Cloud Messaging
2. Sous "APNs Certificates", uploader votre certificat .p8
   - Ou générer un nouveau certificat depuis
     [Apple Developer](https://developer.apple.com/account/resources/authkeys/list)

### 3. Configuration Android

#### Étape 1: Mettre à jour build.gradle

Le fichier `android/build.gradle` doit contenir :

```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

Le fichier `android/app/build.gradle` doit contenir :

```gradle
apply plugin: 'com.google.gms.google-services'
```

#### Étape 2: Icône de notification

Placer une icône de notification dans :

```
android/app/src/main/res/drawable/ic_notification.png
```

### 4. Configuration Supabase

#### Créer la table des tokens FCM

Exécuter le script SQL sur votre base Supabase :

```bash
supabase db push supabase/migrations/create_fcm_tokens_table.sql
```

Ou manuellement dans le SQL Editor de Supabase Dashboard.

## Utilisation

### Dans l'application

#### Accéder aux paramètres

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const NotificationSettingsPage(),
  ),
);
```

#### Envoyer une notification de test

```dart
await NotificationService.instance.testNotification();
```

#### Afficher une notification de stock faible

```dart
await NotificationService.instance.showLowStockNotification(
  itemName: 'Vis 10mm',
  currentQty: 5,
  minStock: 20,
  itemId: 'item-123',
);
```

#### Vérifier automatiquement les stocks faibles

```dart
// Dans votre logique de rafraîchissement
await NotificationService.instance.scheduleStockChecks(inventory);
```

### Backend (Fonctions Edge Supabase)

Pour envoyer des notifications push depuis le backend :

```typescript
import { createClient } from "@supabase/supabase-js";

async function sendNotificationToUser(
    userId: string,
    title: string,
    body: string,
    data: any,
) {
    const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Récupérer les tokens FCM de l'utilisateur
    const { data: tokens } = await supabase
        .from("user_fcm_tokens")
        .select("token, platform")
        .eq("user_uid", userId);

    if (!tokens || tokens.length === 0) {
        console.log("No FCM tokens found for user");
        return;
    }

    // Envoyer via Firebase Admin SDK
    const message = {
        notification: { title, body },
        data,
        tokens: tokens.map((t) => t.token),
    };

    // Utiliser Firebase Admin SDK ici
    // const response = await admin.messaging().sendMulticast(message)
}
```

## Préférences utilisateur

Les utilisateurs peuvent configurer :

- ✅ Activer/désactiver les notifications
- ✅ Choisir les types de notifications à recevoir
- ✅ Activer/désactiver le son
- ✅ Activer/désactiver les vibrations
- ✅ Définir des heures de silence (ex: 22h-7h)

Les préférences sont sauvegardées localement et synchronisées sur tous les
appareils de l'utilisateur.

## Gestion des notifications

### Écouter les clics sur notifications

```dart
NotificationService.instance.onNotificationTap.listen((data) {
  // Naviguer selon le type de notification
  final type = data['type'] as String?;
  
  if (type == 'low_stock') {
    final itemId = data['item_id'] as String?;
    // Naviguer vers la page de l'item
  }
});
```

### Obtenir le token FCM

```dart
final token = NotificationService.instance.fcmToken;
print('FCM Token: $token');
```

## Dépannage

### iOS - Notifications ne fonctionnent pas

1. Vérifier que les capacités Push Notifications sont activées
2. Vérifier que le certificat APN est bien configuré dans Firebase
3. Tester sur un appareil réel (pas le simulateur)

### Android - Notifications ne s'affichent pas

1. Vérifier que `google-services.json` est bien placé
2. Vérifier les permissions dans `AndroidManifest.xml`
3. Vérifier les logs avec `adb logcat`

### Notifications en arrière-plan ne fonctionnent pas

1. S'assurer que `FirebaseMessaging.onBackgroundMessage` est déclaré au niveau
   top
2. Utiliser `@pragma('vm:entry-point')` avant la fonction handler
3. Vérifier que Background Modes est activé (iOS)

## Structure des fichiers

```
lib/
├── services/
│   └── notification_service.dart      # Service principal de notifications
├── pages/
│   └── notification_settings_page.dart # Page de paramètres
└── config/
    └── firebase_options.dart           # Configuration Firebase

supabase/
└── migrations/
    └── create_fcm_tokens_table.sql     # Migration table FCM tokens
```

## Améliorations futures

- [ ] Notifications planifiées
- [ ] Groupement de notifications
- [ ] Actions rapides (Quick Actions)
- [ ] Rich notifications avec images
- [ ] Statistiques d'engagement
- [ ] A/B testing de messages
- [ ] Support Web Push

## Support

Pour toute question, consulter :

- [Documentation Firebase](https://firebase.google.com/docs/cloud-messaging)
- [Documentation Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)
- [Supabase Documentation](https://supabase.com/docs)

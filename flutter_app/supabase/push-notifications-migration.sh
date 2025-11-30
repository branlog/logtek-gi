#!/bin/bash

# Script pour pousser la migration des notifications vers Supabase
# Usage: ./push-notifications-migration.sh

echo "🚀 Push de la migration des notifications vers Supabase..."
echo ""

# Vérifier que Supabase CLI est installé
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI n'est pas installé"
    echo "📦 Installe-le avec: brew install supabase/tap/supabase"
    exit 1
fi

echo "✅ Supabase CLI détecté"
echo ""

# Vérifier qu'on est lié à un projet
if [ ! -f ".temp/project-ref" ]; then
    echo "⚠️  Projet Supabase non lié"
    echo "🔗 Exécute d'abord: supabase link --project-ref=ton-project-ref"
    echo ""
    read -p "Veux-tu lier un projet maintenant? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Entre ton project-ref: " project_ref
        supabase link --project-ref=$project_ref
    else
        exit 1
    fi
fi

echo "📤 Push de la migration..."
echo ""

# Pusher les migrations
supabase db push

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Migration réussie ! 🎉"
    echo ""
    echo "📱 Tu peux maintenant tester les notifications dans ton app:"
    echo "   1. Lance l'app Flutter"
    echo "   2. Va dans Plus > Profil > Paramètres de notifications"
    echo "   3. Clique sur 'Tester les notifications'"
    echo ""
    echo "💡 Pour envoyer une notification manuellement via SQL:"
    echo "   SELECT send_notification_to_user("
    echo "       'ton-user-id'::UUID,"
    echo "       'system_alert',"
    echo "       'Test',"
    echo "       'Ça fonctionne ! 🎉'"
    echo "   );"
    echo ""
else
    echo ""
    echo "❌ Erreur lors du push"
    echo "💡 Vérifie que tu es bien connecté avec: supabase status"
    exit 1
fi

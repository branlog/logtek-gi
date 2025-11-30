import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

interface NotificationRequest {
  user_id?: string
  company_id?: string
  type: string
  title: string
  body: string
  data?: Record<string, any>
  priority?: 'high' | 'normal'
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const {
      user_id,
      company_id,
      type,
      title,
      body,
      data,
      priority = 'normal',
    } = (await req.json()) as NotificationRequest

    let result

    if (user_id) {
      // Envoyer à un utilisateur spécifique
      const { data: notification, error } = await supabaseClient.rpc(
        'send_notification_to_user',
        {
          p_user_id: user_id,
          p_type: type,
          p_title: title,
          p_body: body,
          p_data: data || null,
          p_priority: priority,
        }
      )

      if (error) throw error

      result = {
        success: true,
        message: 'Notification envoyée à l\'utilisateur',
        notification_id: notification,
        recipients: 1,
      }
    } else if (company_id) {
      // Envoyer à tous les membres d'une entreprise
      const { data: count, error } = await supabaseClient.rpc(
        'send_notification_to_company',
        {
          p_company_id: company_id,
          p_type: type,
          p_title: title,
          p_body: body,
          p_data: data || null,
          p_priority: priority,
        }
      )

      if (error) throw error

      result = {
        success: true,
        message: 'Notification envoyée à l\'entreprise',
        recipients: count,
      }
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'user_id ou company_id requis',
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

/* Exemple d'utilisation:

POST https://[votre-projet].supabase.co/functions/v1/send-notification-supabase

Body:
{
  "user_id": "uuid-de-l-utilisateur",
  "type": "low_stock",
  "title": "Stock faible",
  "body": "Vis 10mm : 5 restant (min: 20)",
  "data": { "item_id": "123" },
  "priority": "high"
}

Ou pour toute une entreprise:
{
  "company_id": "uuid-de-l-entreprise",
  "type": "team_message",
  "title": "Réunion d'équipe",
  "body": "Réunion à 14h dans la salle de conférence",
  "priority": "normal"
}
*/

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
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { user_id, company_id, type, title, body, data } =
      (await req.json()) as NotificationRequest

    // Get FCM tokens for the target user(s)
    let query = supabaseClient
      .from('user_fcm_tokens')
      .select('token, platform, user_uid')

    if (user_id) {
      query = query.eq('user_uid', user_id)
    } else if (company_id) {
      // Get all users in the company
      const { data: members } = await supabaseClient
        .from('memberships')
        .select('user_uid')
        .eq('company_id', company_id)
        .eq('status', 'active')

      if (members && members.length > 0) {
        const userIds = members.map((m) => m.user_uid)
        query = query.in('user_uid', userIds)
      }
    }

    const { data: tokens, error: tokensError } = await query

    if (tokensError) {
      throw tokensError
    }

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ success: false, message: 'No FCM tokens found' }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 404,
        }
      )
    }

    // Prepare the FCM message
    const fcmTokens = tokens.map((t) => t.token)
    
    // NOTE: Pour envoyer réellement les notifications, vous devez:
    // 1. Configurer Firebase Admin SDK dans Supabase Edge Functions
    // 2. Ou utiliser l'API REST de FCM avec votre Server Key
    
    // Exemple avec l'API REST FCM (simplifié):
    const fcmServerKey = Deno.env.get('FCM_SERVER_KEY')
    
    if (!fcmServerKey) {
      console.warn('FCM_SERVER_KEY not configured, skipping actual send')
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Notification prepared but not sent (FCM not configured)',
          tokens_found: fcmTokens.length,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Send to FCM
    const fcmResponse = await fetch(
      'https://fcm.googleapis.com/fcm/send',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `key=${fcmServerKey}`,
        },
        body: JSON.stringify({
          registration_ids: fcmTokens,
          notification: {
            title,
            body,
            sound: 'default',
          },
          data: {
            type,
            ...data,
          },
          priority: 'high',
        }),
      }
    )

    const fcmResult = await fcmResponse.json()

    // Log the notification for debugging
    await supabaseClient.from('notification_logs').insert({
      type,
      title,
      body,
      target_user_id: user_id,
      target_company_id: company_id,
      tokens_sent: fcmTokens.length,
      fcm_result: fcmResult,
      sent_at: new Date().toISOString(),
    })

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Notification sent',
        tokens_sent: fcmTokens.length,
        fcm_result: fcmResult,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
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

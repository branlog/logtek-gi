import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

const SHOPIFY_DOMAIN = Deno.env.get("SHOPIFY_DOMAIN") ?? "";
const SHOPIFY_STOREFRONT_TOKEN = Deno.env.get("SHOPIFY_STOREFRONT_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const supabaseAnon = createClient(SUPABASE_URL, ANON_KEY);

const CUSTOMER_TOKEN_MUTATION = `
mutation customerAccessTokenCreate($input: CustomerAccessTokenCreateInput!) {
  customerAccessTokenCreate(input: $input) {
    customerAccessToken {
      accessToken
      expiresAt
    }
    customerUserErrors {
      code
      message
      field
    }
  }
}`;

interface LoginPayload {
  email?: string;
  password?: string;
}

async function validateWithShopify(email: string, password: string) {
  const response = await fetch(
    `https://${SHOPIFY_DOMAIN}/api/2024-04/graphql.json`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Storefront-Access-Token": SHOPIFY_STOREFRONT_TOKEN,
      },
      body: JSON.stringify({
        query: CUSTOMER_TOKEN_MUTATION,
        variables: {
          input: { email, password },
        },
      }),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Shopify API error: ${detail}`);
  }

  const data = await response.json();
  const errors = data?.data?.customerAccessTokenCreate?.customerUserErrors;
  const token = data?.data?.customerAccessTokenCreate?.customerAccessToken;

  if (errors?.length) {
    throw new Error(errors.map((e: any) => e.message).join(", "));
  }
  if (!token) {
    throw new Error("Échec de l’authentification Shopify.");
  }

  return token as { accessToken: string; expiresAt: string };
}

async function findUserByEmail(email: string) {
  let page = 1;
  const perPage = 100;

  while (true) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) {
      throw error;
    }

    const users = data?.users ?? [];
    const match = users.find((user) =>
      user.email?.toLowerCase() === email.toLowerCase()
    );
    if (match) return match;

    if (users.length < perPage) break;
    page += 1;
  }

  return null;
}

async function getOrCreateSupabaseUser(email: string) {
  const existing = await findUserByEmail(email);
  if (existing) return existing;

  const { data: created, error: createError } = await supabaseAdmin.auth.admin
    .createUser({
      email,
      password: crypto.randomUUID(), // temp password, will be replaced after Shopify validation
      email_confirm: true,
    });
  if (createError) {
    if (createError.code === "email_exists") {
      const refreshed = await findUserByEmail(email);
      if (refreshed) return refreshed;
    }
    throw createError;
  }
  return created?.user ?? await findUserByEmail(email);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (
    !SHOPIFY_DOMAIN || !SHOPIFY_STOREFRONT_TOKEN || !SUPABASE_URL ||
    !SERVICE_ROLE_KEY || !ANON_KEY
  ) {
    return new Response("Configuration incomplète.", { status: 500 });
  }

  const payload = await req.json() as LoginPayload;
  const email = payload.email?.trim().toLowerCase();
  const password = payload.password ?? "";

  if (!email || !password) {
    return new Response("email et password sont requis.", { status: 400 });
  }

  try {
    await validateWithShopify(email, password);

    const user = await getOrCreateSupabaseUser(email);
    if (!user) {
      throw new Error(
        "Impossible de créer ou récupérer l’utilisateur Supabase.",
      );
    }

    let profile: {
      first_name?: string | null;
      last_name?: string | null;
      phone?: string | null;
      address?: string | null;
      email?: string | null;
    } | null = null;

    try {
      const { data: profileRow } = await supabaseAdmin.from("user_profiles")
        .upsert({
          user_uid: user.id,
          first_name: user.user_metadata?.first_name ??
            user.user_metadata?.firstName ??
            null,
          last_name: user.user_metadata?.last_name ??
            user.user_metadata?.lastName ??
            null,
          phone: user.user_metadata?.phone ?? null,
          address: user.user_metadata?.address ?? null,
          email: user.email ?? null,
        }, { onConflict: "user_uid" })
        .select()
        .single();
      profile = profileRow ?? null;
    } catch (error) {
      console.error("shopify-login profile upsert error", error);
    }

    const metadataUpdate: Record<string, unknown> = {};
    if (profile?.first_name) metadataUpdate.first_name = profile.first_name;
    if (profile?.last_name) metadataUpdate.last_name = profile.last_name;
    if (profile?.phone) metadataUpdate.phone = profile.phone;
    if (profile?.address) metadataUpdate.address = profile.address;
    if (!profile?.email) metadataUpdate.email = user.email ?? null;

    await supabaseAdmin.auth.admin.updateUserById(user.id, {
      password,
      ...(Object.keys(metadataUpdate).length
        ? { user_metadata: { ...user.user_metadata, ...metadataUpdate } }
        : {}),
    });

    const { data: sessionData, error: signInError } = await supabaseAnon.auth
      .signInWithPassword({
        email,
        password,
      });

    if (signInError || !sessionData?.session) {
      throw signInError ?? new Error("Impossible de créer la session.");
    }

    return new Response(JSON.stringify(sessionData.session), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("shopify-login error", error);
    return new Response(
      error instanceof Error ? error.message : "Erreur inconnue",
      { status: 401 },
    );
  }
});

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10?dts";

const SUPABASE_URL: string = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY: string = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const DEFAULT_SHOP_DOMAIN: string = Deno.env.get("DEFAULT_SHOP_DOMAIN") ?? "2uvcbu-ci.myshopify.com";
const SF_TOKEN: string = Deno.env.get("SHOPIFY_STOREFRONT_TOKEN") ?? "";

type AccessTokenResp = {
  data?: {
    customerAccessTokenCreate?: {
      customerAccessToken?: { accessToken: string; expiresAt: string };
      userErrors?: Array<{ code?: string; field?: string[]; message: string }>;
    };
  };
  errors?: Array<{ message: string }>;
};

type CustomerMeResp = {
  data?: { customer?: { id: string; email: string | null } };
  errors?: Array<{ message: string }>;
};

const gql = (s: TemplateStringsArray) => s.join("");

const MUTATION_CREATE = gql`
mutation customerAccessTokenCreate($input: CustomerAccessTokenCreateInput!) {
  customerAccessTokenCreate(input: $input) {
    customerAccessToken { accessToken expiresAt }
    userErrors { code field message }
  }
}`;

const QUERY_ME = gql`
query {
  customer {
    id
    email
  }
}`;

serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response("POST only", { status: 405 });
  }

  try {
    const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return new Response(JSON.stringify({ error: "Missing Supabase JWT" }), { status: 401 });
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const {
      data: { user },
      error: userErr,
    } = await sb.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Invalid user" }), { status: 401 });
    }

    const body = await req.json().catch(() => ({}));
    const shopDomain: string = (body.shopDomain || DEFAULT_SHOP_DOMAIN).toString();
    const email: string = (body.email ?? "").toString();
    const password: string = (body.password ?? "").toString();

    if (!shopDomain || !email || !password) {
      return new Response(JSON.stringify({ error: "shopDomain/email/password required" }), { status: 400 });
    }

    const sfUrl = `https://${shopDomain}/api/2025-01/graphql.json`;

    // 1) Token
    const createRes = await fetch(sfUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Storefront-Access-Token": SF_TOKEN,
      },
      body: JSON.stringify({
        query: MUTATION_CREATE,
        variables: { input: { email, password } },
      }),
    });
    const createJson = (await createRes.json()) as AccessTokenResp;

    const token = createJson.data?.customerAccessTokenCreate?.customerAccessToken?.accessToken;
    const expiresAt = createJson.data?.customerAccessTokenCreate?.customerAccessToken?.expiresAt;

    if (!token) {
      const userErrors =
        createJson.data?.customerAccessTokenCreate?.userErrors ?? createJson.errors ?? [];
      const msg = userErrors.map((e) => e.message).join("; ") || "Failed to get token";
      return new Response(JSON.stringify({ error: msg }), { status: 400 });
    }

    // 2) Infos client (ID/email)
    const meRes = await fetch(sfUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Storefront-Access-Token": SF_TOKEN,
        "Shopify-Customer-Access-Token": token,
      },
      body: JSON.stringify({ query: QUERY_ME }),
    });
    const meJson = (await meRes.json()) as CustomerMeResp;
    const customer = meJson.data?.customer;
    if (!customer?.id) {
      return new Response(JSON.stringify({ error: "Failed to read customer profile" }), { status: 400 });
    }

    // 3) Upsert lien en respectant RLS
    const { error: upsertErr } = await sb
      .from("shopify_accounts")
      .upsert({
        user_id: user.id,
        shop_domain: shopDomain,
        customer_id: customer.id,
        customer_email: customer.email ?? email,
        access_token: token,
        expires_at: new Date(expiresAt ?? "").toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,shop_domain" });

    if (upsertErr) {
      return new Response(JSON.stringify({ error: upsertErr.message }), { status: 400 });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        shopDomain,
        customerId: customer.id,
        email: customer.email ?? email,
        expiresAt,
      }),
      { status: 200 },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
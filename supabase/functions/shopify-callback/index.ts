import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

const API_KEY = Deno.env.get("SHOPIFY_API_KEY") ?? "";
const API_SECRET = Deno.env.get("SHOPIFY_API_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUCCESS_REDIRECT = Deno.env.get("SHOPIFY_SUCCESS_REDIRECT") ??
  "https://logtek.app/shopify?status=success";
const ERROR_REDIRECT = Deno.env.get("SHOPIFY_ERROR_REDIRECT") ??
  "https://logtek.app/shopify?status=error";

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyHmac(params: URLSearchParams): Promise<boolean> {
  const receivedHmac = params.get("hmac");
  if (!receivedHmac) return false;

  const message = [...params.entries()]
    .filter(([key]) => key !== "hmac" && key !== "signature")
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join("&");

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(API_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  const calculated = toHex(signatureBuffer);

  return calculated === receivedHmac;
}

async function exchangeToken(code: string, shop: string) {
  const response = await fetch(`https://${shop}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: API_KEY,
      client_secret: API_SECRET,
      code,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Token exchange failed: ${detail}`);
  }
  return response.json() as Promise<{ access_token: string; scope?: string }>;
}

function decodeState(state: string) {
  const decoded = atob(state);
  return JSON.parse(decoded) as {
    companyId: string;
    shopDomain: string;
    issuedAt: number;
  };
}

function redirectSuccess(message?: string) {
  const url = new URL(SUCCESS_REDIRECT);
  if (message) url.searchParams.set("message", message);
  return Response.redirect(url.toString(), 302);
}

function redirectError(message?: string) {
  const url = new URL(ERROR_REDIRECT);
  if (message) url.searchParams.set("message", message);
  return Response.redirect(url.toString(), 302);
}

serve(async (req) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!API_KEY || !API_SECRET || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return redirectError("Configuration Shopify incomplète.");
  }

  const url = new URL(req.url);
  const params = url.searchParams;

  if (!(await verifyHmac(params))) {
    return redirectError("Signature invalide.");
  }

  const code = params.get("code");
  const shop = params.get("shop");
  const stateParam = params.get("state");

  if (!code || !shop || !stateParam) {
    return redirectError("Paramètres manquants.");
  }

  let state;
  try {
    state = decodeState(stateParam);
  } catch {
    return redirectError("État de connexion invalide.");
  }

  // Optionnel : on refuse les états trop anciens (>10 minutes)
  const maxAgeMs = 10 * 60 * 1000;
  if (Date.now() - state.issuedAt > maxAgeMs) {
    return redirectError("Session expirée, recommence la connexion.");
  }

  try {
    const tokenPayload = await exchangeToken(code, shop);
    const accessToken = tokenPayload.access_token;
    const scope = tokenPayload.scope ?? null;

    const { error } = await supabaseAdmin
      .from("shopify_shops")
      .upsert(
        {
          company_id: state.companyId,
          shop_domain: shop,
          access_token: accessToken,
          scope,
          status: "active",
          connected_at: new Date().toISOString(),
        },
        { onConflict: "shop_domain" },
      );

    if (error) {
      console.error("Supabase upsert error", error);
      return redirectError("Impossible d'enregistrer la boutique.");
    }

    return redirectSuccess("Boutique connectée.");
  } catch (error) {
    console.error("Shopify callback error", error);
    return redirectError("Connexion Shopify impossible.");
  }
});

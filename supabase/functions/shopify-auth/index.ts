import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const API_KEY = Deno.env.get("SHOPIFY_API_KEY") ?? "";
const SCOPES = Deno.env.get("SHOPIFY_SCOPES") ?? "";
const CALLBACK_BASE = Deno.env.get("SHOPIFY_REDIRECT_BASE")
  ?? Deno.env.get("SHOPIFY_CALLBACK_URL")
  ?? "";

type HeaderMap = Record<string, string>;

const CORS_HEADERS: HeaderMap = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS,HEAD",
  "Access-Control-Allow-Headers": "content-type",
};

function reply(
  status: number,
  body: BodyInit | null,
  extraHeaders: HeaderMap = {},
): Response {
  const headers = new Headers({ ...CORS_HEADERS, ...extraHeaders });
  return new Response(body, { status, headers });
}

function badRequest(message: string): Response {
  return reply(400, message);
}

function methodNotAllowed(): Response {
  return reply(405, "Method not allowed");
}

function buildState(companyId: string, shopDomain: string): string {
  const payload = {
    companyId,
    shopDomain,
    issuedAt: Date.now(),
  };
  return btoa(JSON.stringify(payload));
}

const missingCompanyHtml = `
<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Connexion Shopify</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; padding: 24px; background: #f6f6f7; color: #202223; }
      main { max-width: 480px; margin: 40px auto; padding: 24px; background: white; border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
      h1 { font-size: 1.4rem; margin-bottom: 0.75rem; }
      p { line-height: 1.5; margin-bottom: 1rem; }
      code { background: #f0f1f2; padding: 0.15rem 0.35rem; border-radius: 4px; }
      ol { padding-left: 1.3rem; }
    </style>
  </head>
  <body>
    <main>
      <h1>Authentification Logtek</h1>
      <p>Cette application doit être lancée depuis Logtek afin de relier une entreprise Shopify.</p>
      <ol>
        <li>Ouvre l’app Logtek et va sur <strong>Paramètres → Intégrations Shopify</strong>.</li>
        <li>Sélectionne l’entreprise à connecter puis appuie sur <strong>Connecter</strong>.</li>
        <li>Logtek t’enverra ici avec les paramètres requis pour finaliser l’installation.</li>
      </ol>
      <p>Si tu penses voir ce message par erreur, contacte notre support.</p>
    </main>
  </body>
</html>
`.trim();

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return reply(204, null);
  }

  const normalizedMethod = req.method === "HEAD" ? "GET" : req.method;
  if (normalizedMethod !== "GET" && normalizedMethod !== "POST") {
    return methodNotAllowed();
  }

  const { searchParams } = new URL(req.url);
  let companyId = searchParams.get("companyId");
  let shopDomain = searchParams.get("shop");

  if ((!companyId || !shopDomain) && normalizedMethod === "POST") {
    const contentType = req.headers.get("content-type") ?? "";
    try {
      if (contentType.includes("application/json")) {
        const body = await req.json();
        companyId ||= body?.companyId ?? body?.company_id ?? null;
        shopDomain ||= body?.shop ?? body?.shopDomain ?? null;
      } else if (contentType.includes("application/x-www-form-urlencoded")) {
        const form = await req.formData();
        companyId ||= (form.get("companyId") ?? form.get("company_id")) as
          | string
          | null;
        shopDomain ||= (form.get("shop") ?? form.get("shopDomain")) as
          | string
          | null;
      }
    } catch (error) {
      console.error("shopify-auth parse body error", error);
      return badRequest("Impossible de lire la requête Shopify.");
    }
  }

  if (!API_KEY || !SCOPES || !CALLBACK_BASE) {
    console.error(
      "Missing Shopify config",
      { hasApiKey: !!API_KEY, hasScopes: !!SCOPES, hasCallback: !!CALLBACK_BASE },
    );
    return badRequest("Configuration Shopify manquante.");
  }

  if (!shopDomain) {
    return badRequest("Paramètre shop est requis.");
  }

  if (!companyId) {
    return reply(200, missingCompanyHtml, {
      "Content-Type": "text/html; charset=utf-8",
    });
  }

  if (!companyId || !shopDomain) {
    return badRequest("Paramètres companyId et shop sont requis.");
  }

  const sanitizedShop = shopDomain.endsWith(".myshopify.com")
    ? shopDomain
    : `${shopDomain}.myshopify.com`;

  const state = buildState(companyId, sanitizedShop);

  const redirectUri = new URL(CALLBACK_BASE);
  redirectUri.searchParams.set("state", state);

  const authorizeUrl = new URL(`https://${sanitizedShop}/admin/oauth/authorize`);
  authorizeUrl.searchParams.set("client_id", API_KEY);
  authorizeUrl.searchParams.set("scope", SCOPES);
  authorizeUrl.searchParams.set("redirect_uri", redirectUri.toString());
  authorizeUrl.searchParams.set("state", state);

  const headers = new Headers({
    ...CORS_HEADERS,
    Location: authorizeUrl.toString(),
  });
  return new Response(null, { status: 302, headers });
});

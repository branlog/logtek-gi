import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

const SHOPIFY_DOMAIN = Deno.env.get("SHOPIFY_DOMAIN") ?? "";
const SHOPIFY_STOREFRONT_TOKEN = Deno.env.get("SHOPIFY_STOREFRONT_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const supabaseAnon = createClient(SUPABASE_URL, ANON_KEY);

const CUSTOMER_CREATE_MUTATION = `
mutation customerCreate($input: CustomerCreateInput!) {
  customerCreate(input: $input) {
    customer {
      id
      email
    }
    customerUserErrors {
      code
      message
      field
    }
  }
}`;

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

const CUSTOMER_ADDRESS_CREATE = `
mutation customerAddressCreate($address: MailingAddressInput!, $token: String!) {
  customerAddressCreate(address: $address, customerAccessToken: $token) {
    customerAddress {
      id
    }
    customerUserErrors {
      code
      message
      field
    }
  }
}`;

interface SignupPayload {
  email?: string;
  password?: string;
  firstName?: string;
  lastName?: string;
  phone?: string;
  address1?: string;
  address2?: string;
  city?: string;
  province?: string;
  postalCode?: string;
  country?: string;
}

async function shopifyRequest(
  query: string,
  variables: Record<string, unknown>,
) {
  const response = await fetch(
    `https://${SHOPIFY_DOMAIN}/api/2024-04/graphql.json`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Storefront-Access-Token": SHOPIFY_STOREFRONT_TOKEN,
      },
      body: JSON.stringify({ query, variables }),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Shopify API error: ${detail}`);
  }

  return response.json();
}

async function customerCreate(input: Record<string, unknown>) {
  const data = await shopifyRequest(CUSTOMER_CREATE_MUTATION, { input });
  const errors = data?.data?.customerCreate?.customerUserErrors ?? [];
  if (errors.length) {
    throw new Error(errors.map((e: any) => e.message).join(", "));
  }
  const customer = data?.data?.customerCreate?.customer;
  if (!customer?.id) {
    throw new Error("Impossible de créer le client Shopify.");
  }
  return customer as { id: string; email: string };
}

async function createCustomerToken(email: string, password: string) {
  const data = await shopifyRequest(CUSTOMER_TOKEN_MUTATION, {
    input: { email, password },
  });
  const errors = data?.data?.customerAccessTokenCreate?.customerUserErrors ??
    [];
  if (errors.length) {
    throw new Error(errors.map((e: any) => e.message).join(", "));
  }
  const token = data?.data?.customerAccessTokenCreate?.customerAccessToken;
  if (!token?.accessToken) {
    throw new Error("Impossible de récupérer le jeton client Shopify.");
  }
  return token as { accessToken: string; expiresAt: string };
}

async function createCustomerAddress(
  accessToken: string,
  address: Record<string, string>,
) {
  const data = await shopifyRequest(CUSTOMER_ADDRESS_CREATE, {
    token: accessToken,
    address,
  });
  const errors = data?.data?.customerAddressCreate?.customerUserErrors ?? [];
  if (errors.length) {
    throw new Error(errors.map((e: any) => e.message).join(", "));
  }
}

async function findUserByEmail(email: string) {
  const { data, error } = await supabaseAdmin.auth.admin.listUsers({
    page: 1,
    perPage: 1,
    email,
  } as { page?: number; perPage?: number; email?: string });

  if (error) {
    throw error;
  }

  const candidates = data?.users ?? [];
  return candidates.find((user) =>
    user.email?.toLowerCase() === email.toLowerCase()
  ) ?? null;
}

function clean(value?: string | null) {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function normalizePhoneNumber(phone?: string | null, country = "CA") {
  if (!phone) return undefined;
  const trimmed = phone.trim();
  if (!trimmed) return undefined;
  const digits = trimmed.replace(/\D+/g, "");
  if (!digits) return undefined;

  if (trimmed.startsWith("+")) {
    return `+${digits}`;
  }

  if ((country === "CA" || country === "US") && digits.length === 10) {
    return `+1${digits}`;
  }

  if (digits.length >= 11 && digits.length <= 15) {
    return `+${digits}`;
  }

  return `+${digits}`;
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

  const payload = await req.json() as SignupPayload;
  const email = clean(payload.email?.toLowerCase());
  const password = clean(payload.password);
  const firstName = clean(payload.firstName);
  const lastName = clean(payload.lastName);
  const rawPhone = clean(payload.phone);
  const address1 = clean(payload.address1);
  const address2 = clean(payload.address2);
  const city = clean(payload.city);
  const province = clean(payload.province);
  const postalCode = clean(payload.postalCode);
  const country = clean(payload.country) ?? "CA";
  const phone = normalizePhoneNumber(rawPhone, country) ?? rawPhone;

  if (!email || !password || !firstName || !lastName) {
    return new Response(
      "email, password, firstName et lastName sont requis.",
      { status: 400 },
    );
  }

  try {
    let existing = await findUserByEmail(email);
    let customerToken: { accessToken: string; expiresAt: string } | null = null;

    try {
      await customerCreate({
        email,
        password,
        firstName,
        lastName,
        phone,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const alreadyExists = message.toLowerCase().includes("already") ||
        message.toLowerCase().includes("existe");
      if (!alreadyExists) {
        throw error;
      }

      if (!existing) {
        existing = await findUserByEmail(email);
      }
    }

    try {
      customerToken = await createCustomerToken(email, password);
    } catch (error) {
      throw new Error(
        error instanceof Error
          ? error.message
          : "Impossible de valider le mot de passe pour cet e-mail.",
      );
    }

    if (address1 || address2 || city || province || postalCode || phone) {
      const addressInput: Record<string, string> = {};
      if (address1) addressInput.address1 = address1;
      if (address2) addressInput.address2 = address2;
      if (city) addressInput.city = city;
      if (province) addressInput.province = province;
      if (postalCode) addressInput.zip = postalCode;
      if (phone) addressInput.phone = phone;
      addressInput.country = country ?? "CA";
      addressInput.firstName = firstName;
      addressInput.lastName = lastName;

      if (customerToken) {
        await createCustomerAddress(customerToken.accessToken, addressInput);
      }
    }

    const metadata = {
      first_name: firstName,
      last_name: lastName,
      phone,
      address: [address1, address2, city, province, postalCode]
        .filter(Boolean)
        .join(", "),
    };

    let userId: string;
    if (existing) {
      const { data: updated, error: updateError } = await supabaseAdmin.auth
        .admin.updateUserById(existing.id, {
          password,
          email_confirm: true,
          user_metadata: metadata,
        });
      if (updateError || !updated?.user) {
        throw updateError ??
          new Error("Impossible de mettre à jour l’utilisateur.");
      }
      userId = updated.user.id;
    } else {
      const { data: created, error: createError } = await supabaseAdmin.auth
        .admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: metadata,
        });
      if (createError || !created?.user) {
        throw createError ?? new Error("Impossible de créer l’utilisateur.");
      }
      userId = created.user.id;
    }

    await supabaseAdmin
      .from("user_profiles")
      .upsert({
        user_uid: userId,
        first_name: firstName,
        last_name: lastName,
        phone,
        address: metadata.address || null,
      }, { onConflict: "user_uid" });

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
    console.error("shopify-signup error", error);
    return new Response(
      error instanceof Error ? error.message : "Erreur inconnue",
      { status: 400 },
    );
  }
});

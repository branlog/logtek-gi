import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const API_KEY = Deno.env.get("GOOGLE_PLACES_API_KEY") ?? "";

interface DetailsRequest {
  placeId?: string;
  language?: string;
}

function extractComponent(
  components: Array<
    { types: string[]; long_name?: string; short_name?: string }
  >,
  type: string,
  options: { short?: boolean } = {},
): string | null {
  for (const component of components) {
    if (component.types.includes(type)) {
      return options.short
        ? component.short_name ?? null
        : component.long_name ?? null;
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (!API_KEY) {
    return new Response(
      "Clé Google Places manquante. Configure GOOGLE_PLACES_API_KEY.",
      { status: 500 },
    );
  }

  let body: DetailsRequest;
  try {
    body = await req.json() as DetailsRequest;
  } catch {
    return new Response("Corps de requête invalide.", { status: 400 });
  }

  const placeId = body.placeId?.trim();
  if (!placeId) {
    return new Response("placeId est requis.", { status: 400 });
  }

  const params = new URLSearchParams({
    place_id: placeId,
    key: API_KEY,
    language: body.language ?? "fr",
    fields: "address_component,formatted_address",
  });

  const url =
    `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`;

  try {
    const response = await fetch(url);
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`Google API error: ${detail}`);
    }

    const data = await response.json() as {
      status?: string;
      result?: {
        address_components?: Array<{
          long_name?: string;
          short_name?: string;
          types: string[];
        }>;
        formatted_address?: string;
      };
      error_message?: string;
    };

    if (data.status !== "OK") {
      throw new Error(
        data.error_message ?? `Google API status ${data.status}`,
      );
    }

    const components = data.result?.address_components ?? [];

    const streetNumber = extractComponent(components, "street_number");
    const route = extractComponent(components, "route");
    const address1 = [streetNumber, route].filter(Boolean).join(" ") || null;
    const city = extractComponent(components, "locality") ??
      extractComponent(components, "sublocality") ?? null;
    const province = extractComponent(
      components,
      "administrative_area_level_1",
      { short: true },
    );
    const postalCode = extractComponent(components, "postal_code");

    return new Response(
      JSON.stringify({
        address1,
        city,
        province,
        postalCode,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("google-place-details error", error);
    return new Response(
      error instanceof Error ? error.message : "Erreur inconnue",
      { status: 500 },
    );
  }
});

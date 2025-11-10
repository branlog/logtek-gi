import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const API_KEY = Deno.env.get("GOOGLE_PLACES_API_KEY") ?? "";

interface AutocompleteRequest {
  query?: string;
  country?: string;
  language?: string;
  sessionToken?: string;
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

  let body: AutocompleteRequest;
  try {
    body = await req.json() as AutocompleteRequest;
  } catch {
    return new Response("Corps de requête invalide.", { status: 400 });
  }

  const query = body.query?.trim();
  if (!query) {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const params = new URLSearchParams({
    input: query,
    key: API_KEY,
    language: body.language ?? "fr",
    types: "address",
  });

  if (body.country && body.country.trim().length === 2) {
    params.set("components", `country:${body.country.trim().toLowerCase()}`);
  }

  if (body.sessionToken) {
    params.set("sessiontoken", body.sessionToken);
  }

  const url =
    `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`;

  try {
    const response = await fetch(url);
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`Google API error: ${detail}`);
    }

    const data = await response.json() as {
      status?: string;
      predictions?: Array<{ description?: string; place_id?: string }>;
      error_message?: string;
    };

    if (data.status !== "OK" && data.status !== "ZERO_RESULTS") {
      throw new Error(
        data.error_message ?? `Google API status ${data.status}`,
      );
    }

    const suggestions = (data.predictions ?? [])
      .map((prediction) => ({
        description: prediction.description?.trim() ?? null,
        placeId: prediction.place_id ?? null,
      }))
      .filter((suggestion) => Boolean(suggestion.description));

    return new Response(JSON.stringify(suggestions), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("google-places-autocomplete error", error);
    return new Response(
      error instanceof Error ? error.message : "Erreur inconnue",
      { status: 500 },
    );
  }
});

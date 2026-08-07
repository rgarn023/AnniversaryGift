import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, requirePrivateMember } from "../_shared/auth.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/**
 * Place autocomplete / reverse geocode proxy for Location Lock.
 * Uses Photon (Komoot/OSM) — no API key required.
 * Client must not scrape consumer map websites.
 */

const PHOTON_SEARCH = "https://photon.komoot.io/api/";
const PHOTON_REVERSE = "https://photon.komoot.io/reverse";
const UA = "ChestOfLoveNotes/1.0 (Charoite Games; search-places edge)";

interface Body {
  action?: string;
  query?: string;
  lat?: number;
  lng?: number;
  limit?: number;
}

function featureToPlace(feature: Record<string, unknown>): Record<string, unknown> | null {
  const props = (feature.properties ?? {}) as Record<string, unknown>;
  const geom = (feature.geometry ?? {}) as Record<string, unknown>;
  const coords = (geom.coordinates ?? []) as number[];
  if (coords.length < 2) return null;
  const lng = Number(coords[0]);
  const lat = Number(coords[1]);
  let name = String(props.name ?? "").trim();
  const city = String(props.city ?? props.town ?? props.village ?? "").trim();
  const state = String(props.state ?? "").trim();
  const country = String(props.country ?? "").trim();
  const street = String(props.street ?? "").trim();
  const housenumber = String(props.housenumber ?? "").trim();
  if (!name) {
    if (street) name = `${housenumber} ${street}`.trim();
    else if (city) name = city;
    else name = "Selected place";
  }
  const addressParts: string[] = [];
  if (street) {
    const line = `${housenumber} ${street}`.trim();
    if (line !== name) addressParts.push(line);
  }
  let locality = city;
  if (state) locality = locality ? `${locality}, ${state}` : state;
  if (locality && locality !== name) addressParts.push(locality);
  else if (country && country !== name) addressParts.push(country);
  const address = addressParts.join(", ");
  return {
    name,
    address,
    lat,
    lng,
    display: address ? `${name} — ${address}` : name,
    city,
    state,
    country,
  };
}

async function photonGet(url: string): Promise<Record<string, unknown>> {
  const res = await fetch(url, {
    headers: {
      Accept: "application/json",
      "User-Agent": UA,
    },
  });
  if (!res.ok) {
    throw new AppError("upstream", "Couldn't search locations. Try again.", 502);
  }
  return (await res.json()) as Record<string, unknown>;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const body = (await req.json()) as Body;
    const action = (body.action ?? "autocomplete").trim();

    if (action === "autocomplete") {
      const query = String(body.query ?? "").trim();
      if (query.length < 3) {
        return jsonResponse({ ok: true, results: [] });
      }
      const limit = Math.min(Math.max(Number(body.limit ?? 8), 1), 12);
      const url =
        `${PHOTON_SEARCH}?q=${encodeURIComponent(query)}&limit=${limit}&lang=en`;
      const data = await photonGet(url);
      const features = (data.features ?? []) as Record<string, unknown>[];
      const results = features
        .map((f) => featureToPlace(f))
        .filter((p): p is Record<string, unknown> => p != null);
      return jsonResponse({ ok: true, results, provider: "photon" });
    }

    if (action === "reverse") {
      const lat = Number(body.lat);
      const lng = Number(body.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        throw new AppError("invalid_request", "lat/lng required", 400);
      }
      const url = `${PHOTON_REVERSE}?lat=${lat}&lon=${lng}&lang=en`;
      const data = await photonGet(url);
      const features = (data.features ?? []) as Record<string, unknown>[];
      const place = features.length
        ? featureToPlace(features[0])
        : { name: "Selected place", address: "", lat, lng, display: "Selected place" };
      if (place) {
        place.lat = lat;
        place.lng = lng;
      }
      return jsonResponse({ ok: true, place, provider: "photon" });
    }

    throw new AppError("invalid_request", "Unknown action", 400);
  } catch (err) {
    return errorResponse(err);
  }
});

const https = require('https');
const db = require('../config/database');
const { haversineKm } = require('./deliveryChargeService');

const FARM_LAT = process.env.FARM_LAT ? parseFloat(process.env.FARM_LAT) : 19.0746;
const FARM_LNG = process.env.FARM_LNG ? parseFloat(process.env.FARM_LNG) : 84.5027;
const MAX_RADIUS_KM = process.env.DELIVERY_RADIUS_KM ? parseFloat(process.env.DELIVERY_RADIUS_KM) : 20;

// Cache TTL: 30 days (pincode coordinates don't change)
const CACHE_DAYS = 30;

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, {
      headers: { 'User-Agent': 'HappyKrishi-Delivery/1.0' },
    }, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('Invalid JSON from geocoder')); }
      });
    });
    req.on('error', reject);
    req.setTimeout(8000, () => { req.destroy(); reject(new Error('Geocoder timeout')); });
    req.end();
  });
}

async function geocodePincode(pincode) {
  // India-scoped Nominatim query
  const url = `https://nominatim.openstreetmap.org/search?postalcode=${encodeURIComponent(pincode)}&countrycodes=in&format=json&limit=1&addressdetails=1`;
  const results = await fetchJson(url);
  if (!results || results.length === 0) return null;
  const r = results[0];
  const addr = r.address || {};
  return {
    lat: parseFloat(r.lat),
    lng: parseFloat(r.lon),
    district: addr.county || addr.city_district || addr.state_district || '',
    state: addr.state || '',
  };
}

async function checkPincode(pincode) {
  if (!/^\d{6}$/.test(pincode)) {
    return { deliverable: false, error: 'Enter a valid 6-digit pincode' };
  }

  // Check cache — whitelisted pincodes (admin-approved) never expire
  const cachedAny = db.prepare('SELECT * FROM pincode_cache WHERE pincode = ?').get(pincode);
  if (cachedAny && (cachedAny.min_order_amount != null || cachedAny.allowed_product_ids != null ||
      cachedAny.custom_delivery_charge != null || cachedAny.deliverable === 0)) {
    // Admin-managed pincode — never re-geocode, return as-is
    return {
      deliverable: cachedAny.deliverable === 1,
      distance_km: cachedAny.distance_km,
      district: cachedAny.district,
      state: cachedAny.state,
      lat: cachedAny.lat,
      lng: cachedAny.lng,
      cached: true,
    };
  }

  // Check normal cache (skip if older than CACHE_DAYS)
  const cached = db.prepare(
    `SELECT * FROM pincode_cache WHERE pincode = ?
     AND checked_at > datetime('now', '-${CACHE_DAYS} days')`
  ).get(pincode);

  if (cached) {
    return {
      deliverable: cached.deliverable === 1,
      distance_km: cached.distance_km,
      district: cached.district,
      state: cached.state,
      lat: cached.lat,
      lng: cached.lng,
      cached: true,
    };
  }

  // Geocode via Nominatim
  let geo;
  try {
    geo = await geocodePincode(pincode);
  } catch (e) {
    console.error('[Pincode] Geocode error:', e.message);
    return { deliverable: null, error: 'Could not verify pincode — please try again' };
  }

  if (!geo) {
    // Unknown pincode — cache as non-deliverable
    db.prepare(
      `INSERT OR REPLACE INTO pincode_cache
         (pincode, lat, lng, district, state, deliverable, distance_km,
          min_order_amount, allowed_product_ids, custom_delivery_charge)
       VALUES (?,?,?,?,?,?,?,
         COALESCE((SELECT min_order_amount FROM pincode_cache WHERE pincode=?), NULL),
         COALESCE((SELECT allowed_product_ids FROM pincode_cache WHERE pincode=?), NULL),
         COALESCE((SELECT custom_delivery_charge FROM pincode_cache WHERE pincode=?), NULL))`
    ).run(pincode, null, null, '', '', 0, null, pincode, pincode, pincode);
    return { deliverable: false, error: 'Pincode not found — we may not deliver there' };
  }

  const distance_km = haversineKm(FARM_LAT, FARM_LNG, geo.lat, geo.lng);
  const deliverable = distance_km <= MAX_RADIUS_KM;

  db.prepare(
    `INSERT OR REPLACE INTO pincode_cache
       (pincode, lat, lng, district, state, deliverable, distance_km,
        min_order_amount, allowed_product_ids, custom_delivery_charge)
     VALUES (?,?,?,?,?,?,?,
       COALESCE((SELECT min_order_amount FROM pincode_cache WHERE pincode=?), NULL),
       COALESCE((SELECT allowed_product_ids FROM pincode_cache WHERE pincode=?), NULL),
       COALESCE((SELECT custom_delivery_charge FROM pincode_cache WHERE pincode=?), NULL))`
  ).run(pincode, geo.lat, geo.lng, geo.district, geo.state, deliverable ? 1 : 0,
        Math.round(distance_km * 10) / 10, pincode, pincode, pincode);

  return {
    deliverable,
    distance_km: Math.round(distance_km * 10) / 10,
    district: geo.district,
    state: geo.state,
    lat: geo.lat,
    lng: geo.lng,
  };
}

module.exports = { checkPincode, MAX_RADIUS_KM };

const db = require('../config/database');

function getConfig(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? parseFloat(row.value) : null;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Farm location (centre point for distance calculation)
const FARM_LAT = process.env.FARM_LAT ? parseFloat(process.env.FARM_LAT) : 19.0746;
const FARM_LNG = process.env.FARM_LNG ? parseFloat(process.env.FARM_LNG) : 84.5027;

function calcDeliveryCharge(addressLat, addressLng, subtotal) {
  const freeAbove = getConfig('free_delivery_above') || 500;
  if (subtotal >= freeAbove) return 0;

  const baseCharge = getConfig('base_delivery_charge') || 30;
  const perKm = getConfig('delivery_charge_per_km') || 5;

  if (!addressLat || !addressLng) return baseCharge;

  const km = haversineKm(FARM_LAT, FARM_LNG, addressLat, addressLng);
  return Math.round(baseCharge + km * perKm);
}

module.exports = { calcDeliveryCharge, haversineKm };

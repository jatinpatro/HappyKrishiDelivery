# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HappyKrishi Delivery is a full-stack farm-to-door delivery platform with four user roles: **customer**, **salesman**, **delivery agent**, and **admin**. It consists of:
- `happykrishi_backend/` — Node.js 22 + Express REST API with SQLite
- `happykrishi_flutter/` — Flutter app (Android APK + Web) serving all four roles

## Key Commands

### Backend
```bash
cd happykrishi_backend
npm start          # production
npm run dev        # development with nodemon
```
> **Critical:** Always use Node 22 (`/usr/bin/node`). Node 24 corrupts the SQLite WAL database via better-sqlite3.

### Flutter
```bash
cd happykrishi_flutter
flutter run                                          # run on connected device
flutter build apk --release \
  --dart-define=API_BASE_URL=https://... \
  --dart-define=WS_BASE_URL=wss://...
flutter build web --release \
  --dart-define=API_BASE_URL=https://... \
  --dart-define=WS_BASE_URL=wss://...
```

### Deploy to production (full pipeline)
```bash
bash deploy.sh    # from repo root — backs up DB, builds APK + web, rsyncs to server, restarts backend
```
Production server: `88.222.212.244` (root), site: `https://delivery.happykrishi.com`

## Backend Architecture

**Stack:** Express → controllers → services → SQLite (better-sqlite3, WAL mode, synchronous prepared statements — no ORM, no async DB calls)

**Route → controller mapping** (all mounted under `/api/` in `app.js`):
| Route prefix | File | Auth requirement |
|---|---|---|
| `/auth` | `routes/auth.js` | Public + authenticated mixed |
| `/products`, `/categories` | `routes/products.js` | Public read |
| `/orders` | `routes/orders.js` | Customer |
| `/delivery` | `routes/delivery.js` | `agent` or `salesman` role |
| `/wallet` | `routes/wallet.js` | Customer |
| `/admin` | `routes/admin.js` | `admin` or `subadmin` role |
| `/salesman` | `routes/salesman.js` | `salesman` role |
| `/custom-delivery` | `routes/customDelivery.js` | Mixed |
| `/referral` | `routes/referral.js` | Customer |

**Auth flow:** `authenticate` middleware validates JWT, checks `token_version` column against DB to support force-logout. `requireRole(...roles)` middleware checks `req.user.role`.

**Database:** Single SQLite file at `data/happykrishi.db`. Schema is defined in `src/config/database.js` via `runMigrations()` (CREATE TABLE IF NOT EXISTS) + incremental ALTER TABLE migrations at the bottom of the same file. Always add new columns as incremental migrations, never modify the CREATE TABLE blocks.

**WAL checkpoint:** `db.pragma('wal_checkpoint(TRUNCATE)')` runs at startup (right after `journal_mode = WAL`) to ensure all previous WAL data is visible to the new connection.

**Delivery charge resolution priority** (in `orderController.resolveDeliveryRule`):
1. `pincode_delivery_rules` table (tiered by subtotal range, per pincode)
2. `pincode_cache.custom_delivery_charge` (legacy single value)
3. Distance-based: `base_charge + km × per_km_rate` from `app_config`

**Key services:**
- `walletService` — atomic credit/debit with transaction logging; always records to `wallet_transactions`
- `notificationService` — FCM push via Firebase Admin SDK
- `pincodeService` — geocodes pincodes via Nominatim, caches in `pincode_cache`
- `geofenceService` — haversine distance check, alerts customer when agent is within radius

**WebSocket** (`src/websocket/server.js`): rooms keyed by `order_id`. Broadcasts `{ type: 'location' | 'status' | 'customer_location' | 'customer_confirmed' }`.

## Flutter Architecture

**State management:** Riverpod (`flutter_riverpod`). Providers are defined close to the screen that uses them — typically `FutureProvider.autoDispose.family` for API calls keyed by a filter string.

**Navigation:** GoRouter in `lib/core/router/app_router.dart`. Protected routes redirect unauthenticated users to `/auth/otp`. Role-based navigation happens in `SplashScreen._navigate()`.

**API client:** `lib/core/api/dio_client.dart` — single `Dio` instance with JWT injected in `onRequest` interceptor. On 401, clears token and fires `_onForceLogout` callback (wired to `authStateProvider` via `setForceLogoutCallback`). All endpoint URLs are constants/methods in `lib/core/api/endpoints.dart`.

**Auth state:** `authStateProvider` (`StateNotifierProvider<AuthNotifier, AuthState>`) in `lib/core/providers/auth_provider.dart`. Token stored in `SharedPreferences` via `saveToken`/`deleteToken` helpers in `dio_client.dart`.

**Feature structure:** Each feature in `lib/features/<name>/` is self-contained. Screens use `ConsumerWidget` or `ConsumerStatefulWidget`. No separate repository layer — providers call Dio directly.

**Environment config:** `API_BASE_URL` and `WS_BASE_URL` are injected at build time via `--dart-define` and read in `lib/core/config/app_config.dart`.

**Shared widgets:** `lib/core/widgets/` contains `FilterChipBar`, `ActiveFilter`, `LocationPickerScreen` (map-based address pinning).

## Database Schema Notes

Key tables and their purpose:
- `users` — all roles in one table, differentiated by `role` column; `token_version` int for force-logout
- `orders` + `order_items` — order lifecycle; `delivery_date`, `order_type` ('delivery'|'pickup')
- `deliveries` — one-to-one with orders; tracks `delivery_code` (6-digit, shown only to customer+admin), `customer_confirmed_at`
- `topup_requests` — wallet top-up requests; `payment_method` includes 'credit_advance'; `approved_by_role`/'id', `payment_received`
- `salesman_settlements` — cash settlement batches raised by salesman, acknowledged by admin
- `referral_coupons` — one row per invite; `invited_phone` links to specific new user; `bonus_credited_at` set on first delivery
- `pincode_delivery_rules` — tiered delivery charges per pincode by subtotal range; replaces single `custom_delivery_charge` on `pincode_cache`
- `wallet_transactions` — immutable audit log; `reference_type` values: 'topup', 'order', 'refund', 'admin', 'referral_signup', 'referral_bonus', 'delivery_waiver'
- `app_config` — key/value runtime config (delivery charges, referral amounts, feature flags)

## Multi-Role UI

The Flutter app serves all four roles from a single binary. Role routing:
- `customer` → `/home` (ShellRoute with bottom nav)
- `salesman` → `/salesman` (SalesmanDashboardScreen with 6 tabs; Money screen at `/salesman/money`)
- `agent` → `/agent`
- `admin`/`subadmin` → `/admin/dashboard` (Money screen at `/admin/money`)

Admin Money screen (`lib/features/admin/admin_money_screen.dart`) has a shared `_MoneyFilter` that applies across all 4 tabs (Topups, Advances, Settlements, Direct) — filter key is a pipe-delimited string `"dateFrom|dateTo|approvedBy|search"` used as the Riverpod family provider key.

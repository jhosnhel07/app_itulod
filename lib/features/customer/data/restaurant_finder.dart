import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/map_config.dart';
import '../../../shared/models/restaurant_models.dart';

/// Town, category and distance helpers for the restaurant list — the app
/// twin of the web's js/restaurant-finder.js. Keep the town list and the
/// category rules in sync with it.

class IlocosTown {
  final String name;
  final RegExp match;
  final LatLng centre;

  const IlocosTown(this.name, this.match, this.centre);
}

/// Poblacion centres from OpenStreetMap; [match] finds the town in an address.
final List<IlocosTown> ilocosNorteTowns = [
  IlocosTown('Laoag City', RegExp(r'\blaoag\b', caseSensitive: false), const LatLng(18.1954482, 120.5926755)),
  IlocosTown('Batac City', RegExp(r'\bbatac\b', caseSensitive: false), const LatLng(18.0547132, 120.5645187)),
  IlocosTown('Adams', RegExp(r'\badams\b', caseSensitive: false), const LatLng(18.4613933, 120.9015722)),
  IlocosTown('Bacarra', RegExp(r'\bbacarra\b', caseSensitive: false), const LatLng(18.2514574, 120.6102374)),
  IlocosTown('Badoc', RegExp(r'\bbadoc\b', caseSensitive: false), const LatLng(17.9269759, 120.475124)),
  IlocosTown('Bangui', RegExp(r'\bbangui\b', caseSensitive: false), const LatLng(18.5366878, 120.7655254)),
  IlocosTown('Banna', RegExp(r'\bbanna\b', caseSensitive: false), const LatLng(17.9798602, 120.6550315)),
  IlocosTown('Burgos', RegExp(r'\bburgos\b', caseSensitive: false), const LatLng(18.5117704, 120.64429)),
  IlocosTown('Carasi', RegExp(r'\bcarasi\b', caseSensitive: false), const LatLng(18.1401114, 120.8212426)),
  IlocosTown('Currimao', RegExp(r'\bcurrimao\b', caseSensitive: false), const LatLng(18.0200584, 120.4865068)),
  IlocosTown('Dingras', RegExp(r'\bdingras\b', caseSensitive: false), const LatLng(18.1030975, 120.6975437)),
  IlocosTown('Dumalneg', RegExp(r'\bdumalneg\b', caseSensitive: false), const LatLng(18.5223727, 120.8089365)),
  IlocosTown('Marcos', RegExp(r'\bmarcos\b(?!\s+ave)', caseSensitive: false), const LatLng(18.0434623, 120.6782391)),
  IlocosTown('Nueva Era', RegExp(r'\bnueva era\b', caseSensitive: false), const LatLng(17.9150989, 120.6642509)),
  IlocosTown('Pagudpud', RegExp(r'\bpagudpud\b', caseSensitive: false), const LatLng(18.5591345, 120.7870256)),
  IlocosTown('Paoay', RegExp(r'\bpaoay\b', caseSensitive: false), const LatLng(18.0619547, 120.5206137)),
  IlocosTown('Pasuquin', RegExp(r'\bpasuquin\b', caseSensitive: false), const LatLng(18.3335315, 120.618455)),
  IlocosTown('Piddig', RegExp(r'\bpiddig\b', caseSensitive: false), const LatLng(18.1652098, 120.7163881)),
  IlocosTown('Pinili', RegExp(r'\bpinili\b', caseSensitive: false), const LatLng(17.9524076, 120.5272509)),
  IlocosTown('San Nicolas', RegExp(r'\bsan nicolas\b', caseSensitive: false), const LatLng(18.1734458, 120.5944583)),
  IlocosTown('Sarrat', RegExp(r'\bsarrat\b', caseSensitive: false), const LatLng(18.1567792, 120.644784)),
  IlocosTown('Solsona', RegExp(r'\bsolsona\b', caseSensitive: false), const LatLng(18.0926692, 120.7725709)),
  IlocosTown('Vintar', RegExp(r'\bvintar\b', caseSensitive: false), const LatLng(18.2304271, 120.6490336)),
];

class FoodCategory {
  final String id;
  final String label;
  final IconData icon;
  final RegExp match;

  const FoodCategory(this.id, this.label, this.icon, this.match);
}

/// Matched against the cuisine type plus the name; a place can be in several.
final List<FoodCategory> foodCategories = [
  FoodCategory('fastfood', 'Fast food', Icons.lunch_dining_rounded, RegExp(r'fast food|burger|shawarma', caseSensitive: false)),
  FoodCategory('ilocano', 'Ilocano', Icons.rice_bowl_rounded, RegExp(r'ilocano|empanada|miki|native delicacies', caseSensitive: false)),
  FoodCategory('empanada', 'Empanada & miki', Icons.cookie_outlined, RegExp(r'empanada|miki', caseSensitive: false)),
  FoodCategory('coffee', 'Coffee & milk tea', Icons.local_cafe_rounded, RegExp(r'caf[eé]|coffee|milk tea', caseSensitive: false)),
  FoodCategory('bakery', 'Bakery & sweets', Icons.bakery_dining_rounded, RegExp(r'bak|donut|dessert|delicacies', caseSensitive: false)),
  FoodCategory('pizza', 'Pizza & pasta', Icons.local_pizza_rounded, RegExp(r'pizza|pasta', caseSensitive: false)),
  FoodCategory('chicken', 'Chicken', Icons.kebab_dining_rounded, RegExp(r'chicken|wings', caseSensitive: false)),
  FoodCategory('asian', 'Korean & Japanese', Icons.ramen_dining_rounded, RegExp(r'korean|japanese', caseSensitive: false)),
  FoodCategory('chinese', 'Chinese', Icons.takeout_dining_rounded, RegExp(r'chinese', caseSensitive: false)),
  FoodCategory('grill', 'Grill & seafood', Icons.outdoor_grill_rounded, RegExp(r'grill|seafood', caseSensitive: false)),
  FoodCategory('meals', 'Filipino meals', Icons.restaurant_rounded, RegExp(r'filipino|carinderia|silog|pares|international|mexican', caseSensitive: false)),
];

const Distance _distance = Distance();

double straightKm(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b) / 1000;

/// Typical road distance — same factor the fare estimator uses.
double roadKm(LatLng a, LatLng b) => straightKm(a, b) * MapConfig.roadDistanceFactor;

String nearestTown(LatLng p) {
  var best = ilocosNorteTowns.first;
  for (final t in ilocosNorteTowns) {
    if (straightKm(p, t.centre) < straightKm(p, best.centre)) best = t;
  }
  return best.name;
}

/// The town is the last one named in the address; otherwise the nearest
/// town centre to the restaurant's pin.
String restaurantTown(RestaurantModel r) {
  String? best;
  var bestAt = -1;
  for (final t in ilocosNorteTowns) {
    for (final m in t.match.allMatches(r.address)) {
      if (m.start > bestAt) {
        bestAt = m.start;
        best = t.name;
      }
    }
  }
  if (best != null) return best;
  return r.hasLocation ? nearestTown(LatLng(r.lat!, r.lng!)) : 'Other';
}

Set<String> restaurantCategories(RestaurantModel r) {
  final hay = '${r.cuisineType ?? ''} ${r.name}';
  return {for (final c in foodCategories) if (c.match.hasMatch(hay)) c.id};
}

/// Tile colours for a restaurant's main category — same families as the
/// web (brand blue / rose, plus warm and green tints; never status colours).
({Color bg, Color fg, IconData icon}) restaurantVisual(Set<String> cats) {
  FoodCategory? main;
  for (final c in foodCategories) {
    if (cats.contains(c.id)) {
      main = c;
      break;
    }
  }
  const brown = (bg: Color(0xFFF3EBE6), fg: Color(0xFF7A5340));
  const amber = (bg: Color(0xFFFBF1E1), fg: Color(0xFFA8661B));
  const blue = (bg: Color(0xFFE3F2FD), fg: Color(0xFF2196F3));
  const navy = (bg: Color(0xFFE3F2FD), fg: Color(0xFF0D47A1));
  const rose = (bg: Color(0xFFFFF5F5), fg: Color(0xFFB06B79));
  const roseDeep = (bg: Color(0xFFF7D6D0), fg: Color(0xFFA65A6B));
  const green = (bg: Color(0xFFE9F8F0), fg: Color(0xFF157A4D));
  final tint = switch (main?.id) {
    'fastfood' => blue,
    'ilocano' || 'chinese' => rose,
    'empanada' || 'bakery' => amber,
    'coffee' => brown,
    'pizza' => roseDeep,
    'chicken' || 'asian' => navy,
    'grill' || 'meals' => green,
    _ => (bg: const Color(0xFFF1F4F9), fg: const Color(0xFF6B7280)),
  };
  return (bg: tint.bg, fg: tint.fg, icon: main?.icon ?? Icons.storefront_rounded);
}

/// Name without a trailing "(Town)" — the town is shown separately. Branch
/// details like "(Marcos Ave., Batac City)" are kept.
String restaurantDisplayName(RestaurantModel r, String town) {
  final suffix = ' ($town)';
  return r.name.endsWith(suffix) ? r.name.substring(0, r.name.length - suffix.length) : r.name;
}

/// Seeded menus for places without a published menu end their descriptions
/// with this note (sql/021) — shown as a "Typical" badge instead.
const String typicalItemNote = ' · typical item, availability may vary';

// ── Pictures: name badges, cover photos, sample photos ──────────────────

const _monoSkip = {'the', 'of', 'and', 'ni', 'ang', 'sa', 'de', 'la', 'restaurant', 'resto', 'cafe', 'café', 'eatery', 'food', 'house'};

/// Up to two initials for a restaurant's name badge (shown when it has no
/// logo) — same rule as the web's restaurantInitials().
String restaurantInitials(String name) {
  final words = name
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp("['’]"), '') // "Herbie's" stays one word
      .split(RegExp(r'[^A-Za-z0-9ÑñÉé]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final main = words.where((w) => !_monoSkip.contains(w.toLowerCase())).toList();
  final pick = (main.isNotEmpty ? main : words).take(2);
  final s = pick.map((w) => w[0].toUpperCase()).join();
  return s.isEmpty ? '?' : s;
}

/// Sample dish photos (CC0 / public domain) in the catalog-images bucket
/// (web sql/027, sql/028, STOCK_PHOTOS.md).
String get _stockBase =>
    '${(dotenv.env['SUPABASE_URL'] ?? '').replaceAll(RegExp(r'/+$'), '')}/storage/v1/object/public/catalog-images/stock/';

bool isSamplePhoto(String? url) => url != null && url.contains('/catalog-images/stock/');

const _categoryCover = {
  'fastfood': 'burger', 'ilocano': 'longganisa', 'empanada': 'empanada', 'coffee': 'coffee', 'bakery': 'bread',
  'pizza': 'pizza', 'chicken': 'fried-chicken', 'asian': 'sushi', 'chinese': 'dumplings', 'grill': 'bbq', 'meals': 'rice-meal',
};

/// Banner photo for a restaurant's menu page: a sample photo of its category.
String restaurantCoverUrl(Set<String> cats) {
  final first = foodCategories.where((c) => cats.contains(c.id)).map((c) => c.id).firstOrNull;
  return '$_stockBase${_categoryCover[first] ?? 'rice-meal'}.jpg';
}

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../shared/models/booking_models.dart';

/// The app's icon set — Font Awesome, the same icons the web dashboards use,
/// so a ride, a food order or the Home tab looks the same on both.
/// (web: ICON_BY_KIND in js/dashboard-common.js, .service-tiles, .bottom-nav)
class AppIcons {
  AppIcons._();

  // ── Services ──────────────────────────────────────────────────────────
  static const FaIconData ride = FontAwesomeIcons.car;
  static const FaIconData rideTile = FontAwesomeIcons.carSide;
  static const FaIconData food = FontAwesomeIcons.utensils;
  static const FaIconData parcel = FontAwesomeIcons.box;
  static const FaIconData hauling = FontAwesomeIcons.truckMoving;

  static FaIconData forKind(BookingKind kind) => switch (kind) {
        BookingKind.transport => ride,
        BookingKind.food => food,
        BookingKind.parcel => parcel,
        BookingKind.hauling => hauling,
      };

  // ── Bottom navigation (outline when idle, solid when selected) ─────────
  static const FaIconData home = FontAwesomeIcons.house;
  static const FaIconData homeActive = FontAwesomeIcons.solidHouse;
  static const FaIconData history = FontAwesomeIcons.clockRotateLeft;
  static const FaIconData notifications = FontAwesomeIcons.bell;
  static const FaIconData notificationsActive = FontAwesomeIcons.solidBell;
  static const FaIconData profile = FontAwesomeIcons.user;
  static const FaIconData profileActive = FontAwesomeIcons.solidUser;
  static const FaIconData requests = FontAwesomeIcons.inbox;
  static const FaIconData trip = FontAwesomeIcons.route;
  static const FaIconData earnings = FontAwesomeIcons.sackDollar;
}

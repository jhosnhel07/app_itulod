import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../utils/app_log.dart';

/// Where you were in the app, so it opens there again after Android closed it
/// in the background: the bottom-bar tab, the booking screen that was open and
/// its half-filled form (kept [draftLife]). Per account; cleared on log out.
/// Web twin: the #section in the address + sessionStorage (utils.js
/// writeViewHash / saveFormDraft).
class LastPlace {
  LastPlace._();

  static const _prefix = 'last_place.';
  static const draftLife = Duration(minutes: 30);

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e, s) {
      AppLog.warn('LastPlace: preferences unavailable', e, s);
      return null;
    }
  }

  /// Bottom-bar tab of [dashboard] ('customer' / 'rider').
  static Future<int?> tab(String dashboard, String userId) async =>
      (await _prefs())?.getInt('${_prefix}tab.$dashboard.$userId');

  static Future<void> saveTab(String dashboard, String userId, int index) async =>
      (await _prefs())?.setInt('${_prefix}tab.$dashboard.$userId', index);

  /// The booking screen that was open: 'ride', 'food', 'parcel' or 'hauling'.
  static Future<String?> openForm(String userId) async =>
      (await _prefs())?.getString('${_prefix}open.$userId');

  static Future<void> setOpenForm(String userId, String? form) async {
    final prefs = await _prefs();
    if (form == null) {
      await prefs?.remove('${_prefix}open.$userId');
    } else {
      await prefs?.setString('${_prefix}open.$userId', form);
    }
  }

  /// A half-filled booking form, or null when there is none or it's older
  /// than [draftLife].
  static Future<Map<String, dynamic>?> draft(String form, String userId) async {
    final prefs = await _prefs();
    final raw = prefs?.getString('${_prefix}draft.$form.$userId');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final saved = DateTime.tryParse(data['__saved'] as String? ?? '');
      if (saved == null || DateTime.now().difference(saved) > draftLife) {
        await prefs?.remove('${_prefix}draft.$form.$userId');
        return null;
      }
      return data;
    } catch (e, s) {
      AppLog.warn('LastPlace: dropping a broken draft', e, s);
      await prefs?.remove('${_prefix}draft.$form.$userId');
      return null;
    }
  }

  static Future<void> saveDraft(String form, String userId, Map<String, dynamic> data) async =>
      (await _prefs())?.setString('${_prefix}draft.$form.$userId',
          jsonEncode({...data, '__saved': DateTime.now().toIso8601String()}));

  static Future<void> clearDraft(String form, String userId) async =>
      (await _prefs())?.remove('${_prefix}draft.$form.$userId');

  /// Log out: forget every account's places on this phone.
  static Future<void> clearAll() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }

  static Map<String, dynamic>? pointToJson(LatLng? p) =>
      p == null ? null : {'lat': p.latitude, 'lng': p.longitude};

  static LatLng? pointFromJson(Object? json) {
    if (json is! Map) return null;
    final lat = (json['lat'] as num?)?.toDouble(), lng = (json['lng'] as num?)?.toDouble();
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }
}

/// A booking screen that keeps its half-filled form ([LastPlace.draft]) and
/// is reopened by the customer dashboard if the app was closed on it.
/// Every setState saves the draft (debounced); [draftStep] is the
/// BookingStepper step, and [draftGeneration] changes when a draft comes back
/// so the stepper can be rebuilt on that step.
mixin BookingDraftMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 'ride', 'parcel' or 'hauling'.
  String get draftForm;
  Map<String, dynamic> draftToJson();
  /// Put a saved draft back (runs inside setState).
  void draftFromJson(Map<String, dynamic> data);
  /// After a draft came back — e.g. fetch the road route again.
  void afterDraftRestored() {}

  int draftStep = 0;
  int draftGeneration = 0;
  bool _draftReady = false;
  bool _draftDone = false;
  Timer? _draftTimer;
  String? _draftUser;

  void initDraft() {
    final uid = _draftUser = ref.read(authNotifierProvider).profile?.id;
    if (uid == null) return;
    LastPlace.setOpenForm(uid, draftForm);
    LastPlace.draft(draftForm, uid).then((data) {
      if (!mounted) return;
      if (data != null) {
        super.setState(() {
          draftFromJson(data);
          draftStep = (data['__step'] as num?)?.toInt() ?? 0;
          draftGeneration++;
        });
        afterDraftRestored();
      }
      _draftReady = true; // only now, so the empty form can't overwrite the draft
    });
  }

  void onDraftStep(int step) {
    draftStep = step;
    saveDraft();
  }

  void saveDraft() {
    final uid = _draftUser;
    if (uid == null || !_draftReady || _draftDone) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      if (_draftDone) return;
      LastPlace.saveDraft(draftForm, uid, {...draftToJson(), '__step': draftStep});
    });
  }

  /// The booking was placed: nothing to come back to.
  void finishDraft() {
    _draftDone = true;
    _draftTimer?.cancel();
    final uid = _draftUser;
    if (uid == null) return;
    LastPlace.clearDraft(draftForm, uid);
    LastPlace.setOpenForm(uid, null);
  }

  /// Leaving the screen on purpose: don't reopen it, but keep the draft.
  /// Call before the screen's controllers are disposed.
  void disposeDraft() {
    final pending = _draftTimer?.isActive ?? false;
    _draftTimer?.cancel();
    final uid = _draftUser;
    if (uid == null || _draftDone) return;
    if (pending) LastPlace.saveDraft(draftForm, uid, {...draftToJson(), '__step': draftStep});
    LastPlace.setOpenForm(uid, null);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    saveDraft();
  }
}

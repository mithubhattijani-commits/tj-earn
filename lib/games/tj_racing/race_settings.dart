import 'package:shared_preferences/shared_preferences.dart';

/// Per-player TJ Racing 3D settings + local progress cache
/// (v1.0.31).
///
/// Tilt calibration (competitor-research.md §A.1 — the #1
/// make-or-break, Traffic Racer lesson):
/// - Unity auto-calibrates neutral at EVERY race start (however the
///   player holds the phone IS zero) — that is Unity-side
///   (RaceManager countdown calls `TiltSteering.RequestRecalibrate`);
///   Flutter only sends the settings below via `SetSensitivity` /
///   `SetControlMode` / `RecalibrateTilt` (see `unity_bridge.dart`).
/// - Dead zone is ±10° (research value, `tiltDeadZoneDeg` in the
///   remote config) — Unity reads it from the config, Flutter never
///   sends it per-race.
/// - Sensitivity is a player slider (0.5–2.0, default 1.0), saved
///   here; the player can switch tilt ↔ buttons ↔ both from the
///   Flutter settings sheet (and from Unity's own pause menu — both
///   write the same Unity state).
///
/// Control mode values are Unity's: 'tilt' | 'buttons' | 'both'
/// (Unity default is 'both' — tilt steering + on-screen buttons
/// together, per the plan: "dono tareeqay hon ge").
///
/// Local progress cache: races finished / won and owned cars +
/// power-ups are cached here so the garage renders instantly. The
/// SERVER is truth for coins; the cache only remembers what the
/// player bought (a successful `spend-race-item` response writes
/// it). If the cache is ever lost, owned items are re-derived on
/// next launch — see the open item in `UNITY_CONTRACT.md` (the
/// server needs a GET owned-items endpoint; until then a reinstall
/// loses the local owned list and the player must re-unlock from
/// their Ad Coin balance, which the server still holds).
///
/// NOTE: garage car SELECTION is Unity-owned (MenuUI calls
/// `ApplySelectedCar` locally and never tells Flutter). Flutter's
/// cached selection is only the launch default sent in `SetConfig`
/// / `SetSelectedCar`; if the player picks another car in Unity's
/// garage, Unity's choice wins until the next app launch.
class RaceSettings {
  RaceSettings._();

  static const String _sensitivityKey = 'tj_racing_tilt_sensitivity';
  static const String _controlModeKey = 'tj_racing_control_mode';
  static const String _racesFinishedKey = 'tj_racing_races_finished';
  static const String _racesWonKey = 'tj_racing_races_won';
  static const String _selectedCarKey = 'tj_racing_selected_car';
  static const String _ownedCarsKey = 'tj_racing_owned_cars';
  static const String _ownedPowerupsKey = 'tj_racing_owned_powerups';

  /// Fixed tilt dead zone in degrees (research §A.1: ±10° so small
  /// shakes don't steer). Lives in the remote config
  /// (`tiltDeadZoneDeg`); Unity reads it from `SetConfig` — Flutter
  /// never sends it per-race.
  static const double tiltDeadZoneDeg = 10;

  /// Default tilt sensitivity (slider range 0.5–2.0).
  static const double defaultSensitivity = 1.0;

  /// Default control mode — matches Unity's default ('both': tilt
  /// steering + on-screen buttons together).
  static const String defaultControlMode = 'both';

  static double _clampSensitivity(double v) =>
      v < 0.5 ? 0.5 : (v > 2.0 ? 2.0 : v);

  static Future<double> get tiltSensitivity async {
    final prefs = await SharedPreferences.getInstance();
    return _clampSensitivity(
      prefs.getDouble(_sensitivityKey) ?? defaultSensitivity,
    );
  }

  static Future<void> setTiltSensitivity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sensitivityKey, _clampSensitivity(value));
  }

  /// 'tilt' | 'buttons' | 'both' (default 'both', matching Unity).
  /// Unknown stored values fall back to 'both'.
  static Future<String> get controlMode async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_controlModeKey) ?? defaultControlMode;
    return mode == 'tilt' || mode == 'buttons' ? mode : 'both';
  }

  static Future<void> setControlMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _controlModeKey,
      mode == 'tilt' || mode == 'buttons' ? mode : 'both',
    );
  }

  static Future<int> get racesFinished async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_racesFinishedKey) ?? 0;
  }

  static Future<int> get racesWon async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_racesWonKey) ?? 0;
  }

  /// Records a finished race (called once per claimed result, never
  /// for a quit). First race (0 finished) races 'easy' difficulty
  /// so race 1 is winnable (research §A.8).
  static Future<void> recordRaceFinished({required bool won}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _racesFinishedKey,
      (prefs.getInt(_racesFinishedKey) ?? 0) + 1,
    );
    if (won) {
      await prefs.setInt(
        _racesWonKey,
        (prefs.getInt(_racesWonKey) ?? 0) + 1,
      );
    }
  }

  static Future<String> get selectedCarId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedCarKey) ?? 'street_hawk';
  }

  static Future<void> setSelectedCarId(String carId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedCarKey, carId);
  }

  static Future<Set<String>> get ownedCarIds async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_ownedCarsKey)?.toSet() ??
        {'street_hawk'};
  }

  static Future<void> addOwnedCar(String carId) async {
    final prefs = await SharedPreferences.getInstance();
    final owned = prefs.getStringList(_ownedCarsKey)?.toSet() ??
        {'street_hawk'};
    owned.add(carId);
    await prefs.setStringList(_ownedCarsKey, owned.toList());
  }

  static Future<Set<String>> get ownedPowerupIds async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_ownedPowerupsKey)?.toSet() ?? {};
  }

  static Future<void> addOwnedPowerup(String powerupId) async {
    final prefs = await SharedPreferences.getInstance();
    final owned =
        prefs.getStringList(_ownedPowerupsKey)?.toSet() ?? <String>{};
    owned.add(powerupId);
    await prefs.setStringList(_ownedPowerupsKey, owned.toList());
  }
}

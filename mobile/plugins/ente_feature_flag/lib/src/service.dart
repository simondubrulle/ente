// ignore_for_file: always_use_package_imports

import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "model.dart";

class FeatureFlagService {
  late final SharedPreferences _prefs;
  late final Dio _enteDio;

  FeatureFlagService(this._prefs, this._enteDio) {
    Future.delayed(const Duration(seconds: 5), () {
      _fetch();
    });
  }

  RemoteFlags? _flags;

  RemoteFlags get flags {
    try {
      if (_flags == null) {
        _fetch().ignore();
      }
      _flags ??= RemoteFlags.fromMap(
        jsonDecode(_prefs.getString("remote_flags") ?? "{}"),
      );
      return _flags!;
    } catch (e) {
      debugPrint("Error getting flags: $e");
      return RemoteFlags.defaultValue;
    }
  }

  Future<void> _fetch() async {
    try {
      if (_prefs.containsKey("token")) {
        return;
      }
      if (kDebugMode) {
        debugPrint("Fetching feature flags");
      }
      final response = await _enteDio.get("/remote-store/feature_flags");
      final remoteFlags = RemoteFlags.fromMap(response.data);
      await _prefs.setString("remote_flags", remoteFlags.toJson());
      _flags = remoteFlags;
    } catch (e) {
      debugPrint("Failed to sync feature flags $e");
    }
  }

  bool get disableCFWorker => flags.disableCFWorker;

  bool get internalUser => flags.internalUser;

  bool get betaUser => flags.betaUser;

  bool get enableStripe => Platform.isIOS ? false : flags.enableStripe;

  bool get mapEnabled => flags.mapEnabled;

  bool get faceSearchEnabled => flags.faceSearchEnabled;

  bool get passKeyEnabled => flags.passKeyEnabled;

  bool get recoveryKeyVerified => flags.recoveryKeyVerified;
}

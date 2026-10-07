import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/office_gossip_app.dart';
import 'core/di/injection_container.dart';
import 'core/env/app_environment.dart';
import 'core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await FirebaseBootstrap.initialize();
  await initDI(
    // Release builds (App Store, TestFlight, Xcode Cloud) default to prod unless APP_ENV overrides it.
    AppEnvironment.fromDefine(kReleaseMode ? AppEnvironment.prod : AppEnvironment.dev),
    firebaseReady: firebaseReady,
  );
  runApp(const OfficeGossipApp());
}

import 'package:flutter/widgets.dart';

import 'app/office_gossip_app.dart';
import 'core/di/injection_container.dart';
import 'core/env/app_environment.dart';
import 'core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await FirebaseBootstrap.initialize();
  await initDI(
    AppEnvironment.fromDefine(AppEnvironment.dev),
    firebaseReady: firebaseReady,
  );
  runApp(const OfficeGossipApp());
}

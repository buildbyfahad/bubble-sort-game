import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemChrome();
  // Portrait only. The board's composition is designed around a tall frame,
  // and a landscape layout that has not been designed is worse than none.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const BubbleSortApp());
}

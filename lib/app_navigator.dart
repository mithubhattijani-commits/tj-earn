import 'package:flutter/material.dart';

/// Global navigator key (Jaani, 3 Nov 2026): the update-download banner
/// and the install prompt must survive navigation — they are attached
/// through this key, never through the calling screen's BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

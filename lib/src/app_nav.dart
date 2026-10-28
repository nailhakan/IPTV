import 'package:flutter/widgets.dart';

/// Lets code outside the widget tree (e.g. the phone remote's "Back" button) navigate.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

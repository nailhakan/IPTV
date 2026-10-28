import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app_nav.dart';
import 'src/library.dart';
import 'src/login_page.dart';
import 'src/phone_remote.dart';
import 'src/ui_scale.dart';
import 'src/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid) {
    // low-RAM TV sticks: keep decoded images small
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 32 << 20
      ..maximumSize = 120;
  }
  await Future.wait([AppSettings.instance.load(), Library.instance.load()]);
  if (AppSettings.instance.phoneRemote) PhoneRemote.instance.setEnabled(true);
  runApp(const IptvApp());
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final tv = AppSettings.instance.tvMode;
        final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7), brightness: Brightness.dark);
        // Material 3 buttons ignore ThemeData.focusColor: give them an explicit, clearly visible focus state.
        final focusOverlay = WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.focused) ? scheme.primary.withValues(alpha: 0.35) : null);
        final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((s) => s.contains(WidgetState.focused) ? BorderSide(color: Colors.white, width: 3) : null);
        final focusStyle = ButtonStyle(overlayColor: focusOverlay, side: focusSide);
        return MaterialApp(
          title: 'IPTV',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            // Clear focus highlight so the remote's position is always visible
            focusColor: scheme.primary.withValues(alpha: tv ? 0.45 : 0.25),
            iconButtonTheme: IconButtonThemeData(style: focusStyle),
            textButtonTheme: TextButtonThemeData(style: focusStyle),
            filledButtonTheme: FilledButtonThemeData(style: focusStyle),
            outlinedButtonTheme: OutlinedButtonThemeData(style: focusStyle),
            elevatedButtonTheme: ElevatedButtonThemeData(style: focusStyle),
          ),
          builder: (context, child) => UiScale(scale: AppSettings.instance.uiScale, child: child!),
          home: const LoginPage(autoLogin: true),
        );
      },
    );
  }
}

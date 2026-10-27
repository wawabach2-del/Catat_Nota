import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'presentation/providers.dart';
import 'presentation/screens/app_shell.dart';

class CatatNotaApp extends ConsumerWidget {
  const CatatNotaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Menyalakan pendengar konektivitas -> auto-sync saat online.
    // (select -> tidak rebuild MaterialApp tiap status sync berubah)
    ref.watch(syncControllerProvider.select((_) => 0));

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppShell(),
    );
  }
}

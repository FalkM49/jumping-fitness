import 'package:flutter/material.dart';

import '../../widgets/screen_placeholder.dart';

/// Запасной экран на случай перехода по несуществующему маршруту.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ScreenPlaceholder(
        title: 'Экран не найден',
        subtitle: routeName,
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('На главную'),
          ),
        ],
      ),
    );
  }
}

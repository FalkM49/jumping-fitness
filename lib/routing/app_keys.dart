import 'package:flutter/material.dart';

/// Корневой навигатор — чтобы открыть экран по тапу на push, когда
/// под рукой нет BuildContext нужного экрана.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Корневой ScaffoldMessenger — баннеры о push поверх любого экрана.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

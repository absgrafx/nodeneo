import 'package:flutter/material.dart';

/// Lets [HomeScreen] refresh when a route popped exposes it again (e.g. back from chat).
final RouteObserver<PageRoute<dynamic>> redpillRouteObserver = RouteObserver<PageRoute<dynamic>>();

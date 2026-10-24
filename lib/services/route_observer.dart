import 'package:flutter/widgets.dart';

/// Global route observer to monitor screen transitions and notify [RouteAware] widgets.
final RouteObserver<PageRoute> appRouteObserver = RouteObserver<PageRoute>();

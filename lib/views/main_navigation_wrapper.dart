import 'package:flutter/material.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../config/feature_toggles.dart';
import 'home_screen.dart';

class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    const useExperimental = FeatureToggles.useExperimentalHomeView;

    return const GradientScaffold(
      appBar: useExperimental
          ? null
          : CustomTopBar(
              showBack: false,
            ),
      extendBodyBehindAppBar: true,
      body: HomeScreen(),
    );
  }
}

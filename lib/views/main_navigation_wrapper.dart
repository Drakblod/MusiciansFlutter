import 'package:flutter/material.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import 'home_screen.dart';

class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const GradientScaffold(
      appBar: CustomTopBar(
        showBack: false,
      ),
      extendBodyBehindAppBar: true,
      body: HomeScreen(),
    );
  }
}

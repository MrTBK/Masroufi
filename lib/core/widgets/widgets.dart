import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Maps stored icon names to Material icons (never mirrored blindly).
IconData appIcon(String name) => switch (name) {
  'cash' => Icons.payments,
  'bank' => Icons.account_balance,
  'card' => Icons.credit_card,
  'savings' => Icons.savings,
  'shopping_cart' => Icons.shopping_cart,
  'restaurant' => Icons.restaurant,
  'coffee' => Icons.coffee,
  'fastfood' => Icons.fastfood,
  'taxi' => Icons.local_taxi,
  'bus' => Icons.airport_shuttle,
  'directions_bus' => Icons.directions_bus,
  'tram' => Icons.tram,
  'fuel' => Icons.local_gas_station,
  'bolt' => Icons.bolt,
  'water' => Icons.water_drop,
  'wifi' => Icons.wifi,
  'phone' => Icons.smartphone,
  'shirt' => Icons.checkroom,
  'devices' => Icons.devices,
  'home' => Icons.home,
  'health' => Icons.health_and_safety,
  'entertainment' => Icons.movie,
  'gym' => Icons.fitness_center,
  _ => Icons.category,
};

class EmptyState extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: Theme.of(context).colorScheme.secondary,
              semanticLabel: title,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('↻')),
          ],
        ),
      ),
    );
  }
}

String trOf(BuildContext context, String key) =>
    Strings.get(Localizations.localeOf(context).languageCode, key);

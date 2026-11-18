import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';

class OnboardingScreen extends ConsumerWidget {
  final VoidCallback onGetStarted;

  const OnboardingScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // App Icon / Hero Image without glowing BoxShadow
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Card(
                        elevation: 0,
                        color: colorScheme.surfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(36),
                        ),
                        child: Icon(
                          Icons.cloud_upload_outlined,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // App Name
              Text(
                'CloudPocket',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.8,
                ),
              ),

              const SizedBox(height: 12),

              // Tagline
              Text(
                'Share files and temporary rooms from your phone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 48),

              const Spacer(flex: 3),

              // Get Started Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () {
                    ref.read(settingsProvider.notifier).completeOnboarding();
                    onGetStarted();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

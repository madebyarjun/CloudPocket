import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen(
      {super.key, required this.onGetStarted, this.fromSettings = false});

  final VoidCallback onGetStarted;
  final bool fromSettings;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const pages = [
    (
      image: 'send',
      title: 'Send a file',
      body:
          'Tap Choose files, pick what to share, then tap Start Sharing. Show the QR code or send the link. The recipient can open it in a browser.',
    ),
    (
      image: 'receive',
      title: 'Receive files',
      body:
          'Choose Receive Mode and tap Start Receiving. Share the link so someone can upload to your phone. For local sharing, connect both devices to the same Wi-Fi or hotspot.',
    ),
    (
      image: 'room',
      title: 'Start a room',
      body:
          'Choose Room, tap Create Room, and set a timer. Launch the room and share its invite to chat and view attachments together.',
    ),
  ];
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final page = pages[index];
    final last = index == pages.length - 1;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('User guide'),
        actions: [
          TextButton(
            onPressed: widget.onGetStarted,
            child: Text(widget.fromSettings ? 'Close' : 'Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(index),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    children: [
                      AspectRatio(
                        aspectRatio: 1.5,
                        child: ExcludeSemantics(
                          child: Image.asset('assets/guide/${page.image}.webp',
                              fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Step ${index + 1} of ${pages.length}',
                          style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(page.title,
                            style: theme.textTheme.headlineMedium),
                      ),
                      const SizedBox(height: 12),
                      Text(page.body, style: theme.textTheme.bodyLarge),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      if (index > 0)
                        TextButton(
                          onPressed: () => setState(() => index--),
                          child: const Text('Back'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: last
                            ? widget.onGetStarted
                            : () => setState(() => index++),
                        child: Text(last
                            ? (widget.fromSettings ? 'Done' : 'Get started')
                            : 'Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

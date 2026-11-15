import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class TunnelGuideDialog extends StatelessWidget {
  final int initialTabIndex;

  const TunnelGuideDialog({
    super.key,
    this.initialTabIndex = 0,
  });

  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => TunnelGuideDialog(initialTabIndex: initialTab),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Tunnel Setup Guide',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: colorScheme.outline),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: colorScheme.primary,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'Cloudflare Custom'),
                  Tab(text: 'Custom Bore VPS'),
                  Tab(text: 'Zero-Setup Modes'),
                ],
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const Expanded(
                child: TabBarView(
                  children: [
                    _CloudflareGuideTab(),
                    _BoreVpsGuideTab(),
                    _ZeroSetupGuideTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudflareGuideTab extends StatelessWidget {
  const _CloudflareGuideTab();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cpColors = Theme.of(context).extension<CloudPocketColors>()!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoBanner(
          icon: Icons.shield_outlined,
          color: cpColors.warning,
          title: 'Branded HTTPS on Your Domain',
          description:
              'CloudPocket automates Cloudflare tunnel and DNS setup with a single API token. You never need to configure DNS records manually.',
        ),
        const SizedBox(height: 16),
        _StepCard(
          stepNumber: '1',
          title: 'Generate API Token in Cloudflare',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Go to Cloudflare Dashboard → My Profile → API Tokens → Create Token.',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose "Create Custom Token" and add these permissions:',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const _CodeChip(label: 'Zone → Zone → Read (to list domains)'),
              const SizedBox(height: 4),
              const _CodeChip(label: 'Zone → DNS → Edit (to create CNAME)'),
              const SizedBox(height: 4),
              const _CodeChip(label: 'Account → Cloudflare Tunnel → Edit (to create tunnel)'),
              const SizedBox(height: 8),
              Text(
                'Under "Account Resources" & "Zone Resources", select "Include → All accounts" and "All zones".',
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                '💡 Tip: Your Account ID is on the right sidebar of your Cloudflare overview page or in the browser URL (dash.cloudflare.com/<ACCOUNT_ID>).',
                style: TextStyle(color: cpColors.info, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          stepNumber: '2',
          title: 'Connect Once in App Settings',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Open App Settings → Cloudflare Custom Domain.\n'
                '2. Paste your API Token and tap "Fetch My Domains".\n'
                '3. Choose your domain and type a subdomain (e.g. "pocket").\n'
                '4. Tap "Auto-Configure Tunnel & DNS".',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          stepNumber: '3',
          title: 'Automatic Persistent Sharing',
          content: Text(
            'CloudPocket saves your tunnel connector token permanently. Future shares automatically use https://pocket.yourdomain.com without asking again!',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _BoreVpsGuideTab extends StatelessWidget {
  const _BoreVpsGuideTab();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cpColors = Theme.of(context).extension<CloudPocketColors>()!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoBanner(
          icon: Icons.speed_rounded,
          color: cpColors.success,
          title: 'Private Unmetered Bandwidth',
          description:
              'Run your own Bore server on a \$3–\$5/month VPS (e.g., Hetzner, DigitalOcean, Linode, AWS) to bypass public rate limits and get 1Gbps+ transfer speeds.',
        ),
        const SizedBox(height: 16),
        _StepCard(
          stepNumber: '1',
          title: 'Install & Run Bore on Your VPS',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Run Bore server with Docker on your VPS:',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const _CopyableCode(code: 'docker run -d --net=host ekzhang/bore server'),
              const SizedBox(height: 10),
              Text(
                'Or install the binary directly on Linux:',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const _CopyableCode(
                code: 'curl -fsSL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz | tar -xz\n./bore server',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          stepNumber: '2',
          title: 'Firewall Ports',
          content: Text(
            'Ensure port 7835 (TCP) is open on your VPS firewall (e.g. ufw allow 7835/tcp), plus the dynamic port range (1024–65535) for tunnel forwarding.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          stepNumber: '3',
          title: 'Save in CloudPocket Settings',
          content: Text(
            'Go to App Settings → Custom Bore Relay → enter your VPS Host / IP and port 7835. It will be saved permanently.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ZeroSetupGuideTab extends StatelessWidget {
  const _ZeroSetupGuideTab();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cpColors = Theme.of(context).extension<CloudPocketColors>()!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ModeDetailCard(
          title: 'Auto (Recommended)',
          tag: 'Fastest & Zero Setup',
          tagColor: colorScheme.primary,
          description:
              'CloudPocket tests Cloudflare Edge, LocalTunnel, and Bore in parallel within 2 seconds. It connects to whichever server gives the lowest ping from your network, and automatically switches if one drops.',
        ),
        const SizedBox(height: 12),
        _ModeDetailCard(
          title: 'Cloudflare Quick',
          tag: 'Zero Setup HTTPS',
          tagColor: cpColors.warning,
          description:
              'Instant, zero-config HTTPS tunnel over Cloudflare edge without any account or API token. CloudPocket runs the native cloudflared engine to produce a temporary *.trycloudflare.com URL.',
        ),
        const SizedBox(height: 12),
        _ModeDetailCard(
          title: 'Public Bore (bore.pub)',
          tag: 'Direct TCP Socket',
          tagColor: cpColors.success,
          description:
              'Connects over pure TCP sockets to the open-source bore.pub relay. No accounts or tokens needed. Great when HTTP edge tunnels are blocked or throttled.',
        ),
        const SizedBox(height: 12),
        _ModeDetailCard(
          title: 'LocalTunnel (loca.lt)',
          tag: 'HTTP Multiplexed',
          tagColor: colorScheme.tertiary,
          description:
              'Connects through the loca.lt reverse proxy network. You can optionally set a preferred subdomain prefix in Settings (e.g. pocket-share).',
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final String stepNumber;
  final String title;
  final Widget content;

  const _StepCard({
    required this.stepNumber,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                stepNumber,
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  content,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String label;

  const _CodeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.primary,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CopyableCode extends StatelessWidget {
  final String code;

  const _CopyableCode({required this.code});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              code,
              style: TextStyle(
                color: colorScheme.primary,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 16, color: colorScheme.outline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              AppleToast.show(context, 'Command copied to clipboard!');
            },
          ),
        ],
      ),
    );
  }
}

class _ModeDetailCard extends StatelessWidget {
  final String title;
  final String tag;
  final Color tagColor;
  final String description;

  const _ModeDetailCard({
    required this.title,
    required this.tag,
    required this.tagColor,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

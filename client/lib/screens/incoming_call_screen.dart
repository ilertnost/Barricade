import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';

class IncomingCallBanner extends StatelessWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final info = call.incomingCall;
    if (info == null || call.state != CallState.ringing) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 80,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  info.fromDisplayName.isNotEmpty
                      ? info.fromDisplayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.fromDisplayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Strings.t('common.calling'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              _BannerBtn(
                icon: Icons.call_end,
                color: Colors.red,
                onTap: () => call.declineIncomingCall(),
              ),
              const SizedBox(width: 8),
              _BannerBtn(
                icon: Icons.call,
                color: Colors.green,
                onTap: () async {
                  final chId = info.channelId;
                  final fromId = info.fromId;
                  await call.answerIncomingCall();
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          channelId: chId,
                          peerIds: [fromId],
                          video: false,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BannerBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withOpacity(0.2),
      child: IconButton(
        icon: Icon(icon, color: color, size: 22),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}

class IncomingCallFullscreen extends StatelessWidget {
  const IncomingCallFullscreen({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final info = call.incomingCall;
    if (info == null || call.state != CallState.ringing) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CircleAvatar(
              radius: 56,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                info.fromDisplayName.isNotEmpty
                    ? info.fromDisplayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 40,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              info.fromDisplayName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 28,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Strings.t('common.calling'),
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _FullBtn(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: Strings.t('common.decline'),
                    onTap: () => call.declineIncomingCall(),
                  ),
                  _FullBtn(
                    icon: Icons.call,
                    color: Colors.green,
                    label: Strings.t('common.accept'),
                    onTap: () async {
                      final chId = info.channelId;
                      final fromId = info.fromId;
                      await call.answerIncomingCall();
                      if (context.mounted) {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              channelId: chId,
                              peerIds: [fromId],
                              video: false,
                            ),
                          ),
                        );
                      }
                    },
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

class _FullBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _FullBtn({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: color.withOpacity(0.3),
          child: IconButton(
            icon: Icon(icon, color: color, size: 36),
            onPressed: onTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ],
    );
  }
}

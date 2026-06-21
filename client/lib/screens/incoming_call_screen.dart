import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final info = call.incomingCall;

    if (info == null || call.state != CallState.ringing) {
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              UserAvatar(
                name: info.fromDisplayName,
                radius: 50,
              ),
              const SizedBox(height: 20),
              Text(
                info.fromDisplayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Strings.t('common.calling'),
                style: const TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Btn(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onTap: () {
                      call.declineIncomingCall();
                    },
                  ),
                  _Btn(
                    icon: Icons.call,
                    color: Colors.green,
                    onTap: () async {
                      await call.answerIncomingCall();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              channelId: info.channelId,
                              peerIds: [info.fromId],
                              video: true,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 36,
      backgroundColor: color.withOpacity(0.2),
      child: IconButton(
        icon: Icon(icon, color: color, size: 32),
        onPressed: onTap,
      ),
    );
  }
}

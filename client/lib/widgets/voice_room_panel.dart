import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import '../services/ws_service.dart';
import 'user_avatar.dart';

void showVoiceRoomPanel(BuildContext context, {required String channelName}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _VoiceRoomPanel(channelName: channelName),
  );
}

class _VoiceRoomPanel extends StatefulWidget {
  final String channelName;
  const _VoiceRoomPanel({required this.channelName});

  @override
  State<_VoiceRoomPanel> createState() => _VoiceRoomPanelState();
}

class _VoiceRoomPanelState extends State<_VoiceRoomPanel> {
  final Map<String, double> _localVolumes = {};

  @override
  void initState() {
    super.initState();
    final call = context.read<CallService>();
    for (final uid in call.voiceParticipants) {
      _localVolumes[uid] = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<CallService>(
      builder: (_, call, __) {
        final participants = List<String>.from(call.voiceParticipants);
        final myId = ApiService.currentUserId ?? '';
        final allUsers = [myId, ...participants.where((u) => u != myId)];

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.headset, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.channelName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${allUsers.length}',
                        style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Participant list
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    // Self tile
                    _ParticipantTile(
                      userId: myId,
                      displayName: 'Вы',
                      isSelf: true,
                      isMuted: call.muted,
                      isDeafened: call.deafened,
                      volume: 1.0,
                      onVolumeChanged: null,
                    ),
                    // Others
                    for (final uid in allUsers.where((u) => u != myId))
                      _ParticipantTile(
                        userId: uid,
                        displayName: uid,
                        isSelf: false,
                        isMuted: false,
                        isDeafened: false,
                        volume: _localVolumes[uid] ?? 1.0,
                        onVolumeChanged: (v) {
                          setState(() => _localVolumes[uid] = v);
                          call.setVolume(uid, v);
                        },
                      ),
                  ],
                ),
              ),
              // Controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlButton(
                      icon: call.muted ? Icons.mic_off : Icons.mic,
                      label: call.muted ? 'Выкл' : 'Микрофон',
                      active: !call.muted,
                      onTap: () => call.toggleMute(),
                    ),
                    _ControlButton(
                      icon: call.deafened ? Icons.hearing_disabled : Icons.hearing,
                      label: call.deafened ? 'Глухо' : 'Слышать',
                      active: !call.deafened,
                      onTap: () => call.toggleDeafen(),
                    ),
                    _ControlButton(
                      icon: call.isSharingScreen ? Icons.stop_screen_share : Icons.screen_share,
                      label: call.isSharingScreen ? 'Стоп' : 'Экран',
                      active: call.isSharingScreen,
                      iconColor: call.isSharingScreen ? Colors.green : null,
                      onTap: () => call.toggleScreenShare(),
                    ),
                    _ControlButton(
                      icon: Icons.call_end,
                      label: 'Выйти',
                      active: false,
                      iconColor: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        call.leaveVoiceRoom();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final String userId;
  final String displayName;
  final bool isSelf;
  final bool isMuted;
  final bool isDeafened;
  final double volume;
  final ValueChanged<double>? onVolumeChanged;

  const _ParticipantTile({
    required this.userId,
    required this.displayName,
    required this.isSelf,
    required this.isMuted,
    required this.isDeafened,
    required this.volume,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          UserAvatar(name: displayName, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    if (isSelf)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('(Вы)', style: TextStyle(color: cs.outline, fontSize: 12)),
                      ),
                    if (isMuted)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.mic_off, size: 14, color: cs.error),
                      ),
                  ],
                ),
                if (onVolumeChanged != null)
                  Slider(
                    value: volume,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: onVolumeChanged!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = iconColor ?? (active ? Colors.green : cs.outline);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

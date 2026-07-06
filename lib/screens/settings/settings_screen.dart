import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/avatar_style.dart';
import '../../models/skeleton_3d.dart';
import '../../services/app_settings.dart';
import '../../services/session_repository.dart';
import '../../services/unity_connection_service.dart';
import '../../services/unity_launch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeleton_3d_view.dart';

/// Mirrors the Unity in-game settings (FSR connection type / COM port / host)
/// plus dashboard-only options: per-sensor mock data, sessions folder, WS URI.
/// Values are pushed to Unity as part of `configure_session` when a session
/// starts, so changing them here is enough.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final launcher = context.watch<UnityLaunchService>();

    return Scaffold(
      body: Column(children: [
        // header
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.panelHeader,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.settings_outlined, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('Settings',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                _section('FSR PRESSURE INSOLE', [
                  _label('Connection type'),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final t in kFsrConnTypes) ...[
                      Expanded(
                        child: _choice(
                          t,
                          settings.fsrConnType == t,
                          () => settings.setFsrConnType(t),
                        ),
                      ),
                      if (t != kFsrConnTypes.last) const SizedBox(width: 8),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  if (settings.fsrConnType == 'USB') ...[
                    _label('Serial port'),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: settings.availablePorts.isEmpty
                            ? Text('No COM ports detected — plug in the insole receiver',
                                style: GoogleFonts.schibstedGrotesk(
                                    color: AppColors.textSecondary, fontSize: 11))
                            : Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final port in settings.availablePorts)
                                  SizedBox(
                                    width: 110,
                                    child: _choice(port, settings.fsrUsbPort == port,
                                        () => settings.setFsrUsbPort(port)),
                                  ),
                              ]),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Rescan ports',
                        onPressed: settings.refreshPorts,
                        icon: const Icon(Icons.refresh, size: 18, color: AppColors.accent),
                      ),
                    ]),
                    const SizedBox(height: 14),
                  ],
                  if (settings.fsrConnType == 'WebSocket' ||
                      settings.fsrConnType == 'TCP') ...[
                    _label('Host URI'),
                    const SizedBox(height: 6),
                    _textField(
                      initial: settings.fsrUri,
                      hint: 'e.g. ws://192.168.0.20:81',
                      onChanged: settings.setFsrUri,
                    ),
                    const SizedBox(height: 10),
                    _label('API key (optional)'),
                    const SizedBox(height: 6),
                    _textField(
                      initial: settings.fsrApiKey,
                      hint: 'Leave empty if not required',
                      onChanged: settings.setFsrApiKey,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    'These map 1:1 to the Unity settings screen and are pushed to Unity when a session starts.',
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ]),
                _section('SENSORS', [
                  _switchRow('ZED camera (motion tracking)', settings.zedEnabled,
                      settings.setZedEnabled),
                  _switchRow(
                      'FSR pressure insoles', settings.fsrEnabled, settings.setFsrEnabled),
                  _switchRow('EEG headset', settings.eegEnabled, settings.setEegEnabled),
                ]),
                _section('MOVEMENT AVATAR', [
                  Text(
                    'How the 3D figure is drawn everywhere it appears — the movement mirror, exercise previews and protocol block guides. Every style uses the same recorded motion, so switching is instant and safe.',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textSecondary, fontSize: 10.5),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 220,
                      child: Skeleton3DView(
                        skeleton: Skeleton3D.seatedDemo(kneeAngleDeg: 32),
                        style: settings.avatarStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final s in AvatarStyle.values)
                    _avatarChoice(s, settings.avatarStyle == s,
                        () => settings.setAvatarStyle(s)),
                ]),
                _section('MOCK DATA (dashboard testing)', [
                  Text(
                    'Mocked sensors animate with generated data so you can test the live view and replay without hardware or Unity. Non-mocked sensors keep showing real data.',
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10.5),
                  ),
                  const SizedBox(height: 8),
                  _switchRow('Mock motion / 3D avatar', settings.mockMotion, (v) {
                    settings.setMockMotion(v);
                    context.read<UnityConnectionService>().setMocks(motion: v);
                  }, color: AppColors.accentOrange),
                  _switchRow('Mock FSR pressure', settings.mockFsr, (v) {
                    settings.setMockFsr(v);
                    context.read<UnityConnectionService>().setMocks(fsr: v);
                  }, color: AppColors.accentOrange),
                  _switchRow('Mock EEG', settings.mockEeg, (v) {
                    settings.setMockEeg(v);
                    context.read<UnityConnectionService>().setMocks(eeg: v);
                  }, color: AppColors.accentOrange),
                ]),
                _section('UNITY ENGINE', [
                  _label('Executable path'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _pathBox(launcher.exePath.isEmpty
                        ? 'Not set'
                        : launcher.exePath)),
                    const SizedBox(width: 8),
                    _browseBtn(() async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['exe'],
                        dialogTitle: 'Select Unity executable',
                      );
                      final path = result?.files.single.path;
                      if (path != null && context.mounted) {
                        context.read<UnityLaunchService>().setExePath(path);
                      }
                    }),
                  ]),
                  const SizedBox(height: 14),
                  _label('WebSocket URI'),
                  const SizedBox(height: 6),
                  _textField(
                    initial: settings.wsUri,
                    hint: 'ws://localhost:8765',
                    onChanged: settings.setWsUri,
                  ),
                ]),
                _section('SESSION LIBRARY', [
                  _label('Sessions folder (written by Unity)'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _pathBox(settings.sessionsRoot)),
                    const SizedBox(width: 8),
                    _browseBtn(() async {
                      final dir = await FilePicker.platform
                          .getDirectoryPath(dialogTitle: 'Select sessions folder');
                      if (dir != null && context.mounted) {
                        settings.setSessionsRoot(dir);
                        context.read<SessionRepository>().setRoot(dir);
                      }
                    }),
                  ]),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () {
                      final def = AppSettings.defaultSessionsRoot();
                      settings.setSessionsRoot(def);
                      context.read<SessionRepository>().setRoot(def);
                    },
                    icon: const Icon(Icons.restore, size: 13),
                    label: Text('Reset to default',
                        style: GoogleFonts.schibstedGrotesk(fontSize: 10.5)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── building blocks ─────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _label(String s) => Text(s,
      style: GoogleFonts.schibstedGrotesk(
          color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500));

  Widget _choice(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.accent : AppColors.border),
          ),
          child: Text(label,
              style: GoogleFonts.schibstedGrotesk(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      );

  Widget _avatarChoice(AvatarStyle s, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.10)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? AppColors.accent : AppColors.border,
                  width: active ? 1.5 : 1),
            ),
            child: Row(children: [
              Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: active ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label,
                          style: GoogleFonts.schibstedGrotesk(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(s.description,
                          style: GoogleFonts.schibstedGrotesk(
                              color: AppColors.textSecondary, fontSize: 10.5)),
                    ]),
              ),
            ]),
          ),
        ),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged,
          {Color color = AppColors.accent}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 12))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: color,
            thumbColor: const WidgetStatePropertyAll(Colors.white),
          ),
        ]),
      );

  Widget _textField({
    required String initial,
    required String hint,
    required ValueChanged<String> onChanged,
  }) =>
      TextFormField(
        initialValue: initial,
        onChanged: onChanged,
        style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11),
          filled: true,
          fillColor: AppColors.surfaceLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      );

  Widget _pathBox(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 11)),
      );

  Widget _browseBtn(VoidCallback onTap) => ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.folder_open, size: 15),
        label: const Text('Browse'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceLight,
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
}

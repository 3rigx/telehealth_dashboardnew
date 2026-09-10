import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../services/app_settings.dart';
import '../../services/deidentified_export.dart';
import '../../services/participant_repository.dart';
import '../../services/session_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/participant_picker.dart';

/// Pseudonymous participant registry: enrolment (consent-gated), status,
/// de-identified export and explicit data deletion. Codes only — the
/// code↔identity log lives outside this software by design.
class ParticipantsScreen extends StatelessWidget {
  const ParticipantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ParticipantRepository>();
    final settings = context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: AppColors.background,
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
                child:
                    Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.badge_outlined, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('Participants',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => enrolParticipantDialog(context),
              icon: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('Enrol participant'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                textStyle: GoogleFonts.schibstedGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: repo.participants.isEmpty
                  ? _empty(context)
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _privacyBanner(),
                        const SizedBox(height: 16),
                        for (final p in repo.participants)
                          _ParticipantCard(
                              participant: p, sessionsRoot: settings.sessionsRoot),
                      ],
                    ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _empty(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.badge_outlined, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No participants enrolled yet',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Enrolment records consent and issues a pseudonymous code (P-001, …).\n'
            'Sessions and protocol runs can then only be started for an enrolled code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => enrolParticipantDialog(context),
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Enrol the first participant'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: Colors.white),
          ),
        ],
      );

  Widget _privacyBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.privacy_tip_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This registry holds pseudonymous codes and consent status only. Keep the '
              'code–identity enrolment log outside this computer (paper or the PI\'s '
              'separate encrypted file).',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary, fontSize: 11.5),
            ),
          ),
        ]),
      );
}

class _ParticipantCard extends StatelessWidget {
  final Participant participant;
  final String sessionsRoot;
  const _ParticipantCard({required this.participant, required this.sessionsRoot});

  int get _sessionCount {
    try {
      final d =
          Directory('$sessionsRoot${Platform.pathSeparator}${participant.code}');
      if (!d.existsSync()) return 0;
      return d.listSync().whereType<Directory>().length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final withdrawn = p.status == ParticipantStatus.withdrawn;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (withdrawn ? AppColors.textSecondary : AppColors.accent)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.badge_outlined,
              size: 20,
              color: withdrawn ? AppColors.textSecondary : AppColors.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(p.code,
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              _statusChip(p.status),
            ]),
            const SizedBox(height: 3),
            Text(
              'Enrolled ${p.enrolledUtc.toLocal().toString().split(' ').first}'
              ' · consent ${p.consentVersion}'
              '${p.gender != ParticipantGender.unspecified ? ' · ${p.gender.label}' : ''}'
              ' · $_sessionCount session${_sessionCount == 1 ? '' : 's'}'
              '${p.notes.isNotEmpty ? ' · ${p.notes}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'Actions',
          color: AppColors.surface,
          icon: Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
          onSelected: (a) => _action(context, a),
          itemBuilder: (_) => [
            _item('export', Icons.ios_share, 'Export de-identified data…'),
            if (p.status == ParticipantStatus.active)
              _item('complete', Icons.task_alt, 'Mark completed'),
            if (p.status == ParticipantStatus.active)
              _item('withdraw', Icons.person_off_outlined, 'Withdraw from study'),
            _item('delete_data', Icons.delete_outline, 'Delete recorded data…',
                danger: true),
            _item('remove', Icons.person_remove_outlined, 'Remove from registry…',
                danger: true),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _item(String v, IconData i, String label,
          {bool danger = false}) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(i, size: 16, color: danger ? AppColors.accentRed : AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.schibstedGrotesk(
                  color: danger ? AppColors.accentRed : AppColors.textPrimary,
                  fontSize: 12.5)),
        ]),
      );

  Widget _statusChip(ParticipantStatus s) {
    final color = switch (s) {
      ParticipantStatus.active => AppColors.accentGreen,
      ParticipantStatus.completed => AppColors.accent,
      ParticipantStatus.withdrawn => AppColors.accentOrange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(s.label,
          style: GoogleFonts.schibstedGrotesk(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _action(BuildContext context, String action) async {
    final repo = context.read<ParticipantRepository>();
    switch (action) {
      case 'complete':
        await repo.setStatus(participant.code, ParticipantStatus.completed);
      case 'withdraw':
        final ok = await _confirm(
          context,
          'Withdraw ${participant.code}?',
          'The participant will no longer be selectable for sessions. Recorded '
              'data is kept until you delete it explicitly (a withdrawal may or '
              'may not include erasure — follow your consent form).',
          confirmLabel: 'Withdraw',
        );
        if (ok) await repo.setStatus(participant.code, ParticipantStatus.withdrawn);
      case 'export':
        await _export(context);
      case 'delete_data':
        final n = _sessionCount;
        final ok = await _confirm(
          context,
          'Delete all recorded data for ${participant.code}?',
          'Permanently deletes $n recorded session${n == 1 ? '' : 's'} from disk '
              '(right to erasure). The registry entry stays. This cannot be undone.',
          confirmLabel: 'Delete data',
          danger: true,
        );
        if (ok) {
          try {
            final d = Directory(
                '$sessionsRoot${Platform.pathSeparator}${participant.code}');
            if (d.existsSync()) d.deleteSync(recursive: true);
            if (context.mounted) {
              context.read<SessionRepository>().refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Recorded data for ${participant.code} deleted.')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
            }
          }
        }
      case 'remove':
        final ok = await _confirm(
          context,
          'Remove ${participant.code} from the registry?',
          'Only removes the registry entry (code + consent record). Recorded data '
              'folders are not touched. The code will not be reissued.',
          confirmLabel: 'Remove',
          danger: true,
        );
        if (ok) await repo.remove(participant.code);
    }
  }

  Future<void> _export(BuildContext context) async {
    var realias = false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Export de-identified data',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Bundles ${participant.code}\'s sessions as a zip with calendar dates '
                'replaced by study days and notes fields stripped.',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: realias,
                onChanged: (v) => setState(() => realias = v ?? false),
                title: Text('Re-alias the code (${participant.code} → EXP-…)',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textPrimary, fontSize: 12.5)),
                subtitle: Text(
                    'Use when sharing outside the study team, so the export can\'t be '
                    'linked back to this registry.',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textSecondary, fontSize: 10.5)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              child: const Text('Choose location…'),
            ),
          ],
        ),
      ),
    );
    if (proceed != true || !context.mounted) return;

    final alias = realias
        ? 'EXP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
        : null;
    final outId = alias ?? participant.code;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save de-identified export',
      fileName: '${outId}_deidentified.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (path == null || !context.mounted) return;

    try {
      final n = await DeidentifiedExport(
        participant: participant,
        sessionsRoot: sessionsRoot,
        alias: alias,
      ).run(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(alias == null
              ? 'Exported $n files → $path'
              : 'Exported $n files as $alias → $path  (record the alias↔code link '
                  'in your enrolment log if you need it)'),
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body,
      {required String confirmLabel, bool danger = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textPrimary, fontSize: 15)),
        content: Text(body,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textSecondary, fontSize: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(
                    color: danger ? AppColors.accentRed : AppColors.accent)),
          ),
        ],
      ),
    );
    return r == true;
  }
}

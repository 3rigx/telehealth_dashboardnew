import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/participant.dart';
import '../services/participant_repository.dart';
import '../theme/app_theme.dart';

/// Strict participant selection: a session/run can only use a code that exists
/// in the registry (enrolled + consented + active). There is deliberately no
/// free-text entry — that is the whole privacy guarantee.
///
/// Returns the chosen code, or null if cancelled.
Future<String?> pickParticipant(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => _ParticipantPickerDialog(initial: initial),
  );
}

class _ParticipantPickerDialog extends StatelessWidget {
  final String? initial;
  const _ParticipantPickerDialog({this.initial});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ParticipantRepository>();
    final list = repo.selectable;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Select participant',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No enrolled participants yet.\nEnrol one to begin — consent is recorded at enrolment.',
                textAlign: TextAlign.center,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 12.5),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(shrinkWrap: true, children: [
                for (final p in list)
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    tileColor: p.code == initial
                        ? AppColors.accent.withValues(alpha: 0.08)
                        : null,
                    leading: const Icon(Icons.badge_outlined,
                        size: 18, color: AppColors.accent),
                    title: Text(p.code,
                        style: GoogleFonts.schibstedGrotesk(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        'Enrolled ${p.enrolledUtc.toLocal().toString().split(' ').first}'
                        ' · consent ${p.consentVersion}',
                        style: GoogleFonts.schibstedGrotesk(
                            color: AppColors.textSecondary, fontSize: 10.5)),
                    onTap: () => Navigator.pop(context, p.code),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.privacy_tip_outlined,
                size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Codes only — no names. Identity records stay outside this software.',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await enrolParticipantDialog(context);
            if (p != null && context.mounted) Navigator.pop(context, p.code);
          },
          icon: const Icon(Icons.person_add_alt, size: 16),
          label: const Text('Enrol new…'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
        ),
      ],
    );
  }
}

/// Consent-gated enrolment. The Enrol button stays disabled until the operator
/// confirms the information sheet + written consent; only then is a code issued.
Future<Participant?> enrolParticipantDialog(BuildContext context) {
  final repo = context.read<ParticipantRepository>();
  final consentVersionCtrl = TextEditingController(text: 'v1.0');
  final notesCtrl = TextEditingController();
  var infoSheet = false;
  var writtenConsent = false;
  var gender = ParticipantGender.unspecified;

  return showDialog<Participant>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setState) {
        final canEnrol = infoSheet && writtenConsent;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Enrol participant — ${repo.nextCode()}',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'The next free code is assigned automatically. Record the code–identity '
                'link in your enrolment log (paper / PI file) — it is never stored here.',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: infoSheet,
                onChanged: (v) => setState(() => infoSheet = v ?? false),
                title: Text('Participant information sheet provided & explained',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textPrimary, fontSize: 12.5)),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: writtenConsent,
                onChanged: (v) => setState(() => writtenConsent = v ?? false),
                title: Text('Written informed consent obtained & filed',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textPrimary, fontSize: 12.5)),
              ),
              const SizedBox(height: 8),
              Text('Gender (optional — kept in de-identified exports)',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in const [
                  ParticipantGender.female,
                  ParticipantGender.male,
                  ParticipantGender.nonBinary,
                  ParticipantGender.notDisclosed,
                ])
                  ChoiceChip(
                    label: Text(g.label,
                        style: GoogleFonts.schibstedGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: gender == g
                                ? Colors.white
                                : AppColors.textSecondary)),
                    selected: gender == g,
                    onSelected: (v) => setState(
                        () => gender = v ? g : ParticipantGender.unspecified),
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceLight,
                    side: BorderSide(
                        color: gender == g ? AppColors.accent : AppColors.border),
                    showCheckmark: false,
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: consentVersionCtrl,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: _dec('Consent form version', 'e.g. v1.0'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: _dec('Clinical notes (optional)',
                    'e.g. left-side weakness — NO identifying information'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: canEnrol
                  ? () async {
                      final p = await repo.enrol(
                        consentVersion: consentVersionCtrl.text.trim().isEmpty
                            ? 'v1.0'
                            : consentVersionCtrl.text.trim(),
                        gender: gender,
                        notes: notesCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, p);
                    }
                  : null,
              icon: const Icon(Icons.how_to_reg, size: 16),
              label: const Text('Enrol'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white),
            ),
          ],
        );
      },
    ),
  );
}

InputDecoration _dec(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle:
          GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12),
      hintStyle:
          GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11),
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
    );

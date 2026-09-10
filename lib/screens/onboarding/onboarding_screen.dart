import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';

/// First-run setup guide: what the system is, what hardware/software it
/// needs, the privacy rules, and the study workflow. Auto-opens once on the
/// first launch (persisted via [AppSettings.onboardingSeen]) and can be
/// reopened any time from Settings → Help.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    context.read<AppSettings>().setOnboardingSeen(true);
    Navigator.of(context).maybePop();
  }

  void _go(int delta) {
    final next = (_page + delta).clamp(0, _pageCount - 1);
    _controller.animateToPage(next,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // ── top bar: brand + skip ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.accessibility_new,
                    color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Text('TeleRehab — Setup Guide',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: _finish,
                child: Text('Skip',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          // ── pages ─────────────────────────────────────────────────────
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: const [
                _WelcomePage(),
                _RequirementsPage(),
                _PrivacyPage(),
                _WorkflowPage(),
                _TipsPage(),
              ],
            ),
          ),
          // ── bottom bar: dots + back/next ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
            child: Row(children: [
              for (var i = 0; i < _pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? AppColors.accent
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              if (_page > 0)
                OutlinedButton(
                  onPressed: () => _go(-1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                  child: Text('Back',
                      style: GoogleFonts.schibstedGrotesk(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _page == _pageCount - 1 ? _finish : () => _go(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                ),
                child: Text(_page == _pageCount - 1 ? 'Get started' : 'Next',
                    style: GoogleFonts.schibstedGrotesk(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── shared page scaffolding ───────────────────────────────────────────────────

class _Page extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _Page({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 27),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final bool optional;
  const _Row(this.icon, this.color, this.title, this.desc,
      {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title,
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (optional) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('OPTIONAL',
                      style: GoogleFonts.schibstedGrotesk(
                          color: AppColors.textSecondary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(desc,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String desc;
  const _Step(this.n, this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text('$n',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(desc,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}

// ── page 1: welcome ───────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.waving_hand_outlined,
      color: AppColors.accent,
      title: 'Welcome to TeleRehab',
      subtitle:
          'A research dashboard for tele-rehabilitation studies: capture multi-sensor '
          'movement sessions, run experiment protocols, and review or export the data.',
      children: const [
        _Row(Icons.accessibility_new, AppColors.accent, 'Motion capture',
            'A ZED 2i depth camera tracks the whole body in 3D — no markers, no suit. '
                'Sessions are recorded and replayed as a skeleton avatar.'),
        _Row(Icons.sensors, AppColors.accentCyan, 'Multi-sensor recording',
            'Plantar-pressure insoles (FSR) and an EEG headset can record in sync '
                'with the motion data.'),
        _Row(Icons.science_outlined, AppColors.accentGreen, 'Experiment protocols',
            'Design block-based protocols with exercise classes, timed phases and '
                'event markers — then run them live with a participant.'),
        _Row(Icons.info_outline, AppColors.accentOrange, 'Research use only',
            'This system is a research tool. It is not a medical device and must '
                'not be used for diagnosis or treatment decisions.'),
      ],
    );
  }
}

// ── page 2: requirements ──────────────────────────────────────────────────────

class _RequirementsPage extends StatelessWidget {
  const _RequirementsPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.checklist_rtl,
      color: AppColors.accentCyan,
      title: 'What you need',
      subtitle:
          'The dashboard is one half of the system — the Unity capture app does the '
          'recording. Check these before your first real session.',
      children: const [
        _Row(Icons.computer, AppColors.accentCyan, 'Windows 10/11 PC',
            'With enough free disk space for recordings (a session can be tens of MB; '
                'plan several GB for a study). Full-disk encryption (BitLocker) is '
                'strongly recommended — see Settings → Data Protection.'),
        _Row(Icons.videogame_asset_outlined, AppColors.accentCyan,
            'Unity capture app',
            'The "Smart Game" Unity application installed on this same PC. Point '
                'Settings → Unity Engine → Executable path at its .exe — the dashboard '
                'can then launch and drive it automatically (it talks to Unity on '
                'ws://localhost:8765).'),
        _Row(Icons.camera_outdoor, AppColors.accentCyan, 'ZED 2i camera',
            'Stereolabs ZED 2i on USB 3.0, with the ZED SDK installed and an NVIDIA '
                '(CUDA-capable) GPU — body tracking runs on the GPU. Place the camera '
                'so the participant\'s whole body is in view, ~2–4 m away.'),
        _Row(Icons.directions_walk, AppColors.accentGreen, 'FSR pressure insoles',
            'Plantar-pressure insoles connected over USB (COM port) or Wi-Fi. '
                'Configure the connection in Settings → FSR Pressure Insole.',
            optional: true),
        _Row(Icons.psychology_outlined, AppColors.accentGreen, 'EEG headset',
            'Unicorn Hybrid Black with its Bluetooth dongle (appears as a COM port). '
                'Enable it per-session in the Sensors toggles.',
            optional: true),
        _Row(Icons.smart_toy_outlined, AppColors.accentOrange, 'No hardware yet?',
            'Turn on Mock Data in Settings — every screen works with generated '
                'signals so you can explore the whole app without any equipment.'),
      ],
    );
  }
}

// ── page 3: privacy ───────────────────────────────────────────────────────────

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.privacy_tip_outlined,
      color: AppColors.accentGreen,
      title: 'Privacy comes first',
      subtitle:
          'The dashboard is built around pseudonymity — it never stores names, and '
          'sessions can only be started for an enrolled participant code.',
      children: const [
        _Row(Icons.badge_outlined, AppColors.accentGreen, 'Enrol before recording',
            'Open Participants → Enrol. Confirm the information sheet and written '
                'consent, and a code (P-001, P-002, …) is issued automatically. '
                'Sessions and protocol runs are then picked from this list — IDs are '
                'never typed.'),
        _Row(Icons.edit_off_outlined, AppColors.accentGreen, 'Codes only, no names',
            'Keep the code-to-identity enrolment log on paper or in the PI\'s separate '
                'encrypted file — never on this computer. The software cannot leak '
                'what it never holds.'),
        _Row(Icons.ios_share, AppColors.accentCyan, 'De-identified export',
            'Share data via Participants → Export: calendar dates become study days, '
                'free-text notes are stripped, and the code can be re-aliased.'),
        _Row(Icons.lock_outline, AppColors.accentOrange, 'Check disk encryption',
            'Raw recordings are plain files on disk. Settings → Data Protection shows '
                'whether BitLocker is on for the data drive — keep it green.'),
      ],
    );
  }
}

// ── page 4: workflow ──────────────────────────────────────────────────────────

class _WorkflowPage extends StatelessWidget {
  const _WorkflowPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.route_outlined,
      color: AppColors.accent,
      title: 'Running a study',
      subtitle: 'The typical end-to-end workflow, in order:',
      children: const [
        _Step(1, 'Enrol the participant',
            'Participants → Enrol participant. Consent is recorded and a code is issued.'),
        _Step(2, 'Record exercise guides (optional)',
            'Exercises → Record with ZED: a clinician demonstrates a movement once and '
                'it becomes a looping avatar guide participants can follow.'),
        _Step(3, 'Design the protocol',
            'Protocol Builder: define exercise classes, attach an avatar guide to each, '
                'set block/instruction/reset timing and the counterbalancing order.'),
        _Step(4, 'Run the session',
            'Protocol Builder → Run live → pick the participant. The dashboard starts '
                'Unity, checks every enabled sensor\'s signal quality, and gates Begin '
                'until all checks pass (an operator override exists). Markers are '
                'written continuously during the run.'),
        _Step(5, 'Review & export',
            'Replay a session to inspect the movement and signals. Export de-identified '
                'bundles from the Participants section for analysis.'),
        _Row(Icons.monitor_heart_outlined, AppColors.accentCyan, 'Quick capture',
            'For a single unstructured recording (no protocol), use Live Exercise on '
                'the home screen instead.'),
      ],
    );
  }
}

// ── page 5: tips ──────────────────────────────────────────────────────────────

class _TipsPage extends StatelessWidget {
  const _TipsPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.tips_and_updates_outlined,
      color: AppColors.accentOrange,
      title: 'Good to know',
      subtitle: 'A few things that save time on capture days:',
      children: const [
        _Row(Icons.link, AppColors.accentGreen, 'Watch the Unity status',
            'The home screen shows Unity as Connected / Running / Not running. '
                'Recording only works while it is green — the dashboard can launch '
                'Unity for you when you start a session.'),
        _Row(Icons.fact_check_outlined, AppColors.accentGreen, 'Trust the signal check',
            'Before Begin, each enabled sensor is verified (skeleton tracked, insoles '
                'loaded, EEG in range). If something fails, fix it rather than '
                'overriding — bad signal is unusable data.'),
        _Row(Icons.person_outline, AppColors.accentCyan, 'Pick the avatar look',
            'Settings → Movement Avatar offers five figure styles (lines, mannequin, '
                'neon, blocky, cartoon) with a live preview.'),
        _Row(Icons.folder_outlined, AppColors.accentCyan, 'Where the data lives',
            'Recordings are saved per participant code under the Sessions folder '
                '(see Settings → Session Library). Protocols, exercises and the '
                'participant registry live in sibling folders.'),
        _Row(Icons.help_outline, AppColors.accentOrange, 'Reopen this guide',
            'Settings → Help → "Show setup guide" brings this walkthrough back '
                'any time.'),
      ],
    );
  }
}

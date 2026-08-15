import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/apply_bar.dart';
import 'widgets/connection_card.dart';
import 'widgets/dpi_stage_editor.dart';
import 'widgets/explained_setting.dart';
import 'widgets/status_monitor.dart';
import 'x3_device.dart';
import 'x3_prefs.dart';
import 'x3_profile.dart';
import 'x3_status.dart';

/// The whole app lives on this one scrolling page: connect the mouse, tweak
/// sensitivity / response / power, and press Apply.
class X3SettingsPage extends StatefulWidget {
  const X3SettingsPage({super.key});

  @override
  State<X3SettingsPage> createState() => _X3SettingsPageState();
}

class _X3SettingsPageState extends State<X3SettingsPage> {
  final X3DeviceService _service = X3DeviceService();
  final X3Prefs _prefs = X3Prefs();

  // Initialized to defaults synchronously so the first build never sees a
  // null profile; _loadInitial() replaces it with the persisted profile.
  X3Profile _profile = X3Profile.defaults();
  bool _connected = false;
  bool _busy = false;
  String _statusMessage = '';
  final List<X3StatusReport> _reports = [];
  StreamSubscription<X3StatusReport>? _statusSub;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final profile = await _prefs.loadCurrent();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _statusMessage = 'Looking for your mouse…';
    });
    // Auto-connect on startup: wired USB first, then the 2.4G dongle.
    await _connect(fromStartup: true);
  }

  void _updateProfile(X3Profile next) {
    setState(() => _profile = next);
    _prefs.saveCurrent(next); // fire-and-forget auto-save
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ---- Connection -------------------------------------------------------

  Future<void> _connect({bool fromStartup = false}) async {
    setState(() => _busy = true);
    final message = await _service.connect();
    final connected = _service.isConnected;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _connected = connected;
      _statusMessage = connected
          ? message
          : (fromStartup
                ? 'Couldn’t find the mouse. Plug in the wired mouse or the '
                      'wireless dongle, then press “Connect mouse”.'
                : message);
    });
    if (connected) _startStatusWatch();
  }

  void _startStatusWatch() {
    _statusSub?.cancel();
    _reports.clear();
    _statusSub = _service.watchStatus().listen((report) {
      if (!mounted) return;
      var stageChanged = false;
      setState(() {
        _reports.add(report);
        if (_reports.length > 8) _reports.removeAt(0);
        // Follow the mouse's DPI button: sync the active-stage selection.
        final stage = report.dpiStage;
        if (report.kind == X3StatusKind.dpiStage &&
            stage != null &&
            stage - 1 != _profile.activeStage) {
          _profile = _profile.copyWith(activeStage: stage - 1);
          stageChanged = true;
        }
      });
      if (stageChanged) _prefs.saveCurrent(_profile);
    });
  }

  Future<void> _disconnect() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _reports.clear();
      _statusMessage =
          'Disconnected. Change settings any time — press '
          '“Apply to mouse” after reconnecting.';
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  // ---- Actions ----------------------------------------------------------

  Future<void> _apply() async {
    final lastApplied = await _prefs.loadApplied();
    final plan = buildApplyPlan(_profile, lastApplied);
    if (!plan.anything) {
      _showSnack('Everything is already up to date on the mouse.');
      return;
    }
    setState(() => _busy = true);
    final result = await _service.sendAll(
      report04: plan.send04 ? _profile.toReport04() : null,
      report06: plan.send06 ? _profile.toReport06() : null,
      report05: plan.send05 ? _profile.toReport05() : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      await _prefs.saveApplied(_profile);
      final what = plan.changed.join(', ');
      _showSnack('Applied to the mouse: $what');
    } else {
      final failed = result.messages
          .where((m) => m.contains('failed'))
          .join(', ');
      _showSnack('Something went wrong applying: $failed');
    }
  }

  Future<void> _reset() async {
    await _prefs.reset();
    _updateProfile(X3Profile.defaults());
    _showSnack('Reset to the factory default settings.');
  }

  Future<void> _saveProfile() async {
    final name = await _promptText('Save profile', 'Profile name', 'My setup');
    if (name == null || name.trim().isEmpty) return;
    await _prefs.saveNamed(name.trim(), _profile);
    _showSnack('Saved profile “${name.trim()}”.');
  }

  Future<void> _loadProfile() async {
    final names = await _prefs.profileNames();
    if (!mounted) return;
    if (names.isEmpty) {
      _showSnack(
        'No saved profiles yet. Use “Profiles → Save profile…” first.',
      );
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _ProfilePickerDialog(names: names),
    );
    if (selected == null) return;
    final profile = await _prefs.loadNamed(selected);
    if (profile == null) {
      _showSnack('Could not load “$selected”.');
      return;
    }
    _updateProfile(profile);
    _showSnack('Loaded profile “$selected”.');
  }

  Future<String?> _promptText(
    String title,
    String label,
    String initial,
  ) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  // ---- Layout -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      // padding: const EdgeInsets.symmetric(vertical: 24),
                      children: [
                        _header(context),
                        const SizedBox(height: 8),
                        ConnectionCard(
                          connected: _connected,
                          busy: _busy,
                          productName: _service.config?.productName ?? '',
                          statusMessage: _statusMessage,
                          onConnect: () => _connect(),
                          onDisconnect: _disconnect,
                        ),
                        _dpiCard(context),
                        _performanceCard(context),
                        _powerCard(context),
                        StatusMonitor(connected: _connected, reports: _reports),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ApplyBar(
                connected: _connected,
                busy: _busy,
                onApply: _apply,
                onReset: _reset,
                onSaveProfile: _saveProfile,
                onLoadProfile: _loadProfile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.mouse, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shark X3 Config',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Mouse settings made simple',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _dpiCard(BuildContext context) {
    final theme = Theme.of(context);
    final led = _profile.activeLed;
    return _sectionCard(
      context,
      icon: Icons.speed,
      title: 'Sensitivity (DPI)',
      subtitle:
          'How fast the cursor moves. Each level has its own LED color — '
          'pick which level is active.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: led.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: led.color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: led.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active: ${_profile.activeDpi} DPI · ${led.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < x3StageLed.length; i++)
          DpiStageEditor(
            stage: i,
            dpi: _profile.dpi[i],
            isActive: _profile.activeStage == i,
            onSelectActive: () =>
                _updateProfile(_profile.copyWith(activeStage: i)),
            onChanged: (v) {
              final dpi = List<int>.of(_profile.dpi)..[i] = v;
              _updateProfile(_profile.copyWith(dpi: dpi));
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Tip: the mouse LED shows the color of the active level, so you '
            'can always tell which sensitivity you’re on.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _performanceCard(BuildContext context) {
    return _sectionCard(
      context,
      icon: Icons.tune,
      title: 'Mouse response',
      subtitle: 'How the mouse tracks and reports movement.',
      children: [
        ExplainedSetting(
          title: 'Polling rate',
          icon: Icons.published_with_changes,
          explanation:
              'How often the mouse tells your computer where it is. '
              'Higher is smoother and more responsive.',
          detail:
              'The mouse reports its position 125, 250, 500 or 1000 times '
              'per second. 1000 Hz feels the most responsive and is what most '
              'people use. Lower rates use a little less battery but can feel '
              'slightly less smooth.',
          control: SegmentedButton<int>(
            segments: [
              for (final hz in [125, 250, 500, 1000])
                ButtonSegment(value: hz, label: Text('$hz')),
            ],
            selected: {_profile.polling},
            onSelectionChanged: (s) =>
                _updateProfile(_profile.copyWith(polling: s.first)),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Lift-off distance',
          icon: Icons.height,
          explanation:
              'How far you must lift the mouse before the sensor stops '
              'tracking.',
          detail:
              '1 mm stops tracking as soon as you lift the mouse slightly '
              '— handy if you lift and reposition it a lot. 2 mm is more '
              'forgiving and keeps tracking a little longer during a lift.',
          control: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 mm')),
              ButtonSegment(value: 2, label: Text('2 mm')),
            ],
            selected: {_profile.lod},
            onSelectionChanged: (s) =>
                _updateProfile(_profile.copyWith(lod: s.first)),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Ripple control',
          icon: Icons.waves,
          explanation:
              'Smooths tiny jitter in very small, slow movements. '
              'On feels steadier; off feels more direct.',
          detail:
              'When on, the mouse smooths out micro-jitter so very small '
              'movements feel steadier. Some people prefer it off for a more '
              'raw, direct feel. Try both and keep what feels best.',
          trailing: Switch(
            value: _profile.ripple,
            onChanged: (v) => _updateProfile(_profile.copyWith(ripple: v)),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Angle snap',
          icon: Icons.straighten,
          explanation:
              'Straightens diagonal movement into horizontal / vertical lines. '
              'Most people leave it off.',
          detail:
              'Angle snap helps draw perfectly straight horizontal and '
              'vertical lines (nice for some design work), but it can make '
              'freehand curves feel slightly sticky. Most people prefer it off.',
          trailing: Switch(
            value: _profile.angle,
            onChanged: (v) => _updateProfile(_profile.copyWith(angle: v)),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Motion sync',
          icon: Icons.sync,
          explanation:
              'Synchronizes X and Y sampling so diagonal movement feels '
              'smooth and uniform. Leave this on.',
          detail:
              'Motion sync aligns the timing of the X and Y axis samples, '
              'which makes diagonal movement feel smooth and consistent. '
              'There is no real reason to turn it off.',
          trailing: Switch(
            value: _profile.motion,
            onChanged: (v) => _updateProfile(_profile.copyWith(motion: v)),
          ),
        ),
      ],
    );
  }

  Widget _powerCard(BuildContext context) {
    return _sectionCard(
      context,
      icon: Icons.battery_charging_full,
      title: 'Power & battery',
      subtitle:
          'Sleep and click response — balance battery life and '
          'responsiveness.',
      children: [
        ExplainedSetting(
          title: 'Sleep time',
          icon: Icons.bedtime_outlined,
          explanation:
              'How long the mouse must sit still before it takes a quick '
              'power nap. Shorter saves battery.',
          detail:
              'When the mouse isn’t moved for this long, it enters a light '
              'sleep to save battery. It wakes almost instantly when you move '
              'it. If you want the best battery life, use a shorter time like '
              '2 minutes.',
          control: _valueSlider(
            min: 0.5,
            max: 30,
            divisions: 59,
            value: _profile.sleepMinutes,
            format: (v) => '${v.toStringAsFixed(1)} min',
            onChanged: (v) => _updateProfile(
              _profile.copyWith(sleepMinutes: X3Profile.clampSleep(v)),
            ),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Deep sleep',
          icon: Icons.nightlight_outlined,
          explanation:
              'A deeper power-saving state after the mouse has been idle '
              'even longer. Saves the most battery.',
          detail:
              'Deep sleep is a stronger power-saving mode the mouse enters '
              'after being idle for a while. It saves the most battery, but '
              'waking takes a moment longer than from the light sleep above.',
          control: _valueSlider(
            min: 1,
            max: 60,
            divisions: 59,
            value: _profile.deepMinutes.toDouble(),
            format: (v) => '${v.round()} min',
            onChanged: (v) => _updateProfile(
              _profile.copyWith(deepMinutes: X3Profile.clampDeep(v.round())),
            ),
          ),
        ),
        const Divider(height: 1),
        ExplainedSetting(
          title: 'Key response time',
          icon: Icons.touch_app_outlined,
          explanation:
              'How quickly a click is registered. A low value feels instant '
              'and snappy.',
          detail:
              'The time between pressing a button and the click registering '
              'on your computer. A low value (like 6 ms) feels instant. A '
              'higher value can help avoid accidental double clicks, at the '
              'cost of a tiny delay.',
          control: _valueSlider(
            min: 1,
            max: 50,
            divisions: 49,
            value: _profile.keyMs.toDouble(),
            format: (v) => '${v.round()} ms',
            onChanged: (v) => _updateProfile(
              _profile.copyWith(keyMs: X3Profile.clampKey(v.round())),
            ),
          ),
        ),
      ],
    );
  }

  Widget _valueSlider({
    required double min,
    required double max,
    required int divisions,
    required double value,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(
            format(value),
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple list dialog to pick one of the saved profiles.
class _ProfilePickerDialog extends StatelessWidget {
  const _ProfilePickerDialog({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load a profile'),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final name in names)
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(name),
                onTap: () => Navigator.pop(context, name),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

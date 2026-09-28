import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dsp/sound_controller.dart';
import 'carro_theme.dart';
import 'sound_files.dart';
import 'sound_strings.dart';

/// Profile manager: saved *.carro.json profiles, save-as, rename, share, import, reset.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) {
        showCarroSnack(context, soundText(context, 'error_generic').replaceAll('{error}', '$e'), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAs() async {
    final n = ref.read(soundProvider.notifier);
    final current = ref.read(soundProvider).profile.name;
    final name = await showCarroTextDialog(
      context,
      title: 'SAVE CURRENT AS',
      initial: current == 'Default' ? '' : current,
      label: soundText(context, 'profile_name'),
    );
    if (name == null) return;
    await _run(() => n.saveProfile(name));
  }

  Future<void> _load(String name) async {
    final n = ref.read(soundProvider.notifier);
    await _run(() async {
      await n.loadProfile(name);
      if (mounted) showCarroSnack(context, soundText(context, 'profile_loaded'));
    });
  }

  Future<void> _rename(String name) async {
    final n = ref.read(soundProvider.notifier);
    final newName = await showCarroTextDialog(
      context,
      title: 'RENAME',
      initial: name,
      label: soundText(context, 'profile_name'),
    );
    if (newName == null || newName == name) return;
    await _run(() async {
      final before = ref.read(soundProvider).profile;
      final wasCurrent = before.name == name;
      // Rename = load, save under the new name, delete the old file, then restore the
      // sound that was playing before (unless the renamed profile was the current one).
      await n.loadProfile(name);
      await n.saveProfile(newName);
      await n.deleteProfile(name);
      if (!wasCurrent) n.update((_) => before);
      n.clearMessage();
    });
  }

  Future<void> _delete(String name) async {
    final n = ref.read(soundProvider.notifier);
    final ok = await showCarroConfirm(
      context,
      title: 'DELETE',
      message: soundText(context, 'confirm_delete').replaceAll('{name}', name),
      confirm: 'DELETE',
    );
    if (!ok) return;
    await _run(() => n.deleteProfile(name));
  }

  Future<void> _share(String name, BuildContext itemContext) async {
    await _run(() async {
      final dir = await SoundController.profilesDir();
      final path = p.join(dir.path, '$name.carro.json');
      if (!File(path).existsSync()) return;
      if (!itemContext.mounted) return;
      await shareLocalFile(itemContext, path, subject: 'CarroTube sound profile "$name"');
    });
  }

  Future<void> _exportCurrent(BuildContext buttonContext) async {
    final n = ref.read(soundProvider.notifier);
    await _run(() async {
      final path = await n.exportProfile();
      if (!buttonContext.mounted) return;
      await shareLocalFile(buttonContext, path, subject: 'CarroTube sound profile');
    });
  }

  Future<void> _import() async {
    final n = ref.read(soundProvider.notifier);
    await _run(() async {
      final path = await pickLocalFile(const ['json']);
      if (path == null) return;
      final ok = await n.importProfile(path);
      if (!mounted) return;
      showCarroSnack(context, soundText(context, ok ? 'profile_import_ok' : 'profile_import_fail'), error: !ok);
    });
  }

  Future<void> _resetAll() async {
    final n = ref.read(soundProvider.notifier);
    final ok = await showCarroConfirm(
      context,
      title: 'FACTORY RESET',
      message: soundText(context, 'confirm_reset_all'),
      confirm: 'RESET',
    );
    if (ok) n.resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final c = watchIllumination(ref);
    final current = s.profile.name;

    return CarroScaffold(
      title: 'PROFILES',
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              children: [
                CarroPanel(
                  title: 'CURRENT',
                  glow: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(current.toUpperCase(), style: lcdStyle(c, size: 20, weight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '${s.profile.eqPreset} · ${s.profile.network ? 'NETWORK' : 'STANDARD'} · TA ${s.profile.taOn ? s.profile.taPreset : 'OFF'}',
                        style: carroCaption,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CarroButton(
                              label: 'SAVE AS…',
                              icon: Icons.save_outlined,
                              filled: true,
                              onPressed: _saveAs,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (bc) => CarroButton(
                                label: 'SHARE',
                                icon: Icons.ios_share,
                                onPressed: () => _exportCurrent(bc),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                CarroPanel(
                  title: 'SAVED PROFILES',
                  trailing: Text('${s.savedProfiles.length}', style: lcdStyle(c, size: 12)),
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                  child: s.savedProfiles.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(soundText(context, 'profile_empty'), style: carroBody),
                        )
                      : Column(
                          children: [
                            for (final name in s.savedProfiles)
                              Builder(
                                builder: (itemContext) => ListTile(
                                  dense: true,
                                  leading: Icon(
                                    name == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    color: name == current ? c : CarroColors.textDim,
                                  ),
                                  title: Text(
                                    name,
                                    style: name == current
                                        ? lcdStyle(c, size: 14)
                                        : const TextStyle(
                                            color: CarroColors.text,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.8,
                                          ),
                                  ),
                                  onTap: () => _load(name),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: CarroColors.textDim),
                                    onSelected: (v) {
                                      switch (v) {
                                        case 'load':
                                          _load(name);
                                        case 'rename':
                                          _rename(name);
                                        case 'share':
                                          _share(name, itemContext);
                                        case 'delete':
                                          _delete(name);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'load', child: Text('LOAD')),
                                      PopupMenuItem(value: 'rename', child: Text('RENAME')),
                                      PopupMenuItem(value: 'share', child: Text('EXPORT / SHARE')),
                                      PopupMenuItem(value: 'delete', child: Text('DELETE')),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: CarroButton(label: 'IMPORT', icon: Icons.file_open, onPressed: _import),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CarroButton(
                          label: 'FACTORY RESET',
                          icon: Icons.restart_alt,
                          color: CarroColors.danger,
                          onPressed: _resetAll,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

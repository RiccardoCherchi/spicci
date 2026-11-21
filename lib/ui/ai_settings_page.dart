import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/ai.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'pickers.dart';
import 'solar.dart';
import 'widgets.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  late final AiSettings _initial = ref.read(aiSettingsProvider);
  late String _presetId = _initial.presetId;
  late final _baseUrl = TextEditingController(text: _initial.baseUrl);
  late String _model = _initial.model;
  final _key = TextEditingController();
  List<String>? _models;
  var _busy = false;
  String? _message;

  AiPreset get _preset => aiPresets.firstWhere((p) => p.id == _presetId);

  @override
  void initState() {
    super.initState();
    ref.read(aiKeyProvider.future).then((k) {
      if (mounted && k != null) setState(() => _key.text = k);
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _key.dispose();
    super.dispose();
  }

  AiClient get _client => AiClient(baseUrl: _baseUrl.text.trim(), apiKey: _key.text.trim(), model: _model);

  Future<void> _loadModels() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final models = await _client.models();
      setState(() {
        _models = models;
        if (!models.contains(_model)) _model = '';
      });
    } on Object catch (e) {
      setState(() => _message = '$e');
    }
    setState(() => _busy = false);
  }

  Future<void> _save() async {
    ref
        .read(aiSettingsProvider.notifier)
        .set(AiSettings(presetId: _presetId, baseUrl: _baseUrl.text.trim(), model: _model));
    final storage = ref.read(secureStorageProvider);
    final key = _key.text.trim();
    key.isEmpty ? await storage.delete(key: aiKeyName) : await storage.write(key: aiKeyName, value: key);
    ref.invalidate(aiKeyProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SubPage(
      title: 'ai.title'.tr(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 40),
        children: [
          Text('ai.intro'.tr(), style: TextStyle(color: t.muted, height: 1.4)),
          SectionHeader('ai.provider'.tr()),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in aiPresets)
                Pill(
                  label: p.id == 'custom' ? 'ai.custom'.tr() : p.name,
                  color: p.id == _presetId ? t.accent.withValues(alpha: 0.18) : t.card,
                  trailing: p.id == 'groq'
                      ? Text('ai.recommended'.tr(), style: TextStyle(color: t.accentInk, fontSize: 11))
                      : null,
                  onTap: () => setState(() {
                    _presetId = p.id;
                    if (p.baseUrl.isNotEmpty) _baseUrl.text = p.baseUrl;
                    _models = null;
                    _model = '';
                  }),
                ),
            ],
          ),
          if (_preset.trains) ...[
            const SizedBox(height: 10),
            Row(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SolarIcon.ui(Ui.dangerTriangle, size: 18, color: Colors.orange),
                Expanded(
                  child: Text('ai.trains'.tr(), style: const TextStyle(color: Colors.orange, fontSize: 13)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Field(
            label: 'ai.base_url'.tr(),
            child: TextField(
              controller: _baseUrl,
              enabled: _presetId == 'custom',
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ),
          const SizedBox(height: 14),
          Field(
            label: 'ai.key'.tr(),
            child: TextField(
              controller: _key,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(hintText: 'ai.key_hint'.tr()),
            ),
          ),
          const SizedBox(height: 14),
          Field(
            label: 'ai.model'.tr(),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Pill(
                    label: _model.isEmpty ? 'ai.model_pick'.tr() : _model,
                    color: t.card2,
                    trailing: SolarIcon.ui(Ui.altArrowDown, size: 16, color: t.muted),
                    onTap: _models == null
                        ? null
                        : () async {
                            final o = await pickOption<String>(context, [
                              for (final m in _models!) Option(m, m),
                            ], selected: _model);
                            if (o != null) setState(() => _model = o.value);
                          },
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy || _key.text.trim().isEmpty ? null : _loadModels,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('ai.load_models'.tr()),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!, style: TextStyle(color: t.expense, fontSize: 12.5)),
            ),
          if (_models != null && _models!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('ai.no_models'.tr(), style: TextStyle(color: t.muted, fontSize: 12.5)),
            ),
          const SizedBox(height: 20),
          Text('ai.privacy'.tr(), style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text('preset.save'.tr())),
          if (ref.watch(aiKeyProvider).value?.isNotEmpty ?? false)
            TextButton(
              onPressed: () async {
                await ref.read(secureStorageProvider).delete(key: aiKeyName);
                ref.invalidate(aiKeyProvider);
                setState(() => _key.clear());
              },
              child: Text('ai.remove_key'.tr(), style: TextStyle(color: t.expense)),
            ),
        ],
      ),
    );
  }
}

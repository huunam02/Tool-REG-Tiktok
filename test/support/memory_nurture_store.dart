import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/nurture_store.dart';
import 'package:test_tiktok/core/proxy_store.dart';

class MemoryNurtureRepository implements NurtureRepository {
  MemoryNurtureRepository(this.configurations);
  final Future<List<SavedProxy>> Function() configurations;
  final settings = <String, String>{};
  final sessions =
      <String, ({String email, int? configurationId, NurturePlan plan})>{};
  final totals = <String, NurtureTotals>{};
  final phases = <String, String>{};
  final revisions = <String, int>{};

  @override
  Future<List<NurtureAccount>> listAccounts() async {
    final configs = await configurations();
    final emails = {
      for (final entry in configs)
        if (entry.account != null)
          nurtureAccountKey(entry.account!.email): entry.account!.email,
      for (final session in sessions.values)
        nurtureAccountKey(session.email): session.email,
    };
    return [for (final email in emails.values) _account(email, configs)];
  }

  NurtureAccount _account(String email, List<SavedProxy> configs) {
    final key = nurtureAccountKey(email);
    final matches = configs.where(
      (entry) => nurtureAccountKey(entry.account?.email ?? '') == key,
    );
    final ids = sessions.keys
        .where((id) => nurtureAccountKey(sessions[id]!.email) == key)
        .toList();
    final last = ids.isEmpty ? null : ids.last;
    return NurtureAccount(
      key: key,
      email: email,
      configurationId: matches.firstOrNull?.id,
      configurationName: matches.firstOrNull?.name ?? '',
      totals: ids.fold(
        const NurtureTotals(),
        (sum, id) => sum + (totals[id] ?? const NurtureTotals()),
      ),
      phase: last == null ? 'idle' : phases[last] ?? 'idle',
      mode: last == null ? NurtureMode.feed : sessions[last]!.plan.mode,
      keyword: last == null ? '' : sessions[last]!.plan.keyword,
    );
  }

  @override
  Future<Map<String, String>> preferences() async => Map.of(settings);
  @override
  Future<void> savePreferences(Map<String, String> values) async =>
      settings.addAll(values);
  @override
  Future<void> beginSession({
    required String id,
    required String email,
    int? configurationId,
    required NurturePlan plan,
    required String phase,
    DateTime? scheduledAt,
  }) async {
    sessions[id] = (email: email, configurationId: configurationId, plan: plan);
    phases[id] = phase;
  }

  @override
  Future<void> saveProgress(
    String id,
    int revision,
    NurtureTotals value,
  ) async {
    if (revision <= (revisions[id] ?? 0)) return;
    revisions[id] = revision;
    totals[id] = value;
  }

  @override
  Future<void> setPhase(String id, String phase) async => phases[id] = phase;
  @override
  Future<void> markRegistered(String email) async {}
}

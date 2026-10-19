import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/screens/contentdetailedscreen.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/api/malapi.dart';
import 'package:dailyanimelist/api/maluser.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/user/hompagepref.dart';
import 'package:dailyanimelist/util/responsive_helper.dart';
import 'package:dailyanimelist/widgets/loading/loadingcard.dart';
import 'package:dailyanimelist/widgets/shimmecolor.dart';
import 'package:dailyanimelist/widgets/user/contentlistwidget.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Isolated Ameo/Sprout client and UI; legacy DailyAL recommendation code is untouched.
class AmeoRecommendationSection extends StatefulWidget {
  final String? title;

  const AmeoRecommendationSection({Key? key, this.title}) : super(key: key);

  @override
  State<AmeoRecommendationSection> createState() => _AmeoRecommendationSectionState();
}

class _AmeoRecommendationSectionState extends State<AmeoRecommendationSection> {
  List<_AmeoAnime> items = const [];
  String username = '';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    MalUser.listStatusRevision.addListener(_onListStatusChanged);
    load();
  }

  void _onListStatusChanged() {
    if (mounted) load();
  }

  @override
  void dispose() {
    MalUser.listStatusRevision.removeListener(_onListStatusChanged);
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    username = await _resolveAmeoUsername(prefs);
    if (username.isEmpty) {
      if (mounted) setState(() { loading = false; });
      return;
    }
    if (mounted) setState(() { loading = items.isEmpty; error = null; });
    try {
      final result = await _AmeoClient().recommend(username, _AmeoSettings.fromPrefs(prefs), force: force);
      if (mounted) setState(() { items = result; loading = false; error = result.isEmpty ? 'Ameo tidak mengembalikan rekomendasi.' : null; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Rekomendasi gagal dimuat.'; });
    }
  }

  Future<void> openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AmeoRecommendationPage()));
    load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = tileMap.tryAt(user.pref.homePageTileSize)!;
    final cardHeight = tile.containerHeight;
    final cardWidth = cardHeight * (2 / 3);
    final horizontalPadding =
        ResponsiveHelper.isTabletOrLarger(context) ? 0.0 : 15.0;
    final animeNodes = items
        .take(12)
        .map((item) => item.dailyAlNode)
        .whereType<BaseNode>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 15),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title ?? 'Rekomendasi Ameo',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Semua rekomendasi dan pengaturan',
                onPressed: openSettings,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        if (username.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: OutlinedButton.icon(
              onPressed: openSettings,
              icon: const Icon(Icons.tune),
              label: const Text('Atur username MyAnimeList'),
            ),
          )
        else if (loading)
          ShimmerColor(
            Container(
              height: cardHeight,
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: 10,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) =>
                    LoadingCard(height: cardHeight, width: cardWidth),
              ),
            ),
          )
        else if (animeNodes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                Expanded(child: Text(error ?? 'Belum ada rekomendasi.')),
                IconButton(
                  onPressed: () => load(force: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          )
        else
          horizontalList(
            category: 'anime',
            items: animeNodes,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Text(
            'Ditenagai Sprout oleh Ameobea',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}


class AmeoRecommendationPage extends StatefulWidget {
  const AmeoRecommendationPage({Key? key}) : super(key: key);
  @override
  State<AmeoRecommendationPage> createState() => _AmeoRecommendationPageState();
}
class _AmeoRecommendationPageState extends State<AmeoRecommendationPage> {
  final usernameController = TextEditingController();
  _AmeoSettings settings = const _AmeoSettings();
  List<_AmeoAnime> items = const [];
  bool loading = false;
  String? error;
  String? technicalLog;
  @override
  void initState() {
    super.initState();
    MalUser.listStatusRevision.addListener(_onListStatusChanged);
    initialize();
  }

  void _onListStatusChanged() {
    if (mounted && usernameController.text.trim().isNotEmpty) {
      refresh(force: false);
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedUsername = await _resolveAmeoUsername(prefs);
    if (!mounted) return;
    usernameController.text = resolvedUsername;
    settings = _AmeoSettings.fromPrefs(prefs);
    setState(() {});
    if (resolvedUsername.trim().isNotEmpty) refresh(force: false);
  }
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ameo_username', usernameController.text.trim());
    await settings.save(prefs);
  }
  Future<void> refresh({bool force = true}) async {
    final name = usernameController.text.trim();
    if (name.isEmpty) {
      setState(() { loading = false; error = 'Username MyAnimeList tidak ditemukan. Atur melalui Pengaturan Ameo.'; technicalLog = 'phase=validation\nreason=empty_username\nprofile_auto_detected=${user.status == AuthStatus.AUTHENTICATED}'; items = const []; });
      return;
    }
    await save();
    if (!mounted) return;
    setState(() { loading = true; error = null; technicalLog = null; });
    try {
      final result = await _AmeoClient().recommend(name, settings, force: force);
      if (!mounted) return;
      setState(() {
        items = result; loading = false;
        if (result.isEmpty) { error = 'Ameo tidak mengembalikan rekomendasi yang dapat ditampilkan.'; technicalLog = 'phase=decode\nrecommendation_count=0'; }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = 'Permintaan Ameo gagal. Buka detail teknis untuk melihat penyebabnya.'; technicalLog = e is _AmeoRequestException ? e.diagnostics : 'phase=ui\nexception_type=${e.runtimeType}\nmessage=${_safeError(e.toString())}'; });
    }
  }
  Future<void> _openSettings() async {
    var draftUsername = usernameController.text;
    var draftSettings = settings;
    final applied = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            (() {
              final media = MediaQuery.of(context);
              final keyboardInset = media.viewInsets.bottom;
              final navigationInset = media.viewPadding.bottom;
              return (keyboardInset > navigationInset ? keyboardInset : navigationInset) + 20;
            })(),
          ),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pengaturan Ameo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextFormField(key: ValueKey(draftUsername), initialValue: draftUsername, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username MyAnimeList', helperText: 'Otomatis dari profil login jika tersedia; tetap bisa diubah.', border: OutlineInputBorder()),
              onChanged: (value) => draftUsername = value),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: draftSettings.model,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Model rekomendasi',
                helperText: 'Model dilatih dengan pendekatan berbeda dan dapat menghasilkan rekomendasi berbeda.',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '2026-logq', child: Text('Aug. 2026 · LogQ (default)')),
                DropdownMenuItem(value: '2026-rc', child: Text('Aug. 2026 · Release candidate')),
                DropdownMenuItem(value: '2025-jax', child: Text('2025 · JAX')),
                DropdownMenuItem(value: 'legacy', child: Text('Legacy · 2023')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setSheetState(() => draftSettings = draftSettings.copyWith(model: value));
                }
              },
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Season tambahan'), value: draftSettings.includeExtraSeasons, onChanged: (v) => setSheetState(() => draftSettings = draftSettings.copyWith(includeExtraSeasons: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Film'), value: draftSettings.includeMovies, onChanged: (v) => setSheetState(() => draftSettings = draftSettings.copyWith(includeMovies: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('ONA / OVA / Specials'), value: draftSettings.includeONAsOVAspecials, onChanged: (v) => setSheetState(() => draftSettings = draftSettings.copyWith(includeONAsOVAspecials: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Anime musik'), value: draftSettings.includeMusic, onChanged: (v) => setSheetState(() => draftSettings = draftSettings.copyWith(includeMusic: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Filter Plan to Watch'), value: draftSettings.filterPlanToWatch, onChanged: (v) => setSheetState(() => draftSettings = draftSettings.copyWith(filterPlanToWatch: v))),
            if (draftSettings.model == 'legacy')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Model Legacy tidak menggunakan Logit weight atau Niche boost.'),
              ),
            Text('Logit weight: ${draftSettings.logitWeight.toStringAsFixed(2)}'),
            Slider(value: draftSettings.logitWeight, min: 0, max: 1, divisions: 100, onChanged: draftSettings.model == 'legacy' ? null : (v) => setSheetState(() => draftSettings = draftSettings.copyWith(logitWeight: v))),
            Text('Niche boost factor: ${draftSettings.nicheBoostFactor.toStringAsFixed(2)}'),
            Slider(value: draftSettings.nicheBoostFactor, min: 0, max: 1, divisions: 100, onChanged: draftSettings.model == 'legacy' ? null : (v) => setSheetState(() => draftSettings = draftSettings.copyWith(nicheBoostFactor: v))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { usernameController.text = draftUsername.trim(); settings = draftSettings; Navigator.of(sheetContext).pop(true); }, icon: const Icon(Icons.check), label: const Text('Terapkan pengaturan'))),
          ])),
        ),
      ),
    );
    if (applied == true && mounted) { await save(); await refresh(); }
  }
  Future<void> _copyTechnicalLog() async {
    if (technicalLog == null) return;
    await Clipboard.setData(ClipboardData(text: technicalLog!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log teknis disalin')));
  }
  @override
  void dispose() {
    MalUser.listStatusRevision.removeListener(_onListStatusChanged);
    usernameController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rekomendasi Ameo'), actions: [
      IconButton(tooltip: 'Pengaturan Ameo', onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
      IconButton(tooltip: 'Muat ulang', onPressed: loading ? null : () => refresh(), icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Buka Ameo di browser', onPressed: () => launchUrl(Uri.parse('https://anime.ameo.dev/'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new)),
    ]),
    body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (technicalLog != null) ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Detail teknis'), children: [
            SelectableText(technicalLog!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _copyTechnicalLog, icon: const Icon(Icons.copy), label: const Text('Salin log'))),
          ]),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: loading ? null : () => refresh(), icon: const Icon(Icons.refresh), label: const Text('Coba lagi'))),
        ])))),
      if (!loading && items.isEmpty && error == null) const Padding(padding: EdgeInsets.all(20), child: Text('Tambahkan username MyAnimeList melalui Pengaturan Ameo untuk memuat rekomendasi.')),
      for (var i = 0; i < items.length; i++) _AmeoRecommendationEntry(key: ValueKey(items[i].id), anime: items[i], index: i),
      const SizedBox(height: 20),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Ditenagai Sprout oleh Ameobea. Layanan eksternal dan format respons dapat berubah.')),
    ]),
  );
}


class _AmeoContributor {
  final int id; final String title; final double? userRating; final double? ratingDelta;
  const _AmeoContributor({required this.id, required this.title, this.userRating, this.ratingDelta});
}
class _AmeoRecommendationEntry extends StatefulWidget {
  final _AmeoAnime anime; final int index;
  const _AmeoRecommendationEntry({Key? key, required this.anime, required this.index}) : super(key: key);
  @override State<_AmeoRecommendationEntry> createState() => _AmeoRecommendationEntryState();
}
class _AmeoRecommendationEntryState extends State<_AmeoRecommendationEntry> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (anime.dailyAlNode != null)
        ContentAllWidget(
          dynContent: anime.dailyAlNode,
          myListStatus: listStatus(anime.dailyAlNode, 'anime'),
          index: widget.index,
          category: 'anime',
          aspectRatio: 2.35,
          imageAspectRatio: .6,
          showImage: true,
          showEdit: true,
          showStatus: true,
          updateCacheOnEdit: true,
          onContentUpdate: () {},
          showBackgroundImage: false,
        )
      else
        ListTile(
          leading: SizedBox(width: 60, child: anime.image.isEmpty ? const Icon(Icons.movie_outlined) : CachedNetworkImage(imageUrl: anime.image, fit: BoxFit.cover)),
          title: Text(anime.title),
          subtitle: anime.score == null ? null : Text('Prediksi Ameo: ${anime.score!.toStringAsFixed(3)}'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContentDetailedScreen(id: anime.id))),
        ),
      if (anime.score != null || anime.contributors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 12, top: 2, bottom: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 0,
            children: [
              if (anime.score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, size: 14, color: Theme.of(context).colorScheme.onSecondaryContainer),
                    const SizedBox(width: 5),
                    Text('Prediksi Ameo ${anime.score!.toStringAsFixed(3)}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSecondaryContainer)),
                  ]),
                ),
              if (anime.contributors.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(expanded ? 'Sembunyikan alasan' : 'Mengapa direkomendasikan?'),
                ),
            ],
          ),
        ),
      if (expanded && anime.contributors.isNotEmpty)
        Padding(padding: const EdgeInsets.only(left: 16, right: 12, bottom: 6), child: Column(children: [
        Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.4), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recommended because you watched:', style: Theme.of(context).textTheme.titleSmall),
          for (final source in anime.contributors) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.movie_filter_outlined), title: Text(source.title), subtitle: source.ratingDelta != null ? Text('Kontribusi: ${source.ratingDelta!.toStringAsFixed(3)}') : (source.userRating == null ? null : Text('Rating Anda: ${source.userRating}')), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContentDetailedScreen(id: source.id)))),
        ])),
      ])),
      const Divider(height: 1),
    ]);
  }
}
class _AmeoAnime {
  final int id; final String title; final String image; final double? score;
  final BaseNode? dailyAlNode; final List<_AmeoContributor> contributors;
  const _AmeoAnime({required this.id, required this.title, required this.image, this.score, this.dailyAlNode, this.contributors = const []});
  factory _AmeoAnime.fromJson(int id, Map<String, dynamic> json, dynamic rec, {Map<int, Map<String, dynamic>>? allMetadata, List<dynamic> rawContributors = const []}) {
    final picture = json['main_picture'];
    final image = picture is Map ? (picture['large'] ?? picture['medium'] ?? '').toString() : '';
    final title = (json['title'] ?? json['title_english'] ?? 'Anime #$id').toString();
    // Sprout's `score` is a ranking score, not the predicted rating shown in the UI.
    // Prefer the explicit prediction fields and keep ranking score separate.
    final rawScore = rec is Map
        ? (rec['predictedRating'] ??
            rec['predicted_rating'] ??
            rec['predictedScore'] ??
            rec['predicted_score'])
        : null;
    final BaseNode node = BaseNode.fromJson(
      <String, dynamic>{'node': <String, dynamic>{...json, 'id': id}},
      category: 'anime',
    );
    final contributors = <_AmeoContributor>[];
    for (final raw in rawContributors) {
      if (raw is! Map) continue;
      final rawId = raw['animeId'] ?? raw['anime_id'] ?? raw['id'] ?? raw['malId'];
      final contributorId = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
      if (contributorId == null || contributorId == id) continue;
      final meta = allMetadata?[contributorId];
      final contributorTitle = (raw['title'] ?? raw['animeTitle'] ?? raw['name'] ?? meta?['title'] ?? 'Anime #$contributorId').toString();
      final rating = raw['userRating'] ?? raw['user_rating'];
      final delta = raw['ratingDelta'] ?? raw['rating_delta'];
      contributors.add(_AmeoContributor(id: contributorId, title: contributorTitle, userRating: rating is num ? rating.toDouble() : double.tryParse(rating?.toString() ?? ''), ratingDelta: delta is num ? delta.toDouble() : double.tryParse(delta?.toString() ?? '')));
    }
    // A missing prediction must remain missing; MAL's mean score is a different metric.
    final predictedScore = rawScore is num
        ? rawScore.toDouble()
        : double.tryParse(rawScore?.toString() ?? '');
    return _AmeoAnime(id: id, title: title, image: image, score: predictedScore, dailyAlNode: node, contributors: contributors);
  }
}
class _AmeoSettings {
  final String model;
  final bool includeExtraSeasons, includeONAsOVAspecials, includeMovies, includeMusic, filterPlanToWatch;
  final double logitWeight, nicheBoostFactor;
  const _AmeoSettings({this.model = '2026-logq', this.includeExtraSeasons = false, this.includeONAsOVAspecials = true, this.includeMovies = true, this.includeMusic = false, this.filterPlanToWatch = true, this.logitWeight = 0.6, this.nicheBoostFactor = 0.35});
  _AmeoSettings copyWith({String? model, bool? includeExtraSeasons, bool? includeONAsOVAspecials, bool? includeMovies, bool? includeMusic, bool? filterPlanToWatch, double? logitWeight, double? nicheBoostFactor}) => _AmeoSettings(model: model ?? this.model, includeExtraSeasons: includeExtraSeasons ?? this.includeExtraSeasons, includeONAsOVAspecials: includeONAsOVAspecials ?? this.includeONAsOVAspecials, includeMovies: includeMovies ?? this.includeMovies, includeMusic: includeMusic ?? this.includeMusic, filterPlanToWatch: filterPlanToWatch ?? this.filterPlanToWatch, logitWeight: logitWeight ?? this.logitWeight, nicheBoostFactor: nicheBoostFactor ?? this.nicheBoostFactor);
  factory _AmeoSettings.fromPrefs(SharedPreferences p) => _AmeoSettings(model: p.getString('ameo_model') ?? '2026-logq', includeExtraSeasons: p.getBool('ameo_extra_seasons') ?? false, includeONAsOVAspecials: p.getBool('ameo_ovas') ?? true, includeMovies: p.getBool('ameo_movies') ?? true, includeMusic: p.getBool('ameo_music') ?? false, filterPlanToWatch: p.getBool('ameo_filter_ptw') ?? true, logitWeight: p.getDouble('ameo_logit_weight') ?? 0.6, nicheBoostFactor: p.getDouble('ameo_niche_boost') ?? 0.35);
  Future<void> save(SharedPreferences p) async {
    await p.setString('ameo_model', model); await p.setBool('ameo_extra_seasons', includeExtraSeasons); await p.setBool('ameo_ovas', includeONAsOVAspecials); await p.setBool('ameo_movies', includeMovies); await p.setBool('ameo_music', includeMusic); await p.setBool('ameo_filter_ptw', filterPlanToWatch); await p.setDouble('ameo_logit_weight', logitWeight); await p.setDouble('ameo_niche_boost', nicheBoostFactor);
  }
  Map<String, dynamic> toJson() => {'model': model, 'includeExtraSeasons': includeExtraSeasons, 'includeONAsOVAsSpecials': includeONAsOVAspecials, 'includeMovies': includeMovies, 'includeMusic': includeMusic, 'filterPlanToWatch': filterPlanToWatch, 'logitWeight': logitWeight, 'nicheBoostFactor': nicheBoostFactor, 'popularityAttenuationFactor': 0.0008, 'excludedIds': <int>[], 'excludedGenreIds': <int>[]};
}
class _AmeoClient {
  static const endpoint = 'https://anime.ameo.dev/recommendation/recommendation';
  static const ttl = Duration(hours: 6);
  Future<List<_AmeoAnime>> recommend(String username, _AmeoSettings settings, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'ameo_cache_' + base64Url.encode(utf8.encode(username + '|' + jsonEncode(settings.toJson())));
    final cached = prefs.getString(cacheKey); final cachedAt = prefs.getInt(cacheKey + '_at') ?? 0;
    if (!force && cached != null && DateTime.now().millisecondsSinceEpoch - cachedAt < ttl.inMilliseconds) {
      try {
        final cachedJson = jsonDecode(cached);
        if (cachedJson is Map<String, dynamic>) {
          final cachedItems = decode(cachedJson);
          await _mergeCachedListStatuses(cachedItems);
          return cachedItems;
        }
      } catch (_) {
        // Ignore corrupted cache and fall through to a fresh network request.
      }
      await prefs.remove(cacheKey);
      await prefs.remove(cacheKey + '_at');
    }
    final watch = Stopwatch()..start(); var phase = 'request'; var statusCode = 0; var contentType = ''; var responseBody = '';
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: const {
          'content-type': 'application/json; charset=UTF-8',
          'origin': 'https://anime.ameo.dev',
          'user-agent': 'DailyAL-Modif (Ameo integration)',
        },
        body: jsonEncode({
          'dataSource': {'type': 'username', 'username': username},
          'availableAnimeMetadataIDs': <int>[],
          'excludedRankingAnimeIDs': <int>[],
          'excludedGenreIDs': <int>[],
          'modelName': settings.model,
          'includeContributors': true,
          'includeExtraSeasons': settings.includeExtraSeasons,
          'includeONAsOVAsSpecials': settings.includeONAsOVAspecials,
          'includeMovies': settings.includeMovies,
          'includeMusic': settings.includeMusic,
          'profileSource': 'mal',
          'filterPlanToWatch': settings.filterPlanToWatch,
          'logitWeight': settings.logitWeight,
          'nicheBoostFactor': settings.nicheBoostFactor,
          'popularityAttenuationFactor': 0.0008,
        }),
      ).timeout(const Duration(seconds: 30));
      statusCode = response.statusCode; contentType = response.headers['content-type'] ?? ''; responseBody = response.body;
      if (statusCode < 200 || statusCode >= 300) throw HttpException('Ameo HTTP $statusCode');
      phase = 'json_decode'; final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid Ameo response root');
      phase = 'recommendation_decode'; final result = decode(decoded);
      await _mergeCachedListStatuses(result);
      await prefs.setString(cacheKey, jsonEncode(decoded)); await prefs.setInt(cacheKey + '_at', DateTime.now().millisecondsSinceEpoch);
      return result;
    } catch (e) {
      if (cached != null) {
        try {
          final staleJson = jsonDecode(cached);
          if (staleJson is Map<String, dynamic>) {
            final stale = decode(staleJson);
            if (stale.isNotEmpty) {
              await _mergeCachedListStatuses(stale);
              return stale;
            }
          }
        } catch (_) {
          // Invalid stale cache must not mask the original request failure.
        }
      }
      final diagnostics = [
        'endpoint=$endpoint',
        'method=POST',
        'phase=$phase',
        'http_status=${statusCode == 0 ? 'unavailable' : statusCode}',
        'elapsed_ms=${watch.elapsedMilliseconds}',
        'content_type=${contentType.isEmpty ? 'unavailable' : contentType}',
        'cache_available=${cached != null}',
        'exception_type=${e.runtimeType}',
        'message=${_safeError(e.toString())}',
        if (responseBody.isNotEmpty)
          'response_body=${_safeError(responseBody)}',
      ].join('\n');
      throw _AmeoRequestException(diagnostics);
    }
  }
  Future<void> _mergeCachedListStatuses(List<_AmeoAnime> items) async {
    final nodes = items.map((item) => item.dailyAlNode).whereType<BaseNode>().toList();
    // Ameo recommendations are independent of the MAL list cache. Fetch a full
    // list snapshot once when recommended IDs have no cached status.
    await MalApi.mergeCachedMyListStatus(nodes, 'anime', fetchIfMissing: true);
  }

  List<_AmeoAnime> decode(Map<String, dynamic> body) {
    final rawMetadata = body['animeData']; final rawRecommendations = body['recommendations'];
    if (rawMetadata is! Map || rawRecommendations is! List) throw const FormatException('Expected animeData object and recommendations array');
    final metadata = <int, Map<String, dynamic>>{};
    rawMetadata.forEach((key, value) { final id = int.tryParse(key.toString()); if (id != null && value is Map) metadata[id] = Map<String, dynamic>.from(value); });
    final result = <_AmeoAnime>[];
    for (final rec in rawRecommendations) {
      final rawId = rec is Map ? (rec['animeId'] ?? rec['id'] ?? rec['malId']) : rec;
      final id = rawId is num ? rawId.toInt() : int.tryParse(rawId.toString());
      if (id == null || metadata[id] == null) continue;
      result.add(_AmeoAnime.fromJson(id, metadata[id]!, rec, allMetadata: metadata, rawContributors: _contributorsFor(body, rec, id)));
    }
    return result;
  }
  List<dynamic> _contributorsFor(Map<String, dynamic> body, dynamic rec, int id) {
    if (rec is Map) for (final key in ['topContributors', 'contributors', 'becauseYouWatched', 'because_you_watched', 'contributorAnimeIds']) { final value = rec[key]; if (value is List) return value; }
    final root = body['topContributors'] ?? body['contributors'];
    if (root is Map) { final value = root[id.toString()] ?? root[id]; if (value is List) return value; if (value is Map) { final nested = value['topContributors'] ?? value['contributors'] ?? value['anime']; if (nested is List) return nested; } }
    if (root is List) for (final item in root) { if (item is! Map) continue; final target = item['recommendedAnimeId'] ?? item['recommendationId'] ?? item['targetAnimeId'] ?? item['recommended_anime_id']; if (target == id || target?.toString() == id.toString()) { final nested = item['topContributors'] ?? item['contributors'] ?? item['anime']; if (nested is List) return nested; } }
    return const [];
  }
}

class _AmeoRequestException implements Exception {
  final String diagnostics;
  const _AmeoRequestException(this.diagnostics);
}
Future<String> _resolveAmeoUsername(SharedPreferences prefs) async {
  final saved = (prefs.getString('ameo_username') ?? '').trim();
  if (saved.isNotEmpty) return saved;
  if (user.status != AuthStatus.AUTHENTICATED) return '';
  try {
    final profile = await MalUser.getUserInfo(fields: const ['name']);
    return profile.name?.trim() ?? '';
  } catch (_) {
    // Keep the feature usable when the MAL profile cannot be resolved.
    return '';
  }
}
// Keep server response line breaks intact for full, copyable diagnostics while redacting credentials.
String _safeError(String value) => value.replaceAll(
      RegExp(
        r'(access_token|refresh_token|authorization)\s*[:=]\s*("[^"]*"|[^,;\r\n]+)',
        caseSensitive: false,
      ),
      r'$1=[redacted]',
    );

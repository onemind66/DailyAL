import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/screens/contentdetailedscreen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Isolated Ameo/Sprout client and UI; legacy DailyAL recommendation code is untouched.
class AmeoRecommendationSection extends StatefulWidget {
  const AmeoRecommendationSection({Key? key}) : super(key: key);

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
    load();
  }

  Future<void> load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    username = (prefs.getString('ameo_username') ?? '').trim();
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
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(children: [
            Expanded(child: Text('Rekomendasi Ameo', style: theme.textTheme.titleLarge)),
            IconButton(tooltip: 'Semua rekomendasi dan pengaturan', onPressed: openSettings, icon: const Icon(Icons.arrow_forward)),
          ]),
        ),
        if (username.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: OutlinedButton.icon(onPressed: openSettings, icon: const Icon(Icons.tune), label: const Text('Atur username MyAnimeList')),
          )
        else if (loading)
          const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(children: [
              Expanded(child: Text(error ?? 'Belum ada rekomendasi.')),
              IconButton(onPressed: () => load(force: true), icon: const Icon(Icons.refresh)),
            ]),
          )
        else
          SizedBox(
            height: 225,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: items.length > 12 ? 12 : items.length,
              itemBuilder: (context, index) => _AmeoAnimeCard(
                anime: items[index],
                width: 116,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContentDetailedScreen(id: items[index].id))),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Text('Ditenagai Sprout oleh Ameobea', style: theme.textTheme.bodySmall),
        ),
      ]),
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
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    usernameController.text = prefs.getString('ameo_username') ?? '';
    settings = _AmeoSettings.fromPrefs(prefs);
    if (mounted) setState(() {});
    if (usernameController.text.trim().isNotEmpty) refresh();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ameo_username', usernameController.text.trim());
    await settings.save(prefs);
  }

  Future<void> refresh({bool force = true}) async {
    final name = usernameController.text.trim();
    if (name.isEmpty) {
      setState(() { error = 'Masukkan username MyAnimeList yang memiliki profil publik.'; items = const []; });
      return;
    }
    await save();
    setState(() { loading = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await _AmeoClient().recommend(name, settings, force: force);
      if (mounted) setState(() { items = result; loading = false; if (result.isEmpty) error = 'Tidak ada rekomendasi yang dapat ditampilkan.'; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Permintaan Ameo gagal. Periksa username dan koneksi, lalu coba lagi.'; });
    }
  }

  void change(_AmeoSettings value) {
    setState(() { settings = value; });
    save().then((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 600), () => refresh());
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    usernameController.dispose();
    super.dispose();
  }

  Widget option(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(title), value: value, onChanged: onChanged);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rekomendasi Ameo'), actions: [
      IconButton(tooltip: 'Muat ulang', onPressed: loading ? null : () => refresh(), icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Buka Ameo di browser', onPressed: () => launchUrl(Uri.parse('https://anime.ameo.dev/'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new)),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: usernameController,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Username MyAnimeList',
          helperText: 'Profil harus publik. Username disimpan lokal di perangkat.',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => refresh(),
      ),
      const SizedBox(height: 8),
      option('Season tambahan', settings.includeExtraSeasons, (v) => change(settings.copyWith(includeExtraSeasons: v))),
      option('Film', settings.includeMovies, (v) => change(settings.copyWith(includeMovies: v))),
      option('ONA / OVA / Specials', settings.includeONAsOVAsSpecials, (v) => change(settings.copyWith(includeONAsOVAsSpecials: v))),
      option('Anime musik', settings.includeMusic, (v) => change(settings.copyWith(includeMusic: v))),
      option('Filter Plan to Watch', settings.filterPlanToWatch, (v) => change(settings.copyWith(filterPlanToWatch: v))),
      Text('Logit weight: ' + settings.logitWeight.toStringAsFixed(2)),
      Slider(value: settings.logitWeight, min: 0, max: 1, divisions: 100, onChanged: (v) => setState(() { settings = settings.copyWith(logitWeight: v); }), onChangeEnd: (_) => change(settings)),
      Text('Niche boost factor: ' + settings.nicheBoostFactor.toStringAsFixed(2)),
      Slider(value: settings.nicheBoostFactor, min: 0, max: 1, divisions: 100, onChanged: (v) => setState(() { settings = settings.copyWith(nicheBoostFactor: v); }), onChangeEnd: (_) => change(settings)),
      FilledButton.icon(onPressed: loading ? null : () => refresh(), icon: const Icon(Icons.auto_awesome), label: Text(loading ? 'Memuat…' : 'Terapkan dan muat rekomendasi')),
      if (loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (items.isNotEmpty)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisExtent: 255, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemBuilder: (context, index) => _AmeoAnimeCard(
            anime: items[index],
            width: double.infinity,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContentDetailedScreen(id: items[index].id))),
          ),
        ),
      const SizedBox(height: 20),
      const Text('Ditenagai Sprout oleh Ameobea. Layanan eksternal dan format respons dapat berubah.'),
    ]),
  );
}

class _AmeoAnimeCard extends StatelessWidget {
  final _AmeoAnime anime;
  final double width;
  final VoidCallback onTap;
  const _AmeoAnimeCard({required this.anime, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: InkWell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: anime.image.isEmpty
            ? Container(width: width, color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.movie_outlined))
            : CachedNetworkImage(
                imageUrl: anime.image, width: width, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
              ),
        )),
        const SizedBox(height: 6),
        Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (anime.score != null) Text('Skor MAL: ' + anime.score!.toStringAsFixed(2), style: Theme.of(context).textTheme.bodySmall),
      ]),
    ),
  );
}

class _AmeoAnime {
  final int id;
  final String title;
  final String image;
  final double? score;
  const _AmeoAnime({required this.id, required this.title, required this.image, this.score});

  factory _AmeoAnime.fromJson(int id, Map<String, dynamic> json, dynamic rec) {
    final picture = json['main_picture'];
    final image = picture is Map ? (picture['large'] ?? picture['medium'] ?? '').toString() : '';
    final title = (json['title'] ?? json['title_english'] ?? 'Anime #' + id.toString()).toString();
    final rawScore = rec is Map ? (rec['score'] ?? rec['predictedScore'] ?? rec['predicted_score']) : null;
    final mean = json['mean'];
    return _AmeoAnime(id: id, title: title, image: image, score: rawScore is num ? rawScore.toDouble() : (mean is num ? mean.toDouble() : null));
  }
}

class _AmeoSettings {
  final String model;
  final bool includeExtraSeasons, includeONAsOVAsSpecials, includeMovies, includeMusic, filterPlanToWatch;
  final double logitWeight, nicheBoostFactor;
  const _AmeoSettings({
    this.model = '2026-logq',
    this.includeExtraSeasons = false,
    this.includeONAsOVAsSpecials = true,
    this.includeMovies = true,
    this.includeMusic = false,
    this.filterPlanToWatch = true,
    this.logitWeight = 0.6,
    this.nicheBoostFactor = 0.35,
  });

  _AmeoSettings copyWith({String? model, bool? includeExtraSeasons, bool? includeONAsOVAsSpecials, bool? includeMovies, bool? includeMusic, bool? filterPlanToWatch, double? logitWeight, double? nicheBoostFactor}) => _AmeoSettings(
    model: model ?? this.model,
    includeExtraSeasons: includeExtraSeasons ?? this.includeExtraSeasons,
    includeONAsOVAsSpecials: includeONAsOVAsSpecials ?? this.includeONAsOVAsSpecials,
    includeMovies: includeMovies ?? this.includeMovies,
    includeMusic: includeMusic ?? this.includeMusic,
    filterPlanToWatch: filterPlanToWatch ?? this.filterPlanToWatch,
    logitWeight: logitWeight ?? this.logitWeight,
    nicheBoostFactor: nicheBoostFactor ?? this.nicheBoostFactor,
  );

  factory _AmeoSettings.fromPrefs(SharedPreferences p) => _AmeoSettings(
    model: p.getString('ameo_model') ?? '2026-logq',
    includeExtraSeasons: p.getBool('ameo_extra_seasons') ?? false,
    includeONAsOVAsSpecials: p.getBool('ameo_ovas') ?? true,
    includeMovies: p.getBool('ameo_movies') ?? true,
    includeMusic: p.getBool('ameo_music') ?? false,
    filterPlanToWatch: p.getBool('ameo_filter_ptw') ?? true,
    logitWeight: p.getDouble('ameo_logit_weight') ?? 0.6,
    nicheBoostFactor: p.getDouble('ameo_niche_boost') ?? 0.35,
  );

  Future<void> save(SharedPreferences p) async {
    await p.setString('ameo_model', model);
    await p.setBool('ameo_extra_seasons', includeExtraSeasons);
    await p.setBool('ameo_ovas', includeONAsOVAsSpecials);
    await p.setBool('ameo_movies', includeMovies);
    await p.setBool('ameo_music', includeMusic);
    await p.setBool('ameo_filter_ptw', filterPlanToWatch);
    await p.setDouble('ameo_logit_weight', logitWeight);
    await p.setDouble('ameo_niche_boost', nicheBoostFactor);
  }

  Map<String, dynamic> toJson() => {
    'model': model,
    'includeExtraSeasons': includeExtraSeasons,
    'includeONAsOVAsSpecials': includeONAsOVAsSpecials,
    'includeMovies': includeMovies,
    'includeMusic': includeMusic,
    'filterPlanToWatch': filterPlanToWatch,
    'logitWeight': logitWeight,
    'nicheBoostFactor': nicheBoostFactor,
    'popularityAttenuationFactor': 0.0008,
    'excludedIds': <int>[],
    'excludedGenreIds': <int>[],
  };
}

class _AmeoClient {
  static const endpoint = 'https://anime.ameo.dev/recommendation/recommendation';
  static const ttl = Duration(hours: 6);

  Future<List<_AmeoAnime>> recommend(String username, _AmeoSettings settings, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'ameo_cache_' + base64Url.encode(utf8.encode(username + '|' + jsonEncode(settings.toJson())));
    final cached = prefs.getString(cacheKey);
    final cachedAt = prefs.getInt(cacheKey + '_at') ?? 0;
    if (!force && cached != null && DateTime.now().millisecondsSinceEpoch - cachedAt < ttl.inMilliseconds) {
      return decode(jsonDecode(cached) as Map<String, dynamic>);
    }
    try {
      final response = await http.post(Uri.parse(endpoint),
        headers: const {'content-type': 'text/plain;charset=UTF-8', 'user-agent': 'DailyAL-Modif (Ameo integration)'},
        body: jsonEncode({
          'username': username,
          'settings': settings.toJson(),
          'availableAnimeMetadataIDs': <int>[],
          'includeContributors': false,
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Ameo HTTP ' + response.statusCode.toString());
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw const FormatException('Invalid Ameo response');
      final result = decode(body);
      await prefs.setString(cacheKey, jsonEncode(body));
      await prefs.setInt(cacheKey + '_at', DateTime.now().millisecondsSinceEpoch);
      return result;
    } catch (_) {
      if (cached != null) return decode(jsonDecode(cached) as Map<String, dynamic>);
      rethrow;
    }
  }

  List<_AmeoAnime> decode(Map<String, dynamic> body) {
    final rawMetadata = body['animeData'];
    final rawRecommendations = body['recommendations'];
    if (rawMetadata is! Map || rawRecommendations is! List) return const [];
    final metadata = <int, Map<String, dynamic>>{};
    rawMetadata.forEach((key, value) {
      final id = int.tryParse(key.toString());
      if (id != null && value is Map) metadata[id] = Map<String, dynamic>.from(value);
    });
    final result = <_AmeoAnime>[];
    for (final item in rawRecommendations) {
      final dynamic rawId = item is Map ? (item['animeId'] ?? item['id'] ?? item['malId']) : item;
      final id = rawId is num ? rawId.toInt() : int.tryParse(rawId.toString());
      if (id == null || metadata[id] == null) continue;
      result.add(_AmeoAnime.fromJson(id, metadata[id]!, item));
    }
    return result;
  }
}

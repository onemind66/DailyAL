import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/api/jikan_models.dart';
import 'package:dailyanimelist/api/malconnect.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/enums.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/widgets/search/filtermodal.dart';
import 'package:dal_commons/commons.dart';
import 'package:dal_commons/dal_commons.dart';

class JikanSearchException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;
  final bool connectionFailure;
  final bool timeout;

  const JikanSearchException({
    required this.message,
    this.statusCode,
    this.cause,
    this.connectionFailure = false,
    this.timeout = false,
  });

  @override
  String toString() => message;
}

class JikanHelper {
  static Future<SearchResult> getGenre({
    int id = 1,
    String category = "anime",
    bool fromCache = true,
    int page = 1,
    Function(dynamic)? onError,
  }) async {
    final genre = convertGenre(MalGenre(id: id), category);
    final filter = (category.equals("anime")
        ? CustomFilters.genresAnimeFilter
        : CustomFilters.genresMangaFilter)
      ..includedOptions = [genre];
    return await jikanSearch(
      '',
      category: category,
      filters: {'genres': filter},
      fromCache: fromCache,
      pageNumber: page,
    );
  }

  static Future<JikanV4Result<UserProfileV4>> getUserInfo(
      {bool fromCache = false,
      String? username,
      Function(dynamic)? onError}) async {
    return JikanV4Result.fromJson(
      DataUnionType.user,
      (await MalConnect.getContent('${CredMal.jikanV4}users/$username/full',
          withNoHeaders: true)),
    );
  }

  static Future<JikanV4Result<About>> getUserAbout(String username) async {
    return JikanV4Result.fromJson(
        DataUnionType.about,
        (await MalConnect.getContent('${CredMal.jikanV4}users/$username/about',
            withNoHeaders: true)));
  }

  static Future<ClubV4List> getUserClubs(String username) async {
    return JikanV4Result.fromJson(
            DataUnionType.club,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}users/$username/clubs',
                withNoHeaders: true)))
        .data as ClubV4List;
  }

  static Future<UserFavV4> getUserFavorites(String username) async {
    return JikanV4Result.fromJson(
            DataUnionType.favorites,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}users/$username/favorites',
                withNoHeaders: true)))
        .data as UserFavV4;
  }

  static Future<UserUpdateList> getUserUpdates(String category, int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.userupdates,
            (await MalConnect.getContent(
                '${CredMal.jikanV4}$category/$id/userupdates',
                withNoHeaders: true)))
        .data as UserUpdateList;
  }

  static Future<Club?> getClubInfo(int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.clubinfo,
            (await MalConnect.getContent('${CredMal.jikanV4}clubs/$id',
                withNoHeaders: true)))
        .data as Club?;
  }

  static Future<AnimeVideoV4?> getAnimeVideos(int id) async {
    return JikanV4Result.fromJson(
            DataUnionType.animevideo,
            (await MalConnect.getContent(
              '${CredMal.jikanV4}anime/$id/videos',
              withNoHeaders: true,
              useTimeout: true,
              retryOnFail: false,
              timeoutDuration: const Duration(seconds: 2),
            )))
        .data as AnimeVideoV4?;
  }

  static Future<JikanAnimeStatistics?> getAnimeScoreStatistics(int id) async {
    try {
      final url = '${CredMal.jikanV4}anime/$id/statistics';
      logDal('Fetching score statistics from: $url');

      final response = await MalConnect.getContent(
        url,
        withNoHeaders: true,
        useTimeout: true,
        retryOnFail: false,
        timeoutDuration: const Duration(seconds: 10),
      );

      if (response != null && response is Map<String, dynamic>) {
        logDal('Score statistics response received, parsing...');
        // MalConnect.getContent already returns decoded JSON, no need to jsonDecode
        final stats = JikanAnimeStatistics.fromJson(response['data']);
        logDal('Score statistics parsed successfully: ${stats.scores?.length ?? 0} scores');
        return stats;
      } else {
        logDal('Score statistics response is null or invalid type');
      }
      return null;
    } catch (e, stackTrace) {
      logDal('Error fetching anime statistics: $e\n$stackTrace');
      return null;
    }
  }

  static const useNewApiFields = ['genre', 'genres_exclude'];

  static Future<SearchResult> jikanSearch(String query,
      {String category = "character",
      bool fromCache = false,
      int pageNumber = 1,
      required Map<String, FilterOption> filters,
      Function(dynamic)? onError}) async {
    String custom = filterUrlBuilder(filters, category: category) ?? '';
    String url =
        "get-jikan-search-$category-for-$query-$pageNumber-${custom ?? ""}";
    if (fromCache) {
      var _result = SearchResult.fromJson(
          await CacheManager.instance.getCachedContent(url));
      if (_result?.data != null &&
          !shouldUpdateContent(
              result: _result,
              timeinHours: user.pref.cacheUpdateFrequency[homeIndex]) &&
          _result.data!.isNotEmpty) {
        return _result;
      }
    }
    try {
      final v4Url =
          '${CredMal.jikanV4}$category?q=${query ?? ''}&page=$pageNumber$custom';
      logDal('Jikan search request: $v4Url');
      final response = await MalConnect.retryGet(
        v4Url,
        Map(),
        maxAttempts: 3,
        retryClientException: true,
      );

      if (response.statusCode != 200) {
        throw JikanSearchException(
          message: 'Jikan API returned HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (e) {
        throw JikanSearchException(
          message: 'Jikan API returned an invalid JSON response.',
          cause: e,
        );
      }
      if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
        throw const JikanSearchException(
          message: 'Jikan API returned an unexpected response format.',
        );
      }

      final result = decoded;
      final searchResult = SearchResult(
        data: (result["data"] as List)
            .map<BaseNode>((e) => _fromMap(e, category))
            .toList(),
        paging: Paging(next: (pageNumber + 1).toString()),
      );
      CacheManager.instance.setCachedJson(url, searchResult);
      return searchResult;
    } on JikanSearchException {
      rethrow;
    } catch (e) {
      logDal('Jikan search failed after retry handling: ${e.runtimeType}: $e');
      throw JikanSearchException(
        message: 'Unable to complete the Jikan API search.',
        cause: e,
        connectionFailure: e is SocketException ||
            e is http.ClientException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('ClientException'),
        timeout: e is TimeoutException ||
            e.toString().contains('TimeoutException'),
      );
    }
  }

  static BaseNode _fromMap(dynamic e, String category) {
    var images = e["images"];
    String? url;
    if (images != null) {
      var jpg = images["jpg"];
      if (jpg != null) {
        url = jpg["image_url"];
      }
    }
    final Node node;

    if (e is Map<String, dynamic> && contentTypes.contains(category)) {
      final jikanAnime = JikanAnime.fromJson(e);
      node = AnimeDetailed.fromJikanJson(jikanAnime);
    } else {
      node = Node(
        id: e["mal_id"],
        title: e["title"] ?? e['name'],
        mainPicture: Picture(
          large: url,
          medium: url,
        ),
      );
    }

    return BaseNode(content: node);
  }

  static String? filterUrlBuilder(Map<String, FilterOption>? filters,
      {String category = "anime"}) {
    if (filters == null || filters.isEmpty) return null;
    String url = "";
    for (var entry in filters.entries) {
      String field = entry.key;
      FilterOption option = entry.value;
      switch (option.type) {
        case FilterType.multiple:
          String temp = "";
          if (option.includedOptions!.isNotEmpty) {
            for (var element in (option.includedOptions ?? [])) {
              temp +=
                  getApiValue(option.apiValues, option.values, element) + ",";
            }
            temp = temp.substring(0, temp.length - 1);
            url += "&$field=$temp";
          }
          if (option.excludedOptions != null &&
              option.excludedOptions!.isNotEmpty) {
            String excludeTemp = "";
            for (var element in option.excludedOptions!) {
              excludeTemp +=
                  getApiValue(option.apiValues, option.values, element) + ",";
            }
            excludeTemp = excludeTemp.substring(0, excludeTemp.length - 1);
            url += "&${option.excludeFieldName}=$excludeTemp";
          }
          break;
        default:
          String? value;
          if (option.apiValues != null) {
            value = getApiValue(option.apiValues, option.values, option.value);
          }
          url += "&$field=${value ?? option.value}";
      }
    }
    if (["anime", "manga"].contains(category) &&
        !url.contains("order_by") &&
        !url.contains("score")) {
      url += "&order_by=members&sort=desc";
    }
    return url;
  }

  static String getApiValue(apiValues, values, value) {
    try {
      return apiValues.elementAt(values.indexOf(value)).toString();
    } catch (e) {}
    return '';
  }

  static Future<SearchResult?> getAnimeReviews(int id) async {
    final url = CredMal.htmlEnd + 'anime/$id/_/reviews';
    return MalConnect.htmlListPage(url, '', (p0) => null);
  }
}

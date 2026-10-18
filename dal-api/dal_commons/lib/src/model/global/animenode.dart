import 'package:dal_commons/src/model/anime/animedetailed.dart';
import 'package:dal_commons/src/model/anime/animestudio.dart';
import 'package:dal_commons/src/model/anime/myanimeliststatus.dart';
import 'package:dal_commons/src/model/global/node.dart';
import 'package:dal_commons/src/model/global/genre.dart';
import 'package:dal_commons/src/model/global/ranking.dart';
import 'package:dal_commons/src/model/manga/mangadetailed.dart';
import 'package:dal_commons/src/model/manga/mangaauthors.dart';
import 'package:dal_commons/src/model/manga/mymangaliststatus.dart';
import 'package:dal_commons/src/constants/constant.dart';
import 'myliststatus.dart';

import 'package:json_annotation/json_annotation.dart';

List<T> _parseListSafely<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) parser,
  String fieldName,
) {
  if (value is! List) return <T>[];
  final result = <T>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    try {
      result.add(parser(Map<String, dynamic>.from(entry)));
    } catch (e) {
      logDal('BaseNode: skipped malformed $fieldName entry: $e');
    }
  }
  return result;
}

class BaseNode {
  final Node? content;
  final Ranking? ranking;
  @JsonKey(ignore: true)
  MyListStatus? myListStatus;

  BaseNode({this.content, this.ranking, this.myListStatus});

  factory BaseNode.fromJson(Map<String, dynamic>? json,
      {String category = "anime"}) {
    MyAnimeListStatus? animeList;
    MyMangaListStatus? mangaList;
    Node? node;
    final dynamic rawNode =
        json == null ? null : (json["node"] is Map ? json["node"] : json);
    final Map<String, dynamic>? rawNodeJson =
        rawNode is Map ? Map<String, dynamic>.from(rawNode) : null;

    if (json != null) {
      // List endpoints store list_status beside node. Discovery endpoints may
      // store my_list_status directly in a flat content object.
      final dynamic rawStatus =
          json["list_status"] ?? rawNodeJson?["my_list_status"];
      if (rawStatus is Map) {
        try {
          final statusJson = Map<String, dynamic>.from(rawStatus);
          if (category.equals("manga")) {
            mangaList = MyMangaListStatus.fromJson(statusJson);
          } else {
            animeList = MyAnimeListStatus.fromJson(statusJson);
          }
        } catch (e) {
          logDal('BaseNode status parse failed category=$category: $e');
        }
      }

      if (rawNodeJson != null) {
        try {
          if (category.equals("manga")) {
            node = MangaDetailed.fromJson(rawNodeJson);
          } else {
            node = AnimeDetailed.fromJson(rawNodeJson);
          }
        } catch (e) {
          logDal(
              'BaseNode detailed parse failed category=$category id=${rawNodeJson["id"]}: $e');
          // Preserve chart-relevant fields if an unrelated optional property
          // prevents the full model from being created.
          if (category.equals("manga")) {
            node = MangaDetailed(
              id: int.tryParse('${rawNodeJson["id"]}'),
              title: rawNodeJson["title"]?.toString(),
              status: rawNodeJson["status"]?.toString(),
              mean: double.tryParse('${rawNodeJson["mean"]}'),
              mediaType: rawNodeJson["media_type"]?.toString(),
              numChapters: int.tryParse('${rawNodeJson["num_chapters"]}'),
              numVolumes: int.tryParse('${rawNodeJson["num_volumes"]}'),
              genres: _parseListSafely<MalGenre>(
                rawNodeJson["genres"],
                (value) => MalGenre.fromJson(value),
                "genres",
              ),
              authors: _parseListSafely<MangaAuthors>(
                rawNodeJson["authors"],
                (value) => MangaAuthors.fromJson(value),
                "authors",
              ),
            );
          } else {
            node = AnimeDetailed(
              id: int.tryParse('${rawNodeJson["id"]}'),
              title: rawNodeJson["title"]?.toString(),
              status: rawNodeJson["status"]?.toString(),
              mean: double.tryParse('${rawNodeJson["mean"]}'),
              mediaType: rawNodeJson["media_type"]?.toString(),
              source: rawNodeJson["source"]?.toString(),
              numEpisodes: int.tryParse('${rawNodeJson["num_episodes"]}'),
              genres: _parseListSafely<MalGenre>(
                rawNodeJson["genres"],
                (value) => MalGenre.fromJson(value),
                "genres",
              ),
              studios: _parseListSafely<AnimeStudio>(
                rawNodeJson["studios"],
                (value) => AnimeStudio.fromJson(value),
                "studios",
              ),
            );
          }
        }
      }
    }

    final MyListStatus resolvedStatus;
    if (category.equals("manga")) {
      resolvedStatus = mangaList?.status != null
          ? mangaList!
          : node is MangaDetailed && node.myListStatus?.status != null
              ? node.myListStatus!
              : mangaList ?? MyMangaListStatus();
      if (node is MangaDetailed &&
          resolvedStatus is MyMangaListStatus &&
          resolvedStatus.status != null) {
        node.myListStatus = resolvedStatus;
      }
    } else {
      resolvedStatus = animeList?.status != null
          ? animeList!
          : node is AnimeDetailed && node.myListStatus?.status != null
              ? node.myListStatus!
              : animeList ?? MyAnimeListStatus();
      if (node is AnimeDetailed &&
          resolvedStatus is MyAnimeListStatus &&
          resolvedStatus.status != null) {
        node.myListStatus = resolvedStatus;
      }
    }

    return json != null
        ? BaseNode(
            myListStatus: resolvedStatus,
            content: node ?? Node.fromJson(rawNodeJson),
            ranking: Ranking.fromJson(json["ranking"]))
        : BaseNode();
  }

  Map<String, dynamic> toJson() {
    return {
      "node": content?.toJson(),
      "ranking": ranking,
      "list_status": myListStatus
    };
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dailyanimelist/api/auth/auth.dart';
import 'package:dailyanimelist/api/credmal.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/cache/cachemanager.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dal_api/handlers/handler_core.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:dal_commons/dal_commons.dart' as commons;
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

class MalConnect {
  static bool _isJikanDetailRequest(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return RegExp(r'^/(?:v4/)?(?:characters?|people)/[0-9]+(?:/full)?/?$').hasMatch(path);
  }
  static String _diagnosticPath(String url) =>
      Uri.tryParse(url)?.path ?? '[invalid-uri]';

  static const _options = RetryOptions(maxAttempts: 8);
  static const _retryDuration = const Duration(seconds: 10);

  static Future<http.Response> retryGet(
    String url,
    Map<String, String> headers, {
    int maxAttempts = 8,
    bool retryClientException = false,
  }) async {
    final isDalLocal = url.startsWith('http://localhost:8080');
    final options = maxAttempts == 8 && !retryClientException
        ? _options
        : RetryOptions(
            maxAttempts: maxAttempts,
            delayFactor: const Duration(seconds: 1),
            maxDelay: const Duration(seconds: 2),
            randomizationFactor: 0,
          );
    var attempt = 1;
    final response = await options.retry(
      () async {
        if (isDalLocal) {
          var value = await HandlerCore()
              .handleRequestAsString(Uri.parse(url))
              .timeout(_retryDuration);
          return http.Response.bytes(utf8.encode(value ?? ''), 200, headers: {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'
          });
        }
        return _sendWithAuthRefresh(
          url,
          headers,
          () => http
              .get(Uri.parse(url), headers: headers)
              .timeout(_retryDuration),
        );
      },
      retryIf: (e) {
        final shouldRetry = e is SocketException ||
            e is TimeoutException ||
            (retryClientException && e is http.ClientException);
        if (shouldRetry && attempt < maxAttempts) {
          logDal('Retrying HTTP GET (attempt ${attempt + 1}/$maxAttempts) after ${e.runtimeType}');
        }
        attempt++;
        return shouldRetry;
      },
    );
    return response;
  }

  static Future<http.Response> _sendWithAuthRefresh(
    String url,
    Map<String, String> headers,
    Future<http.Response> Function() send,
  ) async {
    final response = await send();
    if (!url.startsWith(CredMal.endPoint) ||
        response.statusCode != 401 ||
        user.status != AuthStatus.AUTHENTICATED ||
        !headers.containsKey('Authorization')) {
      return response;
    }
    if (!await MalAuth.refreshToken()) return response;

    final authResponse = user.authResponse;
    if (authResponse?.accessToken == null || authResponse?.tokenType == null) {
      return response;
    }
    headers['Authorization'] =
        '${authResponse!.tokenType} ${authResponse.accessToken}';
    return send();
  }

  static Future<http.Response> retryGetNoH(String url) => retryGet(url, Map());

  /// Standard Http Get Request with Auth Header
  static Future<dynamic> httpGetAsync(String url,
      {Map<String, String>? headers, bool usePlainOld = false}) async {
    if (headers == null) {
      headers = new Map();
    }
    if (!usePlainOld) {
      headers["X-MAL-Client-ID"] = CredMal.clientId;
      headers["Accept"] = "application/json";
      if (user.status == AuthStatus.AUTHENTICATED) {
        try {
          if (MalAuth.checkIfTokenExpired(user.authResponse!)) {
            await MalAuth.refreshToken();
          }
        } catch (e) {
          logDal(e);
        }
        final authResponse = user.authResponse;
        if (authResponse?.tokenType != null &&
            authResponse?.accessToken != null) {
          headers["Authorization"] =
              '${authResponse!.tokenType} ${authResponse.accessToken}';
        }
      }
    }

    return retryGet(url, headers);
  }

  /// Standard GetContent from Cache or API
  static Future<dynamic> getContent(
    String url, {
    Map<String, String>? headers,
    bool withNoHeaders = false,
    bool includeNsfw = true,
    bool fromCache = true,
    bool retryOnFail = true,
    bool useTimeout = false,
    Duration? timeoutDuration,
    int? timeinHours,
  }) async {
    if (user?.pref?.nsfw != null && includeNsfw) {
      String op = Uri.dataFromString(url).queryParameters.isEmpty ? "?" : "&";
      url = "$url${op}nsfw=${user.pref.nsfw ? '1' : '0'}&fromCache=$fromCache";
    }

    bool timeoutCache = false;
    dynamic cachedResult;

    final detail = _isJikanDetailRequest(url);
    final path = _diagnosticPath(url);
    final watch = Stopwatch()..start();
    if (fromCache) {
      if (detail) logDal('[Jikan HTTP] cache_lookup path=$path');
      else logDal("Cache ->> $url");
      Map<String, dynamic>? _result =
          await CacheManager.instance.getCachedContent(url);
      if (_result != null) {
        cachedResult = _result;
        if (!shouldUpdateContent(
          result: _result,
          timeinHours: timeinHours ?? user.pref.cacheUpdateFrequency[homeIndex],
        )) {
          _result["url"] = url;
          _result["fromCache"] = true;
          if (detail) logDal('[Jikan HTTP] cache_hit path=$path keys=${_result.keys.join(',')}');
          return _result;
        }
      }
    }
    if (detail) logDal('[Jikan HTTP] network_request path=$path retry=$retryOnFail');
    else logDal("API ->> $url");
    if (headers == null) {
      headers = new Map();
    }
    if (!withNoHeaders) {
      headers["X-MAL-Client-ID"] = CredMal.clientId;
      headers["Accept"] = "application/json";
      if (user.status == AuthStatus.AUTHENTICATED) {
        try {
          if (MalAuth.checkIfTokenExpired(user.authResponse!)) {
            await MalAuth.refreshToken();
          }
          final authResponse = user.authResponse;
          if (authResponse?.tokenType != null &&
              authResponse?.accessToken != null) {
            headers["Authorization"] =
                '${authResponse!.tokenType} ${authResponse.accessToken}';
          }
        } catch (e) {
          logDal(e);
        }
      }
    }
    http.Response response;
    try {
      response = await _getWithOptions(
        url,
        headers,
        retryOnFail: retryOnFail,
        useTimeout: useTimeout,
        timeoutDuration: timeoutDuration,
        onTimeout: () {
          timeoutCache = true;
        },
      );
      if (detail) logDal('[Jikan HTTP] network_response path=$path status=${response.statusCode} '
          'content_type=${response.headers['content-type'] ?? 'unknown'} '
          'body_bytes=${response.bodyBytes.length} elapsed_ms=${watch.elapsedMilliseconds}');
      if (response.statusCode == 200) {
        if (timeoutCache) {
          if (detail) logDal('[Jikan HTTP] timeout_cache_fallback path=$path');
          return cachedResult;
        } else {
          Map<String, dynamic> result = jsonDecode(response.body) ?? {};
          result["url"] = url;
          result["fromCache"] = false;
          CacheManager.instance.setCachedJson(url, result);
          result["lastUpdated"] = DateTime.now().toString();
          if (detail) logDal('[Jikan HTTP] json_decoded path=$path root_keys=${result.keys.join(',')}');
          return result;
        }
      }
      return null;
    } catch (e, stack) {
      if (detail) logDal('[Jikan HTTP] network_exception path=$path type=${e.runtimeType} stack=$stack');
      else logDal(e);
      return null;
    }
  }

  static Future<http.Response> _getWithOptions(
    String url,
    Map<String, String> headers, {
    required bool retryOnFail,
    required bool useTimeout,
    Duration? timeoutDuration,
    required Function() onTimeout,
  }) async {
    final isDalLocal = url.startsWith('http://0.0.0.0:8080');
    if (retryOnFail) {
      return retryGet(url, headers);
    } else if (isDalLocal) {
      var value = await HandlerCore()
          .handleRequestAsString(Uri.parse(url))
          .timeout(_retryDuration);
      return http.Response.bytes(utf8.encode(value ?? ''), 200, headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'
      });
    } else if (useTimeout) {
      return _sendWithAuthRefresh(
        url,
        headers,
        () => http
            .get(Uri.parse(url), headers: headers)
            .timeout(timeoutDuration!, onTimeout: () {
          onTimeout();
          return http.Response('cached', 200);
        }),
      );
    } else {
      return _sendWithAuthRefresh(
          url, headers, () => http.get(Uri.parse(url), headers: headers));
    }
  }

  static Future<Map<String, String>> get _headers async {
    Map<String, String> headers = Map();
    headers["X-MAL-Client-ID"] = CredMal.clientId;
    headers["Accept"] = "application/json";
    if (user.status == AuthStatus.AUTHENTICATED) {
      try {
        if (MalAuth.checkIfTokenExpired(user.authResponse!)) {
          await MalAuth.refreshToken();
        }
      } catch (e) {
        logDal(e);
      }
      final authResponse = user.authResponse;
        if (authResponse?.tokenType != null &&
          authResponse?.accessToken != null) {
        headers["Authorization"] =
            '${authResponse!.tokenType} ${authResponse.accessToken}';
      }
    }
    return headers;
  }

  /// Standard Http Put Request with Auth Header
  static Future<http.Response> httpPutAsync(String url,
      {Map<String, String>? headers, Map<String, dynamic>? body}) async {
    if (headers == null) {
      headers = new Map();
    }
    if (body == null) {
      body = new Map();
    }
    headers["X-MAL-Client-ID"] = CredMal.clientId;
    headers["Accept"] = "application/json";
    if (user.status == AuthStatus.AUTHENTICATED) {
      try {
        if (MalAuth.checkIfTokenExpired(user.authResponse!)) {
          await MalAuth.refreshToken();
        }
      } catch (e) {
        logDal(e);
      }
      final authResponse = user.authResponse;
        if (authResponse?.tokenType != null &&
          authResponse?.accessToken != null) {
        headers["Authorization"] =
            '${authResponse!.tokenType} ${authResponse.accessToken}';
      }
    }
    return _sendWithAuthRefresh(
      url,
      headers,
      () => http.put(Uri.parse(url), body: body, headers: headers),
    );
  }

  static Future<http.Response> delete(String url) async {
    final headers = await _headers;
    return _sendWithAuthRefresh(
      url,
      headers,
      () => http.delete(Uri.parse(url), headers: headers),
    );
  }

  static Future<SearchResult?> htmlListPage(
    String url,
    String nextUrl,
    Function(Document) fromHtml, {
    bool fromCache = false,
    List<int> validCodes = const [200],
  }) async {
    SearchResult? result;
    logDal('Html --> $url');
    var response = await retryGet(url, Map());
    if (response == null || !validCodes.contains(response.statusCode)) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
      result!.fromCache = false;
      if (result.data != null && result.data!.isNotEmpty) {
        result.paging = Paging(next: nextUrl, previous: url);
      } else {
        result.paging = Paging();
      }
    }

    return result;
  }

  static Future<commons.Node?> htmlPage(
      String url, commons.Node Function(Document) fromHtml,
      {bool fromCache = false}) async {
    commons.Node? result;
    logDal(url);
    var response = await retryGet(url, Map());
    if (response.statusCode != 200) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
      result.fromCache = false;
    }

    return result;
  }

  static Future<T?> cachedHtml<T>(
    String url,
    T Function(Document) fromHtml,
    T Function(Map<String, dynamic>) fromJson, {
    bool fromCache = true,
    int? timeinHours,
  }) async {
    T? result;
    if (fromCache) {
      Map<String, dynamic> _result =
          await CacheManager.instance.getCachedContent(url);
      if (_result != null) {
        if (!shouldUpdateContent(
          result: _result,
          timeinHours: timeinHours ?? user.pref.cacheUpdateFrequency[homeIndex],
        )) {
          logDal("Cache ->> $url");
          _result["url"] = url;
          _result["fromCache"] = true;
          return fromJson(_result);
        }
      }
    }
    logDal("Hitting ->> $url");
    var response = await retryGet(url, Map());
    if (response == null || response.statusCode != 200) {
      logDal(response.body);
    } else {
      result = fromHtml(parse(response.body));
    }

    return result;
  }
}

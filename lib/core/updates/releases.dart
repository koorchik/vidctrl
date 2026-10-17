import 'dart:convert';
import 'dart:io';

/// A version such as 1.2.0 or 1.2.0-beta.1, ordered the way semantic
/// versioning orders them: a pre-release comes before its release, and
/// beta.2 before beta.10.
class Version implements Comparable<Version> {
  const Version._(this._numbers, this._preRelease, this._text);

  /// Reads "1.2.0", "v1.2.0" or "1.2.0-beta.1"; null for anything else.
  static Version? tryParse(String text) {
    final written = text.trim().replaceFirst(RegExp('^v'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(written);
    if (match == null) return null;
    return Version._(
      [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)],
      match.group(4)?.split('.') ?? const [],
      written,
    );
  }

  final List<int> _numbers;

  /// Empty for a release.
  final List<String> _preRelease;
  final String _text;

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  int compareTo(Version other) {
    for (var i = 0; i < 3; i++) {
      final order = _numbers[i].compareTo(other._numbers[i]);
      if (order != 0) return order;
    }
    if (_preRelease.isEmpty || other._preRelease.isEmpty) {
      return other._preRelease.length.sign - _preRelease.length.sign;
    }
    for (var i = 0; i < _preRelease.length; i++) {
      if (i == other._preRelease.length) return 1;
      final order = _compareIdentifiers(_preRelease[i], other._preRelease[i]);
      if (order != 0) return order;
    }
    return _preRelease.length == other._preRelease.length ? 0 : -1;
  }

  /// Numbers by value, and before words; words alphabetically.
  static int _compareIdentifiers(String a, String b) {
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(Object.hashAll(_numbers), _preRelease.join());

  /// As written, without the "v".
  @override
  String toString() => _text;
}

/// The newest release, and the page that has its downloads.
class Release {
  const Release({required this.version, required this.page});

  final Version version;
  final Uri page;
}

/// Thrown when the newest release cannot be found out: no connection, an
/// answer that is not a release, or no release at all.
class ReleaseCheckFailed implements Exception {
  const ReleaseCheckFailed(this.reason);

  final String reason;

  @override
  String toString() => 'ReleaseCheckFailed: $reason';
}

/// Where the app is published.
abstract interface class ReleaseSource {
  /// The newest release that is not a pre-release.
  Future<Release> latest();
}

/// The releases of a GitHub repository ("owner/name"), through GitHub's API,
/// which gives the newest one that is neither a draft nor a pre-release.
class GitHubReleases implements ReleaseSource {
  GitHubReleases(this.repository, {required this.userAgent});

  final String repository;

  /// GitHub refuses requests without one.
  final String userAgent;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<Release> latest() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
      );
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw ReleaseCheckFailed('GitHub answered ${response.statusCode}');
      }
      return parseGitHubRelease(jsonDecode(body));
    } on ReleaseCheckFailed {
      rethrow;
    } on Exception catch (e) {
      // No connection, a timeout, or an answer that is not JSON.
      throw ReleaseCheckFailed('$e');
    } finally {
      client.close(force: true);
    }
  }
}

/// A release as GitHub's API describes it: the tag names the version, and
/// the release's page has its notes and downloads.
Release parseGitHubRelease(Object? json) {
  if (json case {'tag_name': String tag, 'html_url': String page}) {
    final version = Version.tryParse(tag);
    final uri = Uri.tryParse(page);
    if (version != null && uri != null && uri.isScheme('https')) {
      return Release(version: version, page: uri);
    }
  }
  throw const ReleaseCheckFailed('not a release with a version tag');
}

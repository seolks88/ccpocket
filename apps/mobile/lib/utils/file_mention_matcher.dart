/// Score a file or directory path against an @-mention query.
///
/// Lower score = better match. Returns -1 if no match.
int scoreFileMentionPath(String path, String query) {
  return scoreFileMentionCandidate(FileMentionCandidate(path), query);
}

/// Precomputed searchable representation of a project file path.
///
/// The composer calls @-mention ranking on every keystroke, so path splitting
/// and compact fuzzy strings are prepared once when the file list changes.
class FileMentionCandidate {
  final String path;
  final String displayPath;
  final String fileName;
  final String nameWithoutExt;
  final List<String> segments;
  final String compactPath;

  factory FileMentionCandidate(String rawPath) {
    final displayPath = _displayPath(rawPath);
    final fileName = _fileName(displayPath);
    return FileMentionCandidate._(
      path: rawPath,
      displayPath: displayPath,
      fileName: fileName,
      nameWithoutExt: _nameWithoutExt(fileName),
      segments: displayPath.split('/'),
      compactPath: _compactForFuzzyMatch(displayPath),
    );
  }

  const FileMentionCandidate._({
    required this.path,
    required this.displayPath,
    required this.fileName,
    required this.nameWithoutExt,
    required this.segments,
    required this.compactPath,
  });
}

class FileMentionIndex {
  final List<FileMentionCandidate> _candidates;

  FileMentionIndex(Iterable<String> paths)
    : _candidates = paths.map(FileMentionCandidate.new).toList(growable: false);

  bool get isNotEmpty => _candidates.isNotEmpty;

  List<String> rank(String query, {int limit = 15}) {
    return rankFileMentionCandidates(_candidates, query, limit: limit);
  }
}

List<String> rankFileMentionPaths(
  Iterable<String> paths,
  String query, {
  int limit = 15,
}) {
  return rankFileMentionCandidates(
    paths.map(FileMentionCandidate.new),
    query,
    limit: limit,
  );
}

List<String> rankFileMentionCandidates(
  Iterable<FileMentionCandidate> candidates,
  String query, {
  int limit = 15,
}) {
  if (limit <= 0) return const [];
  final top = <({String file, int score})>[];
  for (final candidate in candidates) {
    final score = scoreFileMentionCandidate(candidate, query);
    if (score < 0) continue;
    final item = (file: candidate.path, score: score);
    final insertAt = _insertionIndex(top, item);
    if (insertAt >= limit) continue;
    top.insert(insertAt, item);
    if (top.length > limit) top.removeLast();
  }
  return top.map((match) => match.file).toList(growable: false);
}

int scoreFileMentionCandidate(FileMentionCandidate candidate, String query) {
  final q = query.toLowerCase().trim();

  if (q.isEmpty) return 1;
  if (candidate.nameWithoutExt == q) return 0;
  if (candidate.fileName.startsWith(q)) return 1;
  if (candidate.nameWithoutExt.startsWith(q)) return 1;
  if (candidate.fileName.contains(q)) return 2;
  if (candidate.segments.any((s) => s.startsWith(q))) return 3;
  if (candidate.displayPath.contains(q)) return 4;

  final compactQuery = _compactForFuzzyMatch(q);
  if (compactQuery.length < 2) return -1;

  final fuzzyScore = _subsequenceGapScore(candidate.compactPath, compactQuery);
  return fuzzyScore == null ? -1 : 5 + fuzzyScore;
}

int _insertionIndex(
  List<({String file, int score})> top,
  ({String file, int score}) item,
) {
  for (var i = 0; i < top.length; i++) {
    final other = top[i];
    final scoreCmp = item.score.compareTo(other.score);
    if (scoreCmp < 0) return i;
    if (scoreCmp == 0 && item.file.length < other.file.length) return i;
  }
  return top.length;
}

String _displayPath(String rawPath) {
  final lower = rawPath.toLowerCase();
  return lower.endsWith('/') ? lower.substring(0, lower.length - 1) : lower;
}

String _fileName(String displayPath) => displayPath.split('/').last;

String _nameWithoutExt(String fileName) => fileName.split('.').first;

final _nonFuzzyCharsPattern = RegExp(r'[^a-z0-9]');

String _compactForFuzzyMatch(String value) {
  return value.replaceAll(_nonFuzzyCharsPattern, '');
}

int? _subsequenceGapScore(String candidate, String query) {
  var searchFrom = 0;
  var previous = -1;
  var first = -1;
  var gapScore = 0;

  for (final unit in query.codeUnits) {
    var found = -1;
    for (var i = searchFrom; i < candidate.length; i++) {
      if (candidate.codeUnitAt(i) == unit) {
        found = i;
        break;
      }
    }
    if (found == -1) return null;

    if (first == -1) {
      first = found;
    } else {
      gapScore += found - previous - 1;
    }
    previous = found;
    searchFrom = found + 1;
  }

  return first + gapScore;
}

/// Where Fiend looks for new versions: the download site's release.json, written by scripts/build.ps1.
const defaultUpdateFeed = 'https://fiend-delta.vercel.app/downloads/release.json';

/// Compares dotted versions ("1.10.0" > "1.9.2"). Build suffixes ("+3") are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final nums = v.trim().split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

class ReleaseFile {
  ReleaseFile({required this.file, required this.size, required this.sha256, required this.url});
  final String file;
  final int size;
  final String sha256;
  final Uri url;
}

class Release {
  Release({required this.version, required this.notes, required this.installer, required this.built});

  final String version;
  final List<String> notes;
  final ReleaseFile installer;
  final String built;

  /// Reads release.json. Returns null if it has no installer (Fiend updates through the installer).
  static Release? parse(Map<String, dynamic> json, Uri feed) {
    final inst = json['installer'];
    final version = json['version']?.toString() ?? '';
    if (inst is! Map || version.isEmpty) return null;
    final file = inst['file']?.toString() ?? '';
    final sha = inst['sha256']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^Fiend-[\w.]+-setup\.exe$').hasMatch(file) || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      return null;
    }
    return Release(
      version: version,
      built: json['built']?.toString() ?? '',
      notes: (json['notes'] as List? ?? const []).map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList(),
      installer: ReleaseFile(
        file: file,
        size: (inst['size'] as num?)?.toInt() ?? 0,
        sha256: sha,
        // The installer sits next to release.json.
        url: feed.resolve(file),
      ),
    );
  }
}

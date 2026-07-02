import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/protocol.dart';

/// Stores protocol definitions as one JSON file per protocol under
/// [root] (`<protocolsRoot>/<id>.json`). Mirrors the file-based style of
/// [SessionRepository]; protocols are the design objects a researcher creates,
/// saves as drafts, and publishes.
class ProtocolRepository extends ChangeNotifier {
  String _root = '';
  List<Protocol> protocols = [];

  String get root => _root;

  void setRoot(String root) {
    if (root == _root) return;
    _root = root;
    refresh();
  }

  Future<void> refresh() async {
    final loaded = <Protocol>[];
    try {
      final dir = Directory(_root);
      if (await dir.exists()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (!f.path.toLowerCase().endsWith('.json')) continue;
          try {
            loaded.add(Protocol.fromJson(
                jsonDecode(await f.readAsString()) as Map<String, dynamic>));
          } catch (e) {
            debugPrint('Skipping unreadable protocol ${f.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Protocol refresh failed: $e');
    }
    loaded.sort((a, b) => b.updatedUtc.compareTo(a.updatedUtc)); // newest first
    protocols = loaded;
    notifyListeners();
  }

  Protocol? byId(String id) {
    for (final p in protocols) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _pathFor(String id) => '$_root${Platform.pathSeparator}$id.json';

  /// Write (or overwrite) a protocol, stamping [Protocol.updatedUtc].
  Future<void> save(Protocol p) async {
    p.updatedUtc = DateTime.now().toUtc().toIso8601String();
    try {
      final dir = Directory(_root);
      if (!await dir.exists()) await dir.create(recursive: true);
      await File(_pathFor(p.id))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(p.toJson()));
    } catch (e) {
      debugPrint('Protocol save failed: $e');
      rethrow;
    }
    final i = protocols.indexWhere((x) => x.id == p.id);
    final stored = p.clone();
    if (i >= 0) {
      protocols[i] = stored;
    } else {
      protocols.insert(0, stored);
    }
    protocols.sort((a, b) => b.updatedUtc.compareTo(a.updatedUtc));
    notifyListeners();
  }

  /// Mark published and bump the version, then persist.
  Future<void> publish(Protocol p) async {
    p.published = true;
    p.version += 1;
    await save(p);
  }

  Future<void> delete(String id) async {
    try {
      final f = File(_pathFor(id));
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Protocol delete failed: $e');
    }
    protocols.removeWhere((x) => x.id == id);
    notifyListeners();
  }
}

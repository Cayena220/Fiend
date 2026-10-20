import 'dart:async';

import 'models.dart';

class FiendException implements Exception {
  FiendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Rust engine. The native implementation calls fiend_core.dll;
/// tests use [FakeBridge].
abstract class FiendBridge {
  Future<dynamic> call(String method, [Map<String, dynamic>? params]);
}

/// A background job running in the engine.
class Job {
  Job._(this._bridge, this.id);

  final FiendBridge _bridge;
  final int id;

  static Future<Job> start(FiendBridge bridge, String kind, [Map<String, dynamic>? params]) async {
    final r = await bridge.call('job.start', {'kind': kind, 'params': params ?? {}});
    return Job._(bridge, (r['id'] as num).toInt());
  }

  Future<void> cancel() => _bridge.call('job.cancel', {'id': id});

  /// Polls until the job finishes and returns its result.
  Future<dynamic> wait(void Function(JobProgress) onProgress,
      {Duration interval = const Duration(milliseconds: 250)}) async {
    while (true) {
      final s = (await _bridge.call('job.status', {'id': id}) as Map).cast<String, dynamic>();
      onProgress(JobProgress((s['progress'] as Map).cast<String, dynamic>()));
      if (s['finished'] == true) {
        unawaited(_bridge.call('job.dispose', {'id': id}));
        if (s['error'] != null) throw FiendException(s['error'].toString());
        return s['result'];
      }
      await Future<void>.delayed(interval);
    }
  }
}

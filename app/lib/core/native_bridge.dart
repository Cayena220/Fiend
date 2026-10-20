import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bridge.dart';

typedef _InvokeNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class _Engine {
  _Engine(DynamicLibrary lib)
      : invoke = lib.lookupFunction<_InvokeNative, _InvokeNative>('fiend_invoke'),
        free = lib.lookupFunction<_FreeNative, _FreeDart>('fiend_free');

  final _InvokeNative invoke;
  final _FreeDart free;

  static _Engine? _instance;
  static _Engine load(String path) => _instance ??= _Engine(DynamicLibrary.open(path));
}

String _invokeSync(String dllPath, String request) {
  final engine = _Engine.load(dllPath);
  final req = request.toNativeUtf8();
  try {
    final res = engine.invoke(req);
    try {
      return res.toDartString();
    } finally {
      engine.free(res);
    }
  } finally {
    malloc.free(req);
  }
}

/// Calls fiend_core.dll. Each call runs on a short-lived isolate so the UI never blocks.
class NativeBridge implements FiendBridge {
  NativeBridge([String? dllPath])
      : dllPath = dllPath ??
            '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}fiend_core.dll';

  final String dllPath;

  bool get available => File(dllPath).existsSync();

  @override
  Future<dynamic> call(String method, [Map<String, dynamic>? params]) async {
    final request = jsonEncode({'method': method, 'params': params ?? const {}});
    final path = dllPath;
    final text = await Isolate.run(() => _invokeSync(path, request));
    final response = jsonDecode(text) as Map<String, dynamic>;
    if (response['ok'] == true) return response['data'];
    throw FiendException(response['error']?.toString() ?? 'The engine returned an error');
  }
}

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// A Windows power request (`PowerCreateRequest`): while it is set, Windows
/// does not go to sleep by itself. It belongs to this process, so Windows
/// drops it when the app ends for any reason. `powercfg /requests` lists it
/// with its reason.
class PowerRequest {
  PowerRequest._(this._handle, this._reason);

  /// Keeps the computer awake, the screen not; null when Windows refuses.
  static PowerRequest? systemRequired(String reason) {
    final text = reason.toNativeUtf16();
    final context = calloc<_ReasonContext>()
      ..ref.version = _powerRequestContextVersion
      ..ref.flags = _powerRequestContextSimpleString
      ..ref.simpleReasonString = text;
    final handle = _powerCreateRequest(context);
    calloc.free(context);
    if (handle.address == _invalidHandle) {
      calloc.free(text);
      return null;
    }
    if (_powerSetRequest(handle, _powerRequestSystemRequired) == 0) {
      _closeHandle(handle);
      calloc.free(text);
      return null;
    }
    return PowerRequest._(handle, text);
  }

  final Pointer<Void> _handle;
  final Pointer<Utf16> _reason;

  void clear() {
    _powerClearRequest(_handle, _powerRequestSystemRequired);
    _closeHandle(_handle);
    calloc.free(_reason);
  }
}

const _powerRequestContextVersion = 0;
const _powerRequestContextSimpleString = 0x1;
const _powerRequestSystemRequired = 1;
const _invalidHandle = -1;

/// `REASON_CONTEXT`: the reason is a union whose larger member, the
/// localized reason, sets its size.
final class _ReasonContext extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int flags;
  external Pointer<Utf16> simpleReasonString;
  @Uint32()
  external int localizedReasonId;
  @Uint32()
  external int reasonStringCount;
  external Pointer<Void> reasonStrings;
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _powerCreateRequest = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<_ReasonContext>),
      Pointer<Void> Function(Pointer<_ReasonContext>)
    >('PowerCreateRequest');

final _powerSetRequest = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)
    >('PowerSetRequest');

final _powerClearRequest = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)
    >('PowerClearRequest');

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CloseHandle',
    );

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Holds and lets go of a whole process on Windows, which has no SIGSTOP.
/// `NtSuspendProcess` stops every thread of it at once, as Sysinternals'
/// pssuspend does; a held process can still be killed. Returns whether
/// Windows did it.
bool suspendProcess(int pid) => _withProcess(pid, _ntSuspendProcess);

bool resumeProcess(int pid) => _withProcess(pid, _ntResumeProcess);

bool _withProcess(int pid, int Function(Pointer<Void>) call) {
  final handle = _openProcess(_processSuspendResume, 0, pid);
  if (handle == nullptr) return false;
  try {
    return call(handle) == 0;
  } finally {
    _closeHandle(handle);
  }
}

const _processSuspendResume = 0x0800;

/// Puts process [pid] into a job that Windows ends, with every process in
/// it, when its last handle closes: the app holds that handle until it ends,
/// however it ends. Returns whether Windows did it.
bool endWithThisProcess(int pid) {
  final job = _job;
  if (job == null) return false;
  final process = _openProcess(_processSetQuota | _processTerminate, 0, pid);
  if (process == nullptr) return false;
  try {
    return _assignProcessToJobObject(job, process) != 0;
  } finally {
    _closeHandle(process);
  }
}

final Pointer<Void>? _job = () {
  final job = _createJobObject(nullptr, nullptr);
  if (job == nullptr) return null;
  // JOBOBJECT_EXTENDED_LIMIT_INFORMATION on 64-bit Windows: 144 bytes, its
  // LimitFlags 16 bytes in.
  final info = calloc<Uint8>(144);
  (info + 16).cast<Uint32>().value = _jobObjectLimitKillOnJobClose;
  final set = _setInformationJobObject(
    job,
    _jobObjectExtendedLimitInformation,
    info.cast(),
    144,
  );
  calloc.free(info);
  if (set == 0) {
    _closeHandle(job);
    return null;
  }
  return job;
}();

const _processSetQuota = 0x0100;
const _processTerminate = 0x0001;
const _jobObjectExtendedLimitInformation = 9;
const _jobObjectLimitKillOnJobClose = 0x2000;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _ntdll = DynamicLibrary.open('ntdll.dll');

final _openProcess = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Uint32),
      Pointer<Void> Function(int, int, int)
    >('OpenProcess');

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CloseHandle',
    );

final _createJobObject = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
    >('CreateJobObjectW');

final _setInformationJobObject = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int, Pointer<Void>, int)
    >('SetInformationJobObject');

final _assignProcessToJobObject = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)
    >('AssignProcessToJobObject');

/// Both return an NTSTATUS, 0 for success.
final _ntSuspendProcess = _ntdll
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'NtSuspendProcess',
    );

final _ntResumeProcess = _ntdll
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'NtResumeProcess',
    );

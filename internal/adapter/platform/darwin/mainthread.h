//
//  mainthread.h
//  Neru
//
//  Copyright © 2025 Neru. All rights reserved.
//

#ifndef MAINTHREAD_H
#define MAINTHREAD_H

#include <stdint.h>

/// Run a Go function on the main thread and wait for it; inline when the caller
/// is already on the main thread, where a dispatch_sync would deadlock.
/// @param handle runtime/cgo Handle of the func() to run (OnMainThread)
void NeruRunOnMainThread(uintptr_t handle);

#endif /* MAINTHREAD_H */

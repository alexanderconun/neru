//go:build darwin

package darwin

/*
#include "mainthread.h"
#include <pthread.h>
*/
import "C"

import "runtime/cgo"

// OnMainThread runs fn on the Cocoa main thread and waits for it; on the main
// thread it runs fn inline. It is a main-thread round trip: the caller may
// hold h.mu across it only because nothing on the main queue takes h.mu
// (internal/app/modes/AGENTS.md), and fn must not wait on anything that does.
//
// The handle lives exactly as long as this call, so unlike the two callback
// idioms in AGENTS.md it needs no slot or registry.
func OnMainThread(fn func()) {
	handle := cgo.NewHandle(fn)
	defer handle.Delete()

	C.NeruRunOnMainThread(C.uintptr_t(handle))
}

// IsMainThread reports whether the caller runs on the Cocoa main thread.
func IsMainThread() bool { return C.pthread_main_np() != 0 }

//export neruRunGoHandle
func neruRunGoHandle(handle C.uintptr_t) {
	fn, _ := cgo.Handle(handle).Value().(func())
	fn()
}

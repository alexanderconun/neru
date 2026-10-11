//go:build darwin && homekey_ui

package settingsui

// bin/libhomekeysettings.a is the Swift code (scripts/build-settings.sh). Its
// objects name the SwiftUI, AppKit and Swift runtime libraries themselves;
// /usr/lib/swift resolves inside the SDK. Link with CC="xcrun clang", the
// toolchain that built the library.

/*
#cgo LDFLAGS: -L${SRCDIR}/../../../bin -lhomekeysettings -L/usr/lib/swift
#include <stdlib.h>
#include "settingsui.h"

// A file with //export may define nothing but statics.
static inline void homekeyCallWatch(HomekeyWatchFn fn, void *owner, char *line) {
	fn(owner, line);
}
*/
import "C"

import (
	"context"
	"runtime/cgo"
	"unsafe"
)

// Open shows a window: "settings", "tutorial" or "training". It returns at
// once and never fails here; Swift shows the window on the main thread. Safe
// from any thread, the Cocoa main thread included.
func Open(window string) error {
	cWindow := C.CString(window)
	defer C.free(unsafe.Pointer(cWindow))

	C.HomekeySettingsOpen(cWindow)

	return nil
}

// HomekeyCommand answers one request; see command. It blocks: Swift calls it
// off the main thread. The reply is malloc'd and the caller frees it.
//
//export HomekeyCommand
func HomekeyCommand(request *C.char) *C.char {
	return C.CString(string(command(context.Background(), []byte(C.GoString(request)))))
}

// HomekeyWatch streams watch lines to fn on a Go thread, then a NULL line once
// when the stream ends. It returns the handle HomekeyWatchStop takes.
//
//export HomekeyWatch
func HomekeyWatch(fn C.HomekeyWatchFn, owner unsafe.Pointer) C.uintptr_t {
	stop := watch(func(line []byte) {
		cLine := C.CString(string(line))
		C.homekeyCallWatch(fn, owner, cLine)
		C.free(unsafe.Pointer(cLine))
	}, func() { C.homekeyCallWatch(fn, owner, nil) })

	return C.uintptr_t(cgo.NewHandle(stop))
}

// HomekeyWatchStop ends a watch and frees its handle; call it once per watch,
// after the stream ended by itself too. The NULL line still follows.
//
//export HomekeyWatchStop
func HomekeyWatchStop(watch C.uintptr_t) {
	handle := cgo.Handle(watch)
	stop, _ := handle.Value().(context.CancelFunc)
	handle.Delete()
	stop()
}

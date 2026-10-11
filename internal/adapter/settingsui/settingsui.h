//
//  settingsui.h
//  Homekey
//
//  The settings windows (macos/NeruSettings, Swift) and the daemon they run
//  in. Swift imports this header (scripts/build-settings.sh); the Go side is
//  open_darwin.go, built only with -tags homekey_ui.
//
//  Types match cgo's generated prototypes exactly (char *, not const char *),
//  or _cgo_export.c fails to compile with conflicting declarations.
//

#pragma once

#include <stdint.h>

#pragma mark - Go, called from Swift

/// Answers one request, {"action":…,"args":[…]} as docs/reference/ipc.md
/// describes, with the JSON reply the IPC socket would send. It blocks and
/// may wait on the main thread: never call it there. Free the reply with free(3).
char *HomekeyCommand(char *request);

/// Streams `neru watch` lines to HomekeyWatchLine(owner, …). Returns the
/// handle HomekeyWatchStop takes, exactly once, even after the stream ended.
uintptr_t HomekeyWatch(void *owner);
void HomekeyWatchStop(uintptr_t watch);

#pragma mark - Swift, called from Go

/// Shows the window named "settings", "tutorial" or "training". Returns at
/// once from any thread; the window opens on the main thread.
void HomekeySettingsOpen(char *window);

/// Gets each line of the watch HomekeyWatch(owner) started, on a Go thread,
/// then NULL once when the stream ends. It copies the line and returns at once.
void HomekeyWatchLine(void *owner, char *line);

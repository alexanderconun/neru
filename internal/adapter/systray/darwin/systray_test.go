//go:build darwin

package darwin

import "testing"

// The reopen event itself needs LaunchServices and a running app; this pins
// the Go half the delegate calls into.
func TestSystrayOnReopen_CallsHandler(t *testing.T) {
	t.Cleanup(ResetForTesting)

	called := false

	SetReopenHandler(func() { called = true })
	systray_on_reopen()

	if !called {
		t.Error("systray_on_reopen did not call the handler set by SetReopenHandler")
	}
}

//go:build integration && darwin

package darwin_test

import (
	"testing"
	"time"

	"github.com/y3owk1n/neru/internal/adapter/platform/darwin"
)

// An accessibility walk of our own windows goes through OnMainThread from a
// scan goroutine, and may reach it again from code already on the main thread.
func TestOnMainThread_RunsOnTheMainThreadAndInlineWhenAlreadyThere(t *testing.T) {
	var onMain, nestedOnMain bool

	done := make(chan struct{})

	go func() {
		defer close(done)

		darwin.OnMainThread(func() {
			onMain = darwin.IsMainThread()
			// Inline on the main thread; a dispatch_sync here would deadlock.
			darwin.OnMainThread(func() { nestedOnMain = darwin.IsMainThread() })
		})
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("OnMainThread did not return")
	}

	if darwin.IsMainThread() {
		t.Fatal("the test itself runs on the main thread, so it proves nothing")
	}

	if !onMain || !nestedOnMain {
		t.Fatalf("ran on main thread: outer=%v nested=%v", onMain, nestedOnMain)
	}
}

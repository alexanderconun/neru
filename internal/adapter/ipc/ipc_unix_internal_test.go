//go:build !windows

package ipc

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"go.uber.org/zap"
)

// A command is bounded: the daemon refuses one that would make it buffer
// without limit, and says so rather than reporting truncated JSON.
func TestServer_HandleConnection_RefusesAnOversizedCommand(t *testing.T) {
	t.Parallel()

	accepted, dialed := connectedUnixPair(t)

	server := &Server{
		logger: zap.NewNop(),
		handler: func(_ context.Context, _ Command) Response {
			t.Error("handler ran for a command that should have been refused")

			return Response{Success: true, Code: CodeOK}
		},
	}

	server.wg.Add(1)

	go server.handleConnection(accepted)

	oversized, marshalErr := json.Marshal(Command{
		Action: "run",
		Args:   []string{strings.Repeat("x", maxCommandBytes)},
	})
	if marshalErr != nil {
		t.Fatalf("Marshal() error = %v", marshalErr)
	}

	// The daemon stops reading at the limit, so the tail of this write has
	// nowhere to go and its error says nothing about whether the refusal
	// worked. The deadline is only here so it cannot wait forever to find out.
	writeDeadlineErr := dialed.SetWriteDeadline(time.Now().Add(5 * time.Second))
	if writeDeadlineErr != nil {
		t.Fatalf("SetWriteDeadline() error = %v", writeDeadlineErr)
	}

	_, _ = dialed.Write(oversized)

	readDeadlineErr := dialed.SetReadDeadline(time.Now().Add(5 * time.Second))
	if readDeadlineErr != nil {
		t.Fatalf("SetReadDeadline() error = %v", readDeadlineErr)
	}

	var response Response

	decodeErr := json.NewDecoder(dialed).Decode(&response)
	if decodeErr != nil {
		t.Fatalf("decoding the refusal: %v", decodeErr)
	}

	if response.Success {
		t.Fatal("the daemon accepted a command past the size limit")
	}

	if response.Code != CodeInvalidInput {
		t.Errorf("response code = %s, want %s", response.Code, CodeInvalidInput)
	}

	if !strings.Contains(response.Message, "limit") {
		t.Errorf("response message = %q, want it to name the limit", response.Message)
	}

	server.wg.Wait()
}

// A command comfortably inside the limit is unaffected by the cap.
func TestServer_HandleConnection_AcceptsACommandInsideTheLimit(t *testing.T) {
	t.Parallel()

	accepted, dialed := connectedUnixPair(t)

	server := &Server{
		logger: zap.NewNop(),
		handler: func(_ context.Context, cmd Command) Response {
			return Response{Success: true, Message: cmd.Action, Code: CodeOK}
		},
	}

	server.wg.Add(1)

	go server.handleConnection(accepted)

	deadlineErr := dialed.SetDeadline(time.Now().Add(5 * time.Second))
	if deadlineErr != nil {
		t.Fatalf("SetDeadline() error = %v", deadlineErr)
	}

	encodeErr := json.NewEncoder(dialed).Encode(Command{Action: "status", Version: BuildVersion()})
	if encodeErr != nil {
		t.Fatalf("Encode() error = %v", encodeErr)
	}

	var response Response

	decodeErr := json.NewDecoder(dialed).Decode(&response)
	if decodeErr != nil {
		t.Fatalf("Decode() error = %v", decodeErr)
	}

	if !response.Success || response.Message != "status" {
		t.Fatalf("response = %+v, want the handler's own answer", response)
	}

	server.wg.Wait()
}

// While the daemon waits on the startup Accessibility alert, a client of the
// same build gets the denial for every command — ping included — through the
// real handshake rather than a version mismatch, and a launch probing with
// IsServerRunning still finds the daemon instead of starting another.
func TestWaitingForAccessibility_RefusesEveryCommandThroughTheHandshake(t *testing.T) {
	isolateEndpoint(t)

	server, serverErr := NewServer(WaitingForAccessibility, nil)
	if serverErr != nil {
		t.Fatalf("NewServer() error = %v", serverErr)
	}

	server.Start()
	t.Cleanup(func() { _ = server.Stop() })

	if !IsServerRunning() {
		t.Fatal("IsServerRunning() = false, want the waiting daemon to count as running")
	}

	for _, action := range []string{"ping", "status", "config", "health", "hints", "watch"} {
		response, sendErr := NewClient().Send(Command{Action: action})
		if sendErr != nil {
			t.Fatalf("Send(%s) error = %v", action, sendErr)
		}

		if response.Success || response.Code != CodeAccessibilityDenied ||
			response.Version != BuildVersion() {
			t.Errorf("Send(%s) = %+v, want a versioned %s refusal", action, response, CodeAccessibilityDenied)
		}
	}
}

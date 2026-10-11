package settingsui

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/y3owk1n/neru/internal/adapter/ipc"
	"github.com/y3owk1n/neru/internal/buildinfo"
	"github.com/y3owk1n/neru/internal/derrors"
)

func reply(t *testing.T, request string) ipc.Response {
	t.Helper()

	var response ipc.Response

	err := json.Unmarshal(command(t.Context(), []byte(request)), &response)
	if err != nil {
		t.Fatalf("reply to %s is not JSON: %v", request, err)
	}

	return response
}

func TestCommand(t *testing.T) {
	deps.Store(nil)

	if got := reply(t, `{"action":"status"}`); got.Success || got.Code != ipc.CodeActionFailed {
		t.Fatalf("before Start: %+v, want a refusal saying the daemon is still starting", got)
	}

	var forwarded ipc.Command

	Start(Deps{
		Commands: func(_ context.Context, cmd ipc.Command) ipc.Response {
			forwarded = cmd

			return ipc.Response{Success: true, Code: ipc.CodeOK}
		},
		LoginItem: func(op string) (bool, error) {
			if op == "boom" {
				return false, derrors.New(derrors.CodeActionFailed, "launchctl failed")
			}

			return op == "install", nil
		},
	})

	dir := t.TempDir()
	valid := filepath.Join(dir, "valid.toml")
	invalid := filepath.Join(dir, "invalid.toml")

	for path, text := range map[string]string{
		valid:   "[hints]\nhint_characters = \"asdf\"\n",
		invalid: "[hints]\nhint_characters = \"zz\"\n",
	} {
		err := os.WriteFile(path, []byte(text), 0o600)
		if err != nil {
			t.Fatal(err)
		}
	}

	request := func(action string, args ...string) string {
		data, err := json.Marshal(ipc.Command{Action: action, Args: args})
		if err != nil {
			t.Fatal(err)
		}

		return string(data)
	}

	tests := []struct {
		name, request, code, forwarded string
		data                           any
	}{
		{
			"a daemon action goes to the controller with its args",
			request("config-set", "a", "b"), ipc.CodeOK, "config-set", nil,
		},
		{"version is this build's", request("version"), ipc.CodeOK, "", buildinfo.Version},
		{"a valid config file passes", request("validate-config", valid), ipc.CodeOK, "", nil},
		{
			"an invalid config file is refused",
			request("validate-config", invalid), ipc.CodeActionFailed, "", nil,
		},
		{
			"validate-config takes one path",
			request("validate-config"), ipc.CodeInvalidInput, "", nil,
		},
		{
			"the login item reports whether it is installed",
			request("login-item", "install"), ipc.CodeOK, "", true,
		},
		{
			"a login item failure is reported",
			request("login-item", "boom"), ipc.CodeActionFailed, "", nil,
		},
		{"a malformed request is refused", `{"action":`, ipc.CodeInvalidInput, "", nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			forwarded = ipc.Command{}

			got := reply(t, tt.request)
			if got.Code != tt.code || got.Data != tt.data || forwarded.Action != tt.forwarded {
				t.Fatalf("got %+v forwarded %q, want code %s data %v forwarded %q",
					got, forwarded.Action, tt.code, tt.data, tt.forwarded)
			}

			if tt.forwarded != "" && len(forwarded.Args) != 2 {
				t.Fatalf("forwarded args %v, want both", forwarded.Args)
			}
		})
	}
}

func TestWatch(t *testing.T) {
	Start(Deps{Watch: func(ctx context.Context, _ ipc.Command, emit func(any) error) error {
		err := emit(map[string]string{"event": "snapshot"})
		if err != nil {
			return err
		}

		<-ctx.Done()

		return nil
	}})

	lines := make(chan string, 1)
	done := make(chan struct{})
	stop := watch(func(line []byte) { lines <- string(line) }, func() { close(done) })

	if got := <-lines; got != `{"event":"snapshot"}` {
		t.Errorf("first line %s, want the snapshot", got)
	}

	stop()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("stop did not end the stream")
	}
}

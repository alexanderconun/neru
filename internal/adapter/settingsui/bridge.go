// Package settingsui hosts the Settings, Tutorial and Training windows
// (macos/NeruSettings) inside the daemon. The windows reach the daemon through
// the command handler the IPC socket serves, called in-process: no socket and
// no spawned CLI, and the same gate, parsers and errors as both. Only the app
// build (darwin, cgo, -tags homekey_ui) links the Swift code; in any other
// build Open answers CodeNotSupported and callers fall back to the config file.
package settingsui

import (
	"context"
	"encoding/json"
	"sync/atomic"

	"github.com/y3owk1n/neru/internal/adapter/ipc"
	"github.com/y3owk1n/neru/internal/buildinfo"
	"github.com/y3owk1n/neru/internal/config"
	"github.com/y3owk1n/neru/internal/config/loader"
	"github.com/y3owk1n/neru/internal/derrors"
)

// Deps is what the windows may ask of the daemon. The composition root fills it.
type Deps struct {
	// Commands answers a request as the IPC socket does: the IPC controller's
	// HandleCommand, which also refuses modes while Neru is stopped.
	Commands ipc.CommandHandler
	// Watch streams events as `neru watch` does: the controller's HandleWatch.
	Watch ipc.StreamHandler
	// LoginItem runs `neru services status|install|uninstall` in this process
	// and reports whether Neru starts at login afterwards.
	LoginItem func(op string) (bool, error)
}

// The actions the bridge answers itself: what the CLI works out without the
// daemon. Every other action goes to Deps.Commands.
const (
	actionVersion        = "version"
	actionValidateConfig = "validate-config"
	actionLoginItem      = "login-item"
)

// deps is global because C calls in with no instance to hang it on.
var deps atomic.Pointer[Deps]

// Start hands the bridge the daemon. Until then every request is refused, so
// a window opened early says so rather than hanging.
func Start(daemon Deps) { deps.Store(&daemon) }

// command answers one JSON request ({"action":…,"args":[…]},
// docs/reference/ipc.md) with the JSON response the socket would send. It
// never logs the request: config-set carries the user's values.
func command(ctx context.Context, request []byte) []byte {
	var cmd ipc.Command

	response := ipc.Response{Message: "bad request", Code: ipc.CodeInvalidInput}

	err := json.Unmarshal(request, &cmd)
	if err == nil {
		response = answer(ctx, cmd)
	}

	data, err := json.Marshal(response)
	if err != nil {
		// Data the daemon cannot encode is a bug; say so in a reply that encodes.
		return []byte(`{"success":false,"message":"unencodable reply","code":"ERR_ACTION_FAILED"}`)
	}

	return data
}

func answer(ctx context.Context, cmd ipc.Command) ipc.Response {
	daemon := deps.Load()
	if daemon == nil {
		return ipc.Response{Message: "the daemon is still starting", Code: ipc.CodeActionFailed}
	}

	switch cmd.Action {
	case actionVersion:
		return ipc.Response{Success: true, Code: ipc.CodeOK, Data: buildinfo.Version}
	case actionValidateConfig:
		if len(cmd.Args) != 1 {
			return ipc.Response{Message: "validate-config takes a path", Code: ipc.CodeInvalidInput}
		}

		// As `neru config validate --config` does on macOS (cli/config_loader.go).
		result := loader.NewService(config.DefaultConfig(), "", nil, nil).
			LoadWithValidation(cmd.Args[0])
		if result.ValidationError != nil {
			return failure(result.ValidationError)
		}

		return ipc.Response{Success: true, Code: ipc.CodeOK}
	case actionLoginItem:
		if daemon.LoginItem == nil || len(cmd.Args) != 1 {
			return ipc.Response{
				Message: "login-item takes status, install or uninstall",
				Code:    ipc.CodeInvalidInput,
			}
		}

		installed, err := daemon.LoginItem(cmd.Args[0])
		if err != nil {
			return failure(err)
		}

		return ipc.Response{Success: true, Code: ipc.CodeOK, Data: installed}
	}

	return daemon.Commands(ctx, cmd)
}

// watch streams `neru watch` lines to line, on one goroutine, until the
// returned stop is called or the stream ends, then calls done once. line must
// not keep its argument.
func watch(line func([]byte), done func()) context.CancelFunc {
	ctx, stop := context.WithCancel(context.Background())

	go func() {
		defer done()

		daemon := deps.Load()
		if daemon == nil {
			return
		}

		_ = daemon.Watch(ctx, ipc.Command{Action: "watch"}, func(value any) error {
			data, err := json.Marshal(value)
			if err == nil {
				line(data)
			}

			return err
		})
	}()

	return stop
}

func failure(err error) ipc.Response {
	code := ipc.CodeActionFailed
	if derrors.IsNotSupported(err) {
		code = ipc.CodeNotSupported
	}

	return ipc.Response{Message: err.Error(), Code: code}
}

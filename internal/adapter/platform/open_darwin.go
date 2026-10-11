//go:build darwin

package platform

import (
	"context"
	"os/exec"

	"github.com/y3owk1n/neru/internal/derrors"
)

// OpenExternal opens a URL or file path with the macOS default handler.
// It does not validate the target or wait for the launched app.
func OpenExternal(ctx context.Context, target string) error {
	err := exec.CommandContext(ctx, "/usr/bin/open", target).Run()
	if err != nil {
		return derrors.Wrap(err, derrors.CodeExecFailed, "failed to launch the system open handler")
	}

	return nil
}

// OpenWith opens a URL or file path with the app bundle at appPath rather than
// the one LaunchServices would pick: stale copies of an app can claim the same
// URL scheme. It does not wait for the launched app.
func OpenWith(ctx context.Context, appPath, target string) error {
	err := exec.CommandContext(ctx, "/usr/bin/open", "-a", appPath, target).Run()
	if err != nil {
		return derrors.Wrap(err, derrors.CodeExecFailed, "failed to launch the system open handler")
	}

	return nil
}

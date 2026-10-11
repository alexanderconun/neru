//go:build linux

package platform

import (
	"context"
	"os/exec"

	"github.com/y3owk1n/neru/internal/derrors"
)

// OpenExternal opens a URL or file path with the Linux desktop's default
// handler. It does not validate the target or wait for the launched app.
func OpenExternal(ctx context.Context, target string) error {
	err := exec.CommandContext(ctx, "xdg-open", target).Start()
	if err != nil {
		return derrors.Wrap(err, derrors.CodeExecFailed, "failed to launch the system open handler")
	}

	return nil
}

// OpenWith is macOS-only: it opens a target with one app bundle, which only
// the settings helper needs.
func OpenWith(_ context.Context, _, _ string) error {
	return derrors.New(
		derrors.CodeNotSupported,
		"opening a target with a chosen app is not supported",
	)
}

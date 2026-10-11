//go:build !darwin && !linux && !windows

package platform

import (
	"context"

	"github.com/y3owk1n/neru/internal/derrors"
)

// OpenExternal is the non-target fallback: no handler is known here.
func OpenExternal(_ context.Context, _ string) error {
	return derrors.New(derrors.CodeNotSupported, "opening external targets is not supported")
}

// OpenWith is macOS-only: it opens a target with one app bundle, which only
// the settings helper needs.
func OpenWith(_ context.Context, _, _ string) error {
	return derrors.New(
		derrors.CodeNotSupported,
		"opening a target with a chosen app is not supported",
	)
}

//go:build !darwin || !homekey_ui

package settingsui

import "github.com/y3owk1n/neru/internal/derrors"

// Open shows a window. This build has none: only the app build
// (scripts/build-app.sh, -tags homekey_ui) links them.
func Open(string) error {
	return derrors.New(derrors.CodeNotSupported, "this build has no settings windows")
}

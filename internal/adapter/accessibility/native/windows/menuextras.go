//go:build windows

package windows

import (
	"context"

	"go.uber.org/zap"

	"github.com/y3owk1n/neru/internal/config"
	"github.com/y3owk1n/neru/internal/derrors"
)

// MenuExtrasClickableElements returns CodeNotSupported, since menu bar icons
// owned by every running app are a macOS menu bar concept.
func MenuExtrasClickableElements(
	_ context.Context,
	_ *zap.Logger,
	_ config.Provider,
) ([]*TreeNode, error) {
	return nil, derrors.New(derrors.CodeNotSupported, "menu bar icons are macOS-only")
}

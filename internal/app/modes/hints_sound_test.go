package modes

import (
	"context"
	"slices"
	"testing"

	"go.uber.org/zap"

	"github.com/y3owk1n/neru/internal/app/components"
	hintscomponent "github.com/y3owk1n/neru/internal/app/components/hints"
	"github.com/y3owk1n/neru/internal/app/components/scroll"
	"github.com/y3owk1n/neru/internal/app/services"
	configpkg "github.com/y3owk1n/neru/internal/config"
	"github.com/y3owk1n/neru/internal/derrors"
	"github.com/y3owk1n/neru/internal/domain"
	"github.com/y3owk1n/neru/internal/domain/element"
	"github.com/y3owk1n/neru/internal/domain/modecmd"
	"github.com/y3owk1n/neru/internal/domain/state"
	"github.com/y3owk1n/neru/internal/ports"
	portmocks "github.com/y3owk1n/neru/internal/ports/mocks"
)

// soundSystemPort records the sounds the handler asks the platform for.
type soundSystemPort struct {
	portmocks.MockSystemPort

	played []ports.Sound
}

func (s *soundSystemPort) PlaySound(kind ports.Sound, _ float64) {
	s.played = append(s.played, kind)
}

// An activation that ends with nothing to label is otherwise silent: the
// labels never appear and the user cannot tell a miss from a slow scan.
func TestActivateHints_WarnsWhenNothingToLabel(t *testing.T) {
	walkFailed := derrors.New(derrors.CodeAccessibilityFailed, "walk failed")

	tests := []struct {
		name    string
		enabled bool
		walkErr error
		refresh bool
		want    []ports.Sound
	}{
		{"no hints warns", true, nil, false, []ports.Sound{ports.SoundWarning}},
		{"a generation error warns", true, walkFailed, false, []ports.Sound{ports.SoundWarning}},
		{"disabled stays silent", false, nil, false, nil},
		// A chained click whose click closed the last window ends the chain; that is no failure.
		{"a refresh with nothing left stays silent", true, nil, true, nil},
		{"a refresh whose walk fails stays silent", true, walkFailed, true, nil},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			accessibility := &portmocks.MockAccessibilityPort{
				ClickableElementsFunc: func(
					context.Context,
					ports.ElementFilter,
				) ([]*element.Element, error) {
					return nil, testCase.walkErr
				},
			}
			system := &soundSystemPort{}
			actionService := services.NewActionService(
				accessibility, &portmocks.MockOverlayPort{}, system, zap.NewNop(),
			)
			actionService.UpdateSoundConfig(
				configpkg.SoundConfig{Enabled: testCase.enabled, Volume: 50},
			)

			appState := state.NewAppState()
			if testCase.refresh {
				appState.SetMode(domain.ModeHints)
			}

			handler := newHandlerWithState(handlerState{
				ctx:           context.Background(),
				config:        hintsEnabledConfig(),
				appState:      appState,
				cursorState:   state.NewCursorState(),
				modifierState: state.NewModifierState(),
				system:        system,
				actionService: actionService,
				hintService: services.NewHintService(
					accessibility, &portmocks.MockOverlayPort{}, system,
					nil, configpkg.HintsConfig{}, zap.NewNop(), nil,
				),
				hints:  &components.HintsComponent{Context: &hintscomponent.Context{}},
				scroll: &components.ScrollComponent{Context: &scroll.Context{}},
			})

			handler.ActivateMode(modecmd.Activation{Mode: domain.ModeHints})

			if !slices.Equal(system.played, testCase.want) {
				t.Fatalf("played %v, want %v", system.played, testCase.want)
			}

			if mode := appState.CurrentMode(); mode != domain.ModeIdle {
				t.Fatalf("mode = %v after finding nothing to label, want idle", mode)
			}
		})
	}
}

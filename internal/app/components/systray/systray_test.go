package systray_test

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"
	"time"

	"go.uber.org/zap/zaptest"

	"github.com/y3owk1n/neru/internal/app/components/systray"
	"github.com/y3owk1n/neru/internal/buildinfo"
	"github.com/y3owk1n/neru/internal/domain"
	portmocks "github.com/y3owk1n/neru/internal/ports/mocks"
)

// mockApp implements AppInterface for testing.
type mockApp struct {
	hintsEnabled         bool
	gridEnabled          bool
	recursiveGridEnabled bool
	isEnabled            bool
	hiddenForScreenShare bool
	scrollInverted       bool
	activatedMode        domain.Mode
	configPath           string
	reloadCalled         bool
	enabledCallback      func(bool)
}

func (m *mockApp) HintsEnabled() bool         { return m.hintsEnabled }
func (m *mockApp) GridEnabled() bool          { return m.gridEnabled }
func (m *mockApp) RecursiveGridEnabled() bool { return m.recursiveGridEnabled }
func (m *mockApp) BisectEnabled() bool        { return true }
func (m *mockApp) IsEnabled() bool            { return m.isEnabled }
func (m *mockApp) SetEnabled(enabled bool) {
	m.isEnabled = enabled
	if m.enabledCallback != nil {
		m.enabledCallback(enabled)
	}
}
func (m *mockApp) ActivateMode(mode domain.Mode) { m.activatedMode = mode }
func (m *mockApp) GetConfigPath() string         { return m.configPath }
func (m *mockApp) ReloadConfig(ctx context.Context, configPath string) error {
	m.reloadCalled = true

	return nil
}

func (m *mockApp) OnEnabledStateChanged(callback func(bool)) uint64 {
	m.enabledCallback = callback

	return 0
}
func (m *mockApp) OffEnabledStateChanged(id uint64) {}
func (m *mockApp) ToggleEnabled() {
	m.SetEnabled(!m.isEnabled)
}
func (m *mockApp) IsOverlayHiddenForScreenShare() bool      { return m.hiddenForScreenShare }
func (m *mockApp) SetOverlayHiddenForScreenShare(hide bool) { m.hiddenForScreenShare = hide }
func (m *mockApp) ToggleOverlayHiddenForScreenShare() bool {
	newState := !m.hiddenForScreenShare
	m.hiddenForScreenShare = newState

	return newState
}

func (m *mockApp) OnScreenShareStateChanged(callback func(bool)) uint64 {
	return 0
}
func (m *mockApp) OffScreenShareStateChanged(id uint64) {}
func (m *mockApp) IsScrollInverted() bool               { return m.scrollInverted }
func (m *mockApp) SetScrollInverted(inverted bool)      { m.scrollInverted = inverted }
func (m *mockApp) ToggleScrollInvert() bool {
	newState := !m.scrollInverted
	m.scrollInverted = newState

	return newState
}
func (m *mockApp) OnScrollInvertStateChanged(callback func(bool)) uint64 { return 0 }
func (m *mockApp) OffScrollInvertStateChanged(id uint64)                 {}
func (m *mockApp) Quit()                                                 {}

func TestNewComponent(t *testing.T) {
	logger := zaptest.NewLogger(t)
	mockApp := &mockApp{}

	component := systray.NewComponent(mockApp, &portmocks.MockSystrayPort{}, nil, logger)

	if component == nil {
		t.Fatal("NewComponent returned nil")
	}
}

func TestComponent_OnReady(t *testing.T) {
	logger := zaptest.NewLogger(t)
	mockApp := &mockApp{
		hintsEnabled: true,
		gridEnabled:  true,
	}

	tray := &portmocks.MockSystrayPort{}
	component := systray.NewComponent(mockApp, tray, nil, logger)

	component.OnReady()

	// Before ports.SystrayPort existed this test could only assert "did not
	// panic", because the menu was built against a process-global tray. The
	// mock lets it assert what the user actually sees.
	if want := buildinfo.DisplayName + " - Paused"; tray.Tooltip() != want {
		t.Errorf("OnReady() tooltip = %q, want %q", tray.Tooltip(), want)
	}

	items := tray.Items()
	if len(items) == 0 {
		t.Fatal("OnReady() created no menu items")
	}

	// Spot-check entries the menu must always carry, whatever else changes.
	for _, want := range []string{
		"Help", "Config", "Activate Modes",
		"Pause " + buildinfo.DisplayName, "Resume " + buildinfo.DisplayName,
	} {
		if tray.FindItem(want) == nil {
			var titles []string
			for _, item := range items {
				if title := item.Title(); title != "" {
					titles = append(titles, title)
				}
			}

			t.Errorf("OnReady() built no %q item; got %v", want, titles)
		}
	}

	// Tutorial and Training follow Settings, and like it exist only on macOS,
	// the one platform with the windows.
	var titles []string
	for _, item := range items {
		titles = append(titles, item.Title())
	}

	at := slices.Index(titles, "Settings…")
	want := []string{"Settings…", "Tutorial…", "Training…"}
	if at < 0 || !slices.Equal(titles[at:min(at+len(want), len(titles))], want) {
		t.Errorf("OnReady() menu = %v, want Tutorial… and Training… right after Settings…", titles)
	}

	hidden := runtime.GOOS != "darwin"
	for _, title := range want {
		if item := tray.FindItem(title); item != nil && item.Hidden() != hidden {
			t.Errorf("%q hidden = %v on %s", title, item.Hidden(), runtime.GOOS)
		}
	}
}

// The menu opens each window through the opener the composition root injects.
func TestComponent_OnReady_MenuOpensTheWindows(t *testing.T) {
	tray := &portmocks.MockSystrayPort{}
	component := systray.NewComponent(&mockApp{}, tray, nil, zaptest.NewLogger(t))
	opened := make(chan string, 1)
	component.OpenWindow = func(window string) error {
		opened <- window

		return nil
	}

	component.OnReady()
	t.Cleanup(component.OnExit)

	for title, window := range map[string]string{
		"Settings…": systray.SettingsWindow,
		"Tutorial…": systray.TutorialWindow,
		"Training…": systray.TrainingWindow,
	} {
		tray.FindItem(title).Click()

		select {
		case got := <-opened:
			if got != window {
				t.Errorf("%q opened %q, want %q", title, got, window)
			}
		case <-time.After(time.Second):
			t.Fatalf("%q opened nothing", title)
		}
	}
}

func TestOpenTutorialOnce(t *testing.T) {
	logger := zaptest.NewLogger(t)
	dataDir := filepath.Join(t.TempDir(), "neru")
	opened := 0
	open := func(ok bool) func() bool {
		return func() bool {
			opened++

			return ok
		}
	}

	// Not opened (a build without the windows): nothing is marked, so the
	// next launch tries again.
	systray.OpenTutorialOnce(dataDir, open(false), logger)
	systray.OpenTutorialOnce(dataDir, open(false), logger)
	systray.OpenTutorialOnce(dataDir, open(true), logger)
	systray.OpenTutorialOnce(dataDir, open(true), logger)

	if opened != 3 {
		t.Errorf("tutorial opened %d times, want 3: twice not opened, once for good", opened)
	}

	_, err := os.Stat(filepath.Join(dataDir, "tutorial-shown"))
	if err != nil {
		t.Errorf("tutorial not marked shown: %v", err)
	}
}

// trayIconAtReady builds the menu for one enabled state and returns the icon
// the tray was left showing.
func trayIconAtReady(t *testing.T, enabled bool) []byte {
	t.Helper()

	tray := &portmocks.MockSystrayPort{}
	component := systray.NewComponent(
		&mockApp{isEnabled: enabled},
		tray,
		nil,
		zaptest.NewLogger(t),
	)

	component.OnReady()

	t.Cleanup(component.OnExit)

	icon, _ := tray.Icon()

	return icon
}

// TestComponent_OnReady_ShowsADistinctIconWhilePaused pins the one place a
// user can see that Neru is paused without pressing a key. Every platform owes
// two tray icons — macOS a second template glyph, the tray hosts that render
// bytes literally a greyed tile — and showing one icon for both states makes the
// state invisible.
func TestComponent_OnReady_ShowsADistinctIconWhilePaused(t *testing.T) {
	running := trayIconAtReady(t, true)
	paused := trayIconAtReady(t, false)

	if len(running) == 0 {
		t.Fatal("the tray was left with no icon while running")
	}

	if len(paused) == 0 {
		t.Fatal("the tray was left with no icon while paused")
	}

	if bytes.Equal(running, paused) {
		t.Error("the tray shows the same icon running and paused; the paused state is invisible")
	}
}

func TestComponent_OnExit(t *testing.T) {
	logger := zaptest.NewLogger(t)
	mockApp := &mockApp{}

	tray := &portmocks.MockSystrayPort{}
	component := systray.NewComponent(mockApp, tray, nil, logger)

	component.OnReady()

	// Shutdown runs OnExit and Close on paths that can overlap, so both must
	// tolerate being called more than once. A panic or a double-close here
	// fails the test.
	component.OnExit()
	component.OnExit()
	component.Close()

	if tray.FindItem("Help") == nil {
		t.Error("OnExit() should not tear down the menu the tray still owns")
	}
}

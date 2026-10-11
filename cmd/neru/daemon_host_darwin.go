//go:build darwin

package main

import (
	"go.uber.org/zap"

	"github.com/y3owk1n/neru/internal/adapter/platform"
	"github.com/y3owk1n/neru/internal/adapter/settingsui"
	"github.com/y3owk1n/neru/internal/adapter/systray"
	"github.com/y3owk1n/neru/internal/app"
	traycomponent "github.com/y3owk1n/neru/internal/app/components/systray"
	"github.com/y3owk1n/neru/internal/cli"
)

type darwinDaemonHost struct{}

func newDaemonHost() daemonHost {
	return darwinDaemonHost{}
}

func (darwinDaemonHost) Run(application *app.App) error {
	// Ensure cleanup runs even if the systray OnExit callback does not fire
	// (e.g. Cocoa event-loop crash). Cleanup is idempotent (sync.Once), so
	// the duplicate call from OnExit is harmless.
	defer application.Cleanup()

	runDone := make(chan error, 1)

	go func() {
		err := application.Run()
		if err != nil {
			systray.Quit()
		}

		runDone <- err
	}()

	// The settings windows reach the daemon in-process (app build only).
	settingsui.Start(settingsui.Deps{
		Commands:  application.HandleCommand,
		Watch:     application.HandleWatch,
		LoginItem: cli.LoginItem,
	})

	// The first run with Accessibility granted (main waited for it) opens the
	// tutorial once. Off the main thread: it touches the disk.
	go openTutorialOnce(application)

	systrayComponent := application.GetSystrayComponent()
	if systrayComponent != nil {
		// Opening the app again while it runs shows the settings window.
		systray.SetReopenHandler(systrayComponent.OpenSettings)
		systray.Run(systrayComponent.OnReady, systrayComponent.OnExit)
	} else {
		// With the menu bar icon hidden, opening the app again is the only way
		// back to the settings window. A build without it has nothing to show.
		systray.SetReopenHandler(func() { _ = settingsui.Open(traycomponent.SettingsWindow) })
		systray.RunHeadless(func() {}, func() {})
	}

	// Unblock waitForShutdown so the goroutine can return.
	// Stop is idempotent (protected by sync.Once), so this is safe even if
	// the app already stopped itself.
	application.Stop()

	return <-runDone
}

// openTutorialOnce opens the tutorial if the daemon has never opened it,
// keeping the marker in the user data directory.
func openTutorialOnce(application *app.App) {
	logger := application.Logger()

	system, err := platform.NewSystemPort()
	if err != nil {
		logger.Warn("Could not check whether the tutorial was shown", zap.Error(err))

		return
	}

	dataDir, err := system.UserDataDir()
	if err != nil {
		logger.Warn("Could not check whether the tutorial was shown", zap.Error(err))

		return
	}

	traycomponent.OpenTutorialOnce(dataDir, func() bool {
		return settingsui.Open(traycomponent.TutorialWindow) == nil
	}, logger)
}

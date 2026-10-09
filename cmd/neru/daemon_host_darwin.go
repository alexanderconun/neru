//go:build darwin

package main

import (
	"context"

	"github.com/y3owk1n/neru/internal/adapter/systray"
	"github.com/y3owk1n/neru/internal/app"
	traycomponent "github.com/y3owk1n/neru/internal/app/components/systray"
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

	systrayComponent := application.GetSystrayComponent()
	if systrayComponent != nil {
		// Opening the app again while it runs shows the settings window.
		systray.SetReopenHandler(systrayComponent.OpenSettings)
		systray.Run(systrayComponent.OnReady, systrayComponent.OnExit)
	} else {
		// With the menu bar icon hidden, opening the app again is the only way
		// back to the settings window. Off the main thread: opening blocks.
		systray.SetReopenHandler(func() {
			go traycomponent.OpenSettingsApp(context.Background(), application.Logger())
		})
		systray.RunHeadless(func() {}, func() {})
	}

	// Unblock waitForShutdown so the goroutine can return.
	// Stop is idempotent (protected by sync.Once), so this is safe even if
	// the app already stopped itself.
	application.Stop()

	return <-runDone
}

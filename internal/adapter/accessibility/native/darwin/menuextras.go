//go:build darwin

package darwin

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#include "../../../platform/darwin/accessibility.h"
*/
import "C"

import (
	"context"
	"sync"

	"go.uber.org/zap"

	"github.com/y3owk1n/neru/internal/config"
	"github.com/y3owk1n/neru/internal/domain/element"
)

const (
	// maxRunningApplications bounds the PID buffer; a desktop runs a few hundred.
	maxRunningApplications = 1024
	// menuExtrasTreeDepth reaches AXMenuBarItem from an app's AXExtrasMenuBar.
	menuExtrasTreeDepth = 2
	// menuExtrasWorkers bounds the apps queried at once; each query holds an
	// OS thread inside cgo.
	menuExtrasWorkers = 16
)

// RunningApplicationPIDs returns the PIDs of all running applications.
func RunningApplicationPIDs() []int {
	buf := make([]C.int, maxRunningApplications)
	count := int(C.NeruGetRunningApplicationPIDs(&buf[0], C.int(len(buf))))

	pids := make([]int, count)
	for i := range count {
		pids[i] = int(buf[i])
	}

	return pids
}

// ExtrasMenuBar returns the application's menu bar icons (status items), or
// nil when it has none.
func (e *Element) ExtrasMenuBar() *Element {
	if e.ref == nil {
		return nil
	}

	ref := C.NeruGetExtrasMenuBar(e.ref)
	if ref == nil {
		return nil
	}

	return newElement(ref)
}

// MenuExtrasClickableElements returns the menu bar icons of every running
// application, the way the menu bar draws them to the right of the app menus.
// Each app answers for its own icons, so they are asked in parallel, each
// bounded by a short messaging timeout so a hung app costs at most that.
func MenuExtrasClickableElements(
	ctx context.Context,
	logger *zap.Logger,
	configProvider config.Provider,
) ([]*TreeNode, error) {
	allowedRoles := map[string]struct{}{string(element.RoleMenuBarItem): {}}

	var (
		mutex   sync.Mutex
		group   sync.WaitGroup
		results []*TreeNode
	)

	pids := make(chan int)

	for range menuExtrasWorkers {
		group.Go(func() {
			for pid := range pids {
				nodes := menuExtrasOf(ctx, pid, allowedRoles, logger, configProvider)

				mutex.Lock()
				results = append(results, nodes...)
				mutex.Unlock()
			}
		})
	}

	for _, pid := range RunningApplicationPIDs() {
		pids <- pid
	}

	close(pids)
	group.Wait()

	logger.Debug("Included menu extras", zap.Int("count", len(results)))

	return results, nil
}

func menuExtrasOf(
	ctx context.Context,
	pid int,
	allowedRoles map[string]struct{},
	logger *zap.Logger,
	configProvider config.Provider,
) []*TreeNode {
	app := ApplicationByPID(pid)
	if app == nil {
		return nil
	}
	defer app.Release()

	extras := app.ExtrasMenuBar()
	if extras == nil {
		return nil
	}
	defer extras.Release()

	opts := DefaultTreeOptions(logger)
	opts.SetConfigProvider(configProvider)
	opts.SetMaxDepth(menuExtrasTreeDepth)

	tree, err := BuildTree(ctx, extras, opts)
	if err != nil || tree == nil {
		return nil
	}

	nodes := tree.FindClickableElements(allowedRoles, configProvider, false)
	ReleaseTreeExcept(tree, nodes)

	return nodes
}

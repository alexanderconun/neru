//go:build darwin

package cli

import (
	"encoding/xml"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestDaemonStderrPath_ResolvesUnderTheUserOwnLogDirectory pins where the login
// agent's standard error lands. launchd expands nothing it reads out of a
// plist, so a "~" or a "$HOME" written into one is a literal directory name,
// and the shared fallback a wrong answer used to reach is world-readable.
func TestDaemonStderrPath_ResolvesUnderTheUserOwnLogDirectory(t *testing.T) {
	home, homeErr := os.UserHomeDir()
	if homeErr != nil {
		t.Skipf("no home directory on this machine: %v", homeErr)
	}

	got, err := daemonStderrPath()
	if err != nil {
		t.Fatalf("daemonStderrPath() error = %v", err)
	}

	want := filepath.Join(home, "Library", "Logs", "neru", "daemon.err.log")
	if got != want {
		t.Errorf("daemonStderrPath() = %q, want %q", got, want)
	}
}

// TestRenderPlist_SendsOutputOnlyToThePathItIsGiven pins the plist the agent is
// installed from: the stderr redirect names the file it was handed, nothing
// names a shared directory, and standard output is left unredirected, since the
// rotated log file already holds every log line the console core writes there.
func TestRenderPlist_SendsOutputOnlyToThePathItIsGiven(t *testing.T) {
	const (
		binPath    = "/Users/tester/bin/neru"
		stderrPath = "/Users/tester/Library/Logs/neru/daemon.err.log"
	)

	plist := renderPlist(binPath, stderrPath)

	testCases := []struct {
		name    string
		needle  string
		present bool
	}{
		{name: "runs the resolved binary", needle: binPath, present: true},
		{
			name:    "redirects stderr to the given file",
			needle:  "<key>StandardErrorPath</key>\n    <string>" + stderrPath + "</string>",
			present: true,
		},
		{name: "leaves stdout unredirected", needle: "StandardOutPath", present: false},
		// A clean exit (menu Quit, "already running") stays down; a crash restarts.
		{
			name:    "restarts only after a failed exit",
			needle:  "<key>KeepAlive</key>\n    <dict>\n        <key>SuccessfulExit</key>\n        <false/>",
			present: true,
		},
		{name: "names no shared temp directory", needle: "/tmp", present: false},
		{name: "leaves no placeholder behind", needle: "NERU_", present: false},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			if strings.Contains(plist, testCase.needle) != testCase.present {
				t.Errorf(
					"rendered plist contains %q = %v, want %v:\n%s",
					testCase.needle,
					!testCase.present,
					testCase.present,
					plist,
				)
			}
		})
	}
}

// TestRenderPlist_EscapesPathsThatAreNotValidXML keeps a legal directory name
// from producing an illegal plist. Paths are arbitrary text — "A&B" is a
// perfectly good directory on macOS — and launchctl refuses to load a plist
// whose XML does not parse, after the file has already been written, so the
// next install refuses too rather than replacing it.
func TestRenderPlist_EscapesPathsThatAreNotValidXML(t *testing.T) {
	testCases := []struct {
		name       string
		binPath    string
		stderrPath string
		want       string
	}{
		{
			name:       "ampersand in the binary path",
			binPath:    "/Users/tester/A&B/neru",
			stderrPath: "/Users/tester/Library/Logs/neru/daemon.err.log",
			want:       "<string>/Users/tester/A&amp;B/neru</string>",
		},
		{
			name:       "angle brackets in the log path",
			binPath:    "/Users/tester/bin/neru",
			stderrPath: "/Users/tester/<logs>/daemon.err.log",
			want:       "<string>/Users/tester/&lt;logs&gt;/daemon.err.log</string>",
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			plist := renderPlist(testCase.binPath, testCase.stderrPath)

			if !strings.Contains(plist, testCase.want) {
				t.Errorf("rendered plist does not contain %q:\n%s", testCase.want, plist)
			}

			decodeErr := xml.Unmarshal([]byte(plist), new(any))
			if decodeErr != nil {
				t.Errorf("rendered plist is not well-formed XML: %v", decodeErr)
			}
		})
	}
}

var errNotLoaded = errors.New("not loaded")

// TestLoginItem_InstallAfterOffWhileTheJobIsStillLoaded pins turning launch at
// login back on after it was turned off while the job stayed loaded: off from
// inside the launchd job removes only the plist. A job still loaded from our
// own missing plist is ours; one loaded from anywhere else stays refused.
func TestLoginItem_InstallAfterOffWhileTheJobIsStillLoaded(t *testing.T) {
	const foreign = "/Library/LaunchAgents/" + serviceLabel + ".plist"

	testCases := []struct {
		name           string
		xpcService     string
		loadedFrom     string // "ours" for our plist path, "" for nothing loaded
		uninstallFirst bool
		wantOn         bool
		wantErr        error
		wantBootstrap  bool
	}{
		{
			name:           "this daemon is the job: off then on writes the plist back",
			xpcService:     serviceLabel,
			loadedFrom:     "ours",
			uninstallFirst: true,
			wantOn:         true,
		},
		{
			name:          "another instance boots our stale job out and installs",
			loadedFrom:    "ours",
			wantOn:        true,
			wantBootstrap: true,
		},
		{
			name:          "nothing loaded installs",
			wantOn:        true,
			wantBootstrap: true,
		},
		{
			name:       "a job loaded from elsewhere is refused",
			loadedFrom: foreign,
			wantErr:    errServiceAlreadyLoaded,
		},
		{
			name:       "even when this daemon is that job",
			xpcService: serviceLabel,
			loadedFrom: foreign,
			wantErr:    errServiceAlreadyLoaded,
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Setenv("HOME", t.TempDir())
			t.Setenv("XPC_SERVICE_NAME", testCase.xpcService)

			plistPath, err := expandPath(plistFile)
			if err != nil {
				t.Fatal(err)
			}

			loaded := testCase.loadedFrom
			if loaded == "ours" {
				loaded = plistPath

				_, err = writePlist()
				if err != nil {
					t.Fatal(err)
				}
			}

			bootstrapped := false
			original := launchctl

			t.Cleanup(func() { launchctl = original })

			launchctl = func(args ...string) ([]byte, error) {
				switch args[0] {
				case "list", "print":
					if loaded == "" {
						return nil, errNotLoaded
					}

					return []byte(
						"gui/501/" + serviceLabel + " = {\n\tpath = " + loaded + "\n}\n",
					), nil
				case "bootout":
					loaded = ""
				case "bootstrap":
					loaded, bootstrapped = args[2], true
				}

				return nil, nil
			}

			if testCase.uninstallFirst {
				on, uninstallErr := LoginItem("uninstall")
				if on || uninstallErr != nil || loaded != plistPath {
					t.Fatalf(
						"uninstall = %v, %v, loaded %q; want off, job kept",
						on,
						uninstallErr,
						loaded,
					)
				}
			} else if loaded == plistPath {
				_ = os.Remove(plistPath) // what an earlier uninstall left
			}

			on, err := LoginItem("install")
			if on != testCase.wantOn || !errors.Is(err, testCase.wantErr) {
				t.Errorf(
					"install = %v, %v; want %v, %v",
					on,
					err,
					testCase.wantOn,
					testCase.wantErr,
				)
			}

			if bootstrapped != testCase.wantBootstrap {
				t.Errorf("bootstrapped = %v, want %v", bootstrapped, testCase.wantBootstrap)
			}
		})
	}
}

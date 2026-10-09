package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"github.com/spf13/cobra"

	"github.com/y3owk1n/neru/internal/adapter/ipc"
)

// TestPrintDaemonRefusal pins the doctor row for a daemon that answers health
// without a report: the reason and code must reach the person, while a report —
// healthy or not — is left to the report printer.
func TestPrintDaemonRefusal(t *testing.T) {
	tests := []struct {
		name     string
		response ipc.Response
		want     string
	}{
		{
			name:     "a daemon waiting on Accessibility says so",
			response: ipc.WaitingForAccessibility(t.Context(), ipc.Command{Action: "health"}),
			want:     "waiting for Accessibility permission (code: ERR_ACCESSIBILITY_DENIED)",
		},
		{
			name: "an unhealthy report is not a refusal",
			response: ipc.Response{
				Code: ipc.CodeActionFailed,
				Data: map[string]any{"components": map[string]any{}},
			},
		},
		{
			name:     "a healthy reply is not a refusal",
			response: ipc.Response{Success: true, Code: ipc.CodeOK},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var out bytes.Buffer

			cmd := &cobra.Command{}
			cmd.SetOut(&out)

			err := printDaemonRefusal(cmd, test.response)
			printed := out.String()

			if test.want == "" {
				if err != nil || printed != "" {
					t.Fatalf("printDaemonRefusal() = %v, printed %q; want nothing", err, printed)
				}

				return
			}

			if !errors.Is(err, errDaemonRefused) || !strings.Contains(printed, test.want) {
				t.Fatalf("printDaemonRefusal() = %v, printed %q; want %q", err, printed, test.want)
			}
		})
	}
}

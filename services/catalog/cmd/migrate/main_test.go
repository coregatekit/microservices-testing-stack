package main

import (
	"strings"
	"testing"
)

func TestRun_RejectsBadInput(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		dsn     string
		wantErr string
	}{
		{name: "unknown command", args: []string{"down"}, dsn: "postgres://x", wantErr: "unknown command"},
		{name: "missing dsn with default command", args: nil, dsn: "", wantErr: "MIGRATOR_DATABASE_URL is not set"},
		{name: "missing dsn with status", args: []string{"status"}, dsn: "", wantErr: "MIGRATOR_DATABASE_URL is not set"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("MIGRATOR_DATABASE_URL", tc.dsn)

			err := run(t.Context(), tc.args)
			if err == nil {
				t.Fatalf("run(%q) = nil, want error containing %q", tc.args, tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("run(%q) error = %q, want it to contain %q", tc.args, err, tc.wantErr)
			}
		})
	}
}

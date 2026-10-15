package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/coregatekit/ticketlite/services/catalog/db"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := run(ctx); err != nil {
		slog.Error("migrate failed", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	cmd := "up"
	if len(os.Args) > 1 {
		// os.Args[0] is the program name
		// os.Args[1] is the command to run (e.g., "up", "down")
		cmd = os.Args[1]
	}

	// Validate the command before proceeding
	if cmd != "up" && cmd != "status" {
		return fmt.Errorf("unknown command: %q, want up or status", cmd)
	}

	// Get the database connection string from the environment variable
	dsn := os.Getenv("MIGRATOR_DATABASE_URL")
	if dsn == "" {
		return errors.New("MIGRATOR_DATABASE_URL is not set")
	}

	// Get the migrations filesystem from the embedded migrations
	fsys, err := fs.Sub(db.Migrations, "migrations")
	if err != nil {
		return err
	}
	_ = fsys

	return nil
}

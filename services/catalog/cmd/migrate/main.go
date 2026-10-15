package main

import (
	"io/fs"
	"log/slog"
	"os"

	"github.com/coregatekit/ticketlite/services/catalog/db"
)

func main() {
	if err := run(); err != nil {
		slog.Error("migrate failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	fsys, err := fs.Sub(db.Migrations, "migrations")
	if err != nil {
		return err
	}
	_ = fsys

	return nil
}

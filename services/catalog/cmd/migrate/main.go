package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/coregatekit/ticketlite/services/catalog/db"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, os.Args[1:]); err != nil {
		slog.Error("migrate failed", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	cmd := "up"
	if len(args) > 0 {
		// args[0] is the command to run (e.g., "up", "down")
		cmd = args[0]
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
	fsys, err := migrationsFS()
	if err != nil {
		return err
	}

	// Start the database connection
	conn, err := sql.Open("pgx", dsn)
	if err != nil {
		return err
	}
	defer conn.Close()

	// Create a session locker for the migrations
	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return err
	}

	// Create a new goose provider with the session locker and the migrations filesystem
	provider, err := goose.NewProvider(goose.DialectPostgres, conn, fsys, goose.WithSessionLocker(locker))
	if err != nil {
		return err
	}

	// Run the appropriate command based on the user's input
	if cmd == "status" {
		return printStatus(ctx, provider)
	}
	return applyUp(ctx, provider)
}

func migrationsFS() (fs.FS, error) {
	return fs.Sub(db.Migrations, "migrations")
}

func printStatus(ctx context.Context, provider *goose.Provider) error {
	// Get the current status of all migrations
	statuses, err := provider.Status(ctx)
	if err != nil {
		return err
	}

	// Print the status of each migration
	for _, s := range statuses {
		if s.State == goose.StateApplied {
			slog.Info("applied", "migration", s.Source.Path, "applied_at", s.AppliedAt)
		} else {
			slog.Info("pending", "migration", s.Source.Path)
		}
	}

	return nil
}

func applyUp(ctx context.Context, provider *goose.Provider) error {
	// Apply all pending migrations
	// ได้เฉพาะไฟล์ที่รันในครั้งนี้ ถ้าไม่มีอะไรค้างจะได้ list ว่าง
	results, err := provider.Up(ctx)
	// log ก่อนเช็ค err: ถ้าไฟล์ที่ 3 พัง ไฟล์ 1-2 ผ่านไปแล้ว
	// results จะมีทั้งตัวที่ผ่านและตัวที่พัง คนอ่าน log จะรู้ว่าค้างที่ไฟล์ไหน
	for _, r := range results {
		slog.Info("applied", "migration", r.Source.Path, "duration", r.Duration)
	}
	if err != nil {
		return err
	}

	// เวลา deploy อยากรู้ว่าตอนนี้ database อยู่ version ไหน
	version, err := provider.GetDBVersion(ctx)
	if err != nil {
		return err
	}

	slog.Info("database is up to date", "version", version, "applied", len(results))
	return nil
}

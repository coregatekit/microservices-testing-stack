package venue

//go:generate go tool moq -pkg venue_test -out queries_moq_test.go . Queries
// comment พิเศษ ต้องพิมพ์ติดกัน ห้ามมีช่องว่างหลัง // ไม่อย่างนั้น Go จะไม่เห็น
// -pkg venue_test ให้ไฟล์ที่ได้เป็น package venue_test เหมือนกับ test ของเรา
// -out queries_moq_test.go ชื่อไฟล์ลงท้าย _test.go จึงไม่ถูกรวมเข้า binary ตอน build จริง
// . หมายถึงหา interface ใน package ปัจจุบัน
// Queries คือชื่อ interface ที่ต้องการให้สร้าง mock

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/coregatekit/ticketlite/services/catalog/internal/store"
)

var (
	ErrNotFound = errors.New("venue not found")
	ErrInvalid  = errors.New("invalid venue")
)

type Venue struct {
	ID          uuid.UUID
	OrganizerID string
	Name        string
	Address     string
	Timezone    string
	CreatedAt   time.Time
	CreatedBy   string
	UpdatedAt   time.Time
	UpdatedBy   string
}

type Actor struct {
	UserID      string
	OrganizerID string
}

type CreateInput struct {
	Name     string
	Address  string
	Timezone string
}

type Queries interface {
	CreateVenue(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error)
	GetVenue(ctx context.Context, arg store.GetVenueParams) (store.Venue, error)
	ListVenuesByOrganizer(ctx context.Context, organizerID string) ([]store.Venue, error)
}

type Service struct{ q Queries }

func NewService(q Queries) *Service {
	return &Service{q: q}
}

func (s *Service) Create(ctx context.Context, actor Actor, in CreateInput) (Venue, error) {
	in.Name = strings.TrimSpace(in.Name)
	if in.Name == "" {
		return Venue{}, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	in.Address = strings.TrimSpace(in.Address)
	if in.Address == "" {
		return Venue{}, fmt.Errorf("%w: address is required", ErrInvalid)
	}
	in.Timezone = strings.TrimSpace(in.Timezone)
	if in.Timezone == "" {
		return Venue{}, fmt.Errorf("%w: timezone is required", ErrInvalid)
	}
	return Venue{}, nil
}

func (s *Service) Get(ctx context.Context, actor Actor, id uuid.UUID) (Venue, error) {
	return Venue{}, nil
}

func (s *Service) List(ctx context.Context, actor Actor) ([]Venue, error) {
	return []Venue{}, nil
}

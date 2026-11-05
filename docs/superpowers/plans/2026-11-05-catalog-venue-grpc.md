# Catalog Venue gRPC Implementation Plan

> **For agentic workers:** repo นี้ใช้เรียน ผู้ใช้เขียนโค้ดและ commit เอง ห้ามลงมือแทนด้วย subagent หรือ executing-plans ให้อธิบายขั้นถัดไปเป็นภาษาไทย เสนอโครง test แล้วรีวิวผลงาน ขั้นตอนใช้ checkbox (`- [ ]`) ในการติดตาม

**Goal:** เปิด `venue.Service` ของ catalog ผ่าน gRPC และรันกับ Postgres จริงได้

**Architecture:** สัญญาอยู่ใน `proto/` และ generate โค้ดลง `internal/gen` ของ catalog ส่วน `internal/rpc` แปลง metadata, proto และ error ระหว่าง gRPC กับ `venue.Service` แล้ว `cmd/server` ประกอบทุกชั้นเข้าด้วยกัน

**Tech Stack:** Go 1.27, gRPC, Protobuf, buf 1.73, pgxpool, moq, go-cmp, bufconn

**Spec:** [2026-11-05-catalog-venue-grpc-design.md](../specs/2026-11-05-catalog-venue-grpc-design.md)

## Global Constraints

- รันคำสั่ง `buf` และ `make` จาก root ของ repo ส่วนคำสั่ง `go` รันจาก `services/catalog`
- ไม่ import testify ใช้ `if`, `t.Errorf`, `t.Fatalf` และ go-cmp ตาม [GO_TESTING.md](../../../GO_TESTING.md)
- เทียบ proto message ด้วย `cmp.Diff(want, got, protocmp.Transform())` เพราะ go-cmp เทียบ message ตรงๆ แล้วจะ panic
- ห้ามแก้ไฟล์ใน `internal/gen` และ `_moq_test.go` ด้วยมือ
- ห้ามอ่านไฟล์ `.env` หรือ `mise.<env>.toml` คำสั่งที่ต้องใช้รหัสผ่าน database ผู้ใช้เป็นคนรัน

**รอบ TDD ของแต่ละเงื่อนไข**

1. เขียน test แล้วรันให้ fail ที่ assertion จากนั้น commit ด้วย `test: …`
2. เขียนโค้ดเท่าที่ test บังคับ แล้วรัน `go test ./...` ให้ผ่าน จากนั้น commit ด้วย `feat: …` หรือ `fix: …`
3. ถ้ามีอะไรต้องจัด ให้ commit ด้วย `refactor: …`

ถ้าเงื่อนไขไหนผ่านตั้งแต่แรก ให้ใช้ขั้นตอน "เมื่อ test ไม่มี red" ใน GO_TESTING.md

**ข้อความของ status**

| status | ข้อความ |
| --- | --- |
| `Unauthenticated` | `missing caller identity` |
| `InvalidArgument` จาก id | `invalid venue id` |
| `InvalidArgument` จาก `ErrInvalid` | `err.Error()` จาก service |
| `NotFound` | `venue not found` |
| `Internal` | `internal error` |

## Review Focus

1. metadata ที่มีแต่ช่องว่าง เช่น `x-organizer-id: "   "` ต้องได้ `Unauthenticated` ไม่ใช่ส่ง organizer ว่างไปถึง SQL (Task 2)
2. `id` ที่เป็นสตริงว่าง ซึ่งเกิดเมื่อ client ลืมใส่ field ต้องได้ `InvalidArgument` (Task 2)
3. service ห่อ `ErrNotFound` เพิ่มในอนาคต ต้องยังได้ `NotFound` จึงต้องใช้ `errors.Is` ไม่ใช่ `==` (Task 2)
4. port ถูกใช้อยู่แล้ว process ต้องจบด้วย error ไม่ใช่ค้างรอ signal (Task 5)
5. ส่ง SIGTERM ระหว่างรัน process ต้องปิดเรียบร้อยและ exit code เป็น 0 (Task 5)

---

### Task 1: สัญญาและการ generate โค้ด

**Files:**
- Modify: `proto/ticketlite/catalog/v1/venue.proto`, `Makefile`, `services/catalog/go.mod`, `services/catalog/go.sum`
- Create: `buf.yaml`, `services/catalog/buf.gen.yaml`
- Generated: `services/catalog/internal/gen/ticketlite/catalog/v1/venue.pb.go`, `venue_grpc.pb.go`

**Interfaces:**
- Produces: package `catalogv1` ที่ `github.com/coregatekit/ticketlite/services/catalog/internal/gen/ticketlite/catalog/v1` มี `VenueServiceClient`, `NewVenueServiceClient`, `RegisterVenueServiceServer` และ `UnimplementedVenueServiceServer`

- [ ] **Step 1:** เขียน `venue.proto` ตามหัวข้อ "สัญญา" ใน spec โดยเพิ่ม `syntax = "proto3";`, `package ticketlite.catalog.v1;` และ `import "google/protobuf/timestamp.proto";`
- [ ] **Step 2:** เขียน `buf.yaml` ตาม spec แล้วเพิ่ม target `proto-lint` ใน `Makefile` และ `.PHONY`
- [ ] **Step 3:** รัน `make proto-lint` ต้องไม่มีข้อความ และ exit code เป็น 0
- [ ] **Step 4:** เขียน `services/catalog/buf.gen.yaml` ตาม spec แล้วเพิ่ม target `proto-gen` ที่ต้องมี `SVC` (ใช้ `require-svc`)
- [ ] **Step 5:** รัน `make proto-gen SVC=catalog` ต้องได้ไฟล์ทั้งสองใน `internal/gen/ticketlite/catalog/v1/`
- [ ] **Step 6:** ใน `services/catalog` รัน `go get google.golang.org/grpc google.golang.org/protobuf` แล้ว `go mod tidy`
- [ ] **Step 7:** รัน `go build ./... && go test ./...` ต้องผ่าน
- [ ] **Step 8:** commit ด้วย `feat: add catalog venue gRPC contract`

### Task 2: handler ของ `GetVenue` (เงื่อนไข 1–5)

**Files:**
- Create: `services/catalog/internal/rpc/venue.go`, `services/catalog/internal/rpc/venue_test.go`
- Generated: `services/catalog/internal/rpc/venue_service_moq_test.go`

**Interfaces:**
- Consumes: `catalogv1` จาก Task 1 และ `venue.Actor`, `venue.Venue`, `venue.ErrNotFound`, `venue.ErrInvalid`
- Produces:
  - `rpc.VenueService` ตามที่กำหนดใน spec
  - `func NewVenueHandler(svc VenueService) *VenueHandler`
  - ใน package `rpc` (ไม่ export):
    - `actorFromContext(ctx context.Context) (venue.Actor, error)`
    - `toProtoVenue(v venue.Venue) *catalogv1.Venue`
    - `statusFromError(ctx context.Context, op string, err error) error`
  - ใน test: `newTestClient(t *testing.T, svc rpc.VenueService) catalogv1.VenueServiceClient` และ `withActor(ctx context.Context) context.Context`

- [ ] **Step 1: ตั้งโครง** เขียน `venue.go` ให้มีแค่ `VenueService`, `VenueHandler` (ฝัง `UnimplementedVenueServiceServer`) และ `NewVenueHandler` พร้อมบรรทัดนี้

```go
//go:generate go tool moq -pkg rpc_test -out venue_service_moq_test.go . VenueService
```

รัน `go generate ./internal/rpc/` ต้องได้ `VenueServiceMock`

- [ ] **Step 2: เขียน helper ของ test**
  - `newTestClient` ใช้ `bufconn.Listen(1024 * 1024)` และ `grpc.NewClient("passthrough:///bufnet", ...)` พร้อม `grpc.WithContextDialer` กับ `insecure.NewCredentials()` ปิด client และ server ใน `t.Cleanup`
  - `withActor` ใช้ `metadata.AppendToOutgoingContext(ctx, "x-user-id", "user-1", "x-organizer-id", "org-1")`

- [ ] **Step 3: เงื่อนไข 1, `TestGetVenue_Success`** ตอนนี้ test จะ fail ด้วย `Unimplemented` ซึ่งถือว่าเป็น red ที่ถูกต้อง

```go
// fixture ใช้ CreatedAt และ UpdatedAt คนละค่า เพื่อจับการใส่สลับช่อง
if got := calls[0].Actor; got != (venue.Actor{UserID: "user-1", OrganizerID: "org-1"}) { /* Errorf */ }
if got := calls[0].ID; got != id { /* Errorf */ }
want := &catalogv1.Venue{ /* ทั้ง 6 ช่อง โดยเวลาใช้ timestamppb.New */ }
if diff := cmp.Diff(want, resp.GetVenue(), protocmp.Transform()); diff != "" { /* Errorf */ }
```

- [ ] **Step 4: เงื่อนไข 2, `TestGetVenue_Unauthenticated`** เป็น table ที่ส่ง metadata ด้วย `metadata.NewOutgoingContext` และเช็ก 2 อย่างทุกแถว

```go
if got := status.Code(err); got != codes.Unauthenticated { /* Errorf */ }
if n := len(svc.GetCalls()); n != 0 { /* Errorf */ }
```

| ชื่อ subtest | metadata |
| --- | --- |
| `NoMetadata` | ไม่มี |
| `MissingUserID` | มีแค่ `x-organizer-id` |
| `MissingOrganizerID` | มีแค่ `x-user-id` |
| `BlankUserID` | `x-user-id: "   "` |
| `BlankOrganizerID` | `x-organizer-id: "   "` |
| `DuplicateUserID` | `x-user-id` 2 ค่า |
| `DuplicateOrganizerID` | `x-organizer-id` 2 ค่า |

- [ ] **Step 5: เงื่อนไข 3, `TestGetVenue_InvalidID`** table มีแถว `Empty` (`""`) และ `NotUUID` (`"not-a-uuid"`) เช็กว่าได้ `codes.InvalidArgument` และ `len(svc.GetCalls()) == 0`

- [ ] **Step 6: เงื่อนไข 4, `TestGetVenue_NotFound`** table มีแถว `Sentinel` (`venue.ErrNotFound`) และ `Wrapped` (`fmt.Errorf("lookup: %w", venue.ErrNotFound)`) เช็กว่าได้ `codes.NotFound`

- [ ] **Step 7: เงื่อนไข 5, `TestGetVenue_InternalError`** ใช้ `dbErr := errors.New("connection refused to 10.0.0.5")`

```go
if got := status.Code(err); got != codes.Internal { /* Errorf */ }
if strings.Contains(status.Convert(err).Message(), "10.0.0.5") { /* Errorf: รายละเอียดรั่วถึง client */ }
```

ตรงนี้ `statusFromError` ควรมีครบทุกกรณีตามตาราง "ข้อความของ status" และเรียก `slog.ErrorContext(ctx, op, "error", err)` เฉพาะกรณี `Internal`

- [ ] **Step 8:** รัน `go vet ./... && go test ./...` ต้องผ่าน

### Task 3: handler ของ `CreateVenue` (เงื่อนไข 6–9)

**Files:**
- Modify: `services/catalog/internal/rpc/venue.go`, `services/catalog/internal/rpc/venue_test.go`

**Interfaces:**
- Consumes: `newTestClient`, `withActor`, `actorFromContext`, `toProtoVenue` และ `statusFromError` จาก Task 2

- [ ] **Step 1: เงื่อนไข 6, `TestCreateVenue_Success`** เช็กว่า `calls[0].Actor` ถูก, `calls[0].In == venue.CreateInput{Name: "Hall A", Address: "Bangkok", Timezone: "Asia/Bangkok"}` และ response ตรงกับค่าที่ mock คืน ไม่ใช่ค่าจาก request ดังนั้น fixture ต้องต่างจาก input ทุกช่อง
- [ ] **Step 2: เงื่อนไข 7, `TestCreateVenue_Unauthenticated`** ไม่ส่ง metadata เช็กว่าได้ `codes.Unauthenticated` และ `len(svc.CreateCalls()) == 0`
- [ ] **Step 3: เงื่อนไข 8, `TestCreateVenue_Invalid`** mock คืน `fmt.Errorf("%w: name is required", venue.ErrInvalid)` เช็กว่าได้ `codes.InvalidArgument` และข้อความมี `name is required`
- [ ] **Step 4: เงื่อนไข 9, `TestCreateVenue_InternalError`** ใช้แบบเดียวกับ Task 2 เงื่อนไข 5 เงื่อนไขนี้น่าจะไม่มี red เพราะใช้ `statusFromError` ร่วมกัน ให้ทำตามขั้นตอน "เมื่อ test ไม่มี red"
- [ ] **Step 5:** รัน `go vet ./... && go test ./...` ต้องผ่าน

### Task 4: handler ของ `ListVenues` (เงื่อนไข 10–13)

**Files:**
- Modify: `services/catalog/internal/rpc/venue.go`, `services/catalog/internal/rpc/venue_test.go`

**Interfaces:**
- Consumes: เหมือน Task 3
- Produces: `VenueHandler` ที่ทำครบ 3 RPC

- [ ] **Step 1: เงื่อนไข 10, `TestListVenues_Success`** mock คืน 2 venue ที่ id ไม่ได้เรียงจากน้อยไปมาก เช็กว่าส่ง actor ถูก และ `cmp.Diff` กับ `[]*catalogv1.Venue` ที่เขียนใน test ลำดับต้องตรงกับที่ mock คืน
- [ ] **Step 2: เงื่อนไข 11, `TestListVenues_Empty`** mock คืน `[]venue.Venue{}` เช็กว่า `err == nil` และ `len(resp.GetVenues()) == 0` ห้ามเช็ก `nil`
- [ ] **Step 3: เงื่อนไข 12, `TestListVenues_Unauthenticated`** ไม่ส่ง metadata เช็กว่าได้ `codes.Unauthenticated` และ `len(svc.ListCalls()) == 0`
- [ ] **Step 4: เงื่อนไข 13, `TestListVenues_InternalError`** ใช้แบบเดียวกับ Task 2 เงื่อนไข 5
- [ ] **Step 5:** รัน `go vet ./... && go test ./...` ต้องผ่าน

### Task 5: ต่อ server จริง

**Files:**
- Modify: `services/catalog/cmd/server/main.go`, `mise.env-example.toml`

**Interfaces:**
- Consumes: `rpc.NewVenueHandler`, `catalogv1.RegisterVenueServiceServer`, `store.New`, `venue.NewService`
- Produces: `func run(ctx context.Context) error` ใน `package main`

- [ ] **Step 1:** เขียน `main` ตามรูปแบบของ `cmd/migrate/main.go` คือใช้ `signal.NotifyContext` กับ `os.Interrupt` และ `syscall.SIGTERM` ถ้า `run` คืน error ให้ `slog.Error` แล้ว `os.Exit(1)`
- [ ] **Step 2:** เขียน `run` ตามลำดับในหัวข้อ "Server" ของ spec โดยค่าเริ่มต้นของ `CATALOG_GRPC_ADDR` คือ `127.0.0.1:50051`
- [ ] **Step 3:** ให้ goroutine ของ `Serve` ส่ง error เข้า channel แล้ว `run` ใช้ `select` รอทั้ง channel นั้นและ `ctx.Done()` ถ้า `ctx` จบก่อนให้ `GracefulStop` แล้วคืน `nil` ไม่อย่างนั้น `Serve` ที่พังจะทำให้ process ค้าง
- [ ] **Step 4:** เพิ่มบรรทัดนี้ใต้ `CATALOG_DATABASE_URL` ใน `mise.env-example.toml`

```toml
# CATALOG_GRPC_ADDR = "127.0.0.1:50051"
```

- [ ] **Step 5:** ผู้ใช้รัน `make db-up` และ `make migrate-up SVC=catalog` จากนั้นรัน `go run ./cmd/server` ใน `services/catalog` ต้องเห็น log ว่าเริ่มแล้ว
- [ ] **Step 6:** ผู้ใช้เช็กกรณีที่ผิดปกติ โดยแต่ละกรณีต้องได้ log error และ exit code 1 ทันที ยกเว้นกรณี SIGTERM

| กรณี | วิธีทำ |
| --- | --- |
| ไม่มี URL | `env -u CATALOG_DATABASE_URL go run ./cmd/server` |
| database ปิดอยู่ | `make db-down` แล้วรัน server จากนั้น `make db-up` |
| port ซ้ำ | รัน server ตัวที่สองขณะที่ตัวแรกยังทำงาน |
| SIGTERM | build ด้วย `go build -o <scratchpad>/catalog-server ./cmd/server` แล้วรัน binary นั้น ส่ง `kill -TERM <pid>` ต้องได้ exit code 0 เพราะ `go run` อาจคืน exit code ของตัวเอง |

- [ ] **Step 7:** รัน `go vet ./... && go test ./...` ต้องผ่าน แล้ว commit ด้วย `feat: start catalog gRPC server`

### Task 6: เช็กตามเกณฑ์ว่าเสร็จ

**Files:** ไม่มีไฟล์ใหม่ ถ้าพบปัญหาให้กลับไปแก้แบบ TDD ใน Task ที่เกี่ยวข้อง

- [ ] **Step 1:** ผู้ใช้รัน `CreateVenue` ด้วย `buf curl` ตาม spec โดยใช้ `org-1` ต้องได้ venue พร้อม `id`
- [ ] **Step 2:** รัน `GetVenue` ด้วย id นั้นและ `org-1` ต้องเจอ
- [ ] **Step 3:** รัน `GetVenue` ด้วย id เดิมและ `org-2` ต้องได้ `not_found`
- [ ] **Step 4:** รัน `ListVenues` ด้วย `org-1` ต้องเห็น venue นั้น และด้วย `org-2` ต้องไม่เห็น
- [ ] **Step 5:** รัน `GetVenue` โดยไม่ส่ง metadata ต้องได้ `unauthenticated`
- [ ] **Step 6:** รัน `make proto-lint`, `make test SVC=catalog` และ `make test-integration SVC=catalog` ต้องผ่านทั้งหมด
- [ ] **Step 7:** Claude รีวิว diff ทั้ง branch เทียบกับ spec ก่อน merge หรือ push

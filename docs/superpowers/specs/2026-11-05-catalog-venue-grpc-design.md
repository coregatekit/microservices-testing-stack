# Catalog venue gRPC API

เอกสารนี้กำหนดการเปิด `venue.Service` (`Create`, `Get`, `List`) ของ catalog ผ่าน gRPC โดยเขียนสัญญา `.proto` ก่อน แล้วจึงเขียน handler และต่อ server จริง

## เป้าหมาย

- BFF หรือ service ภายในอื่นเรียกสร้าง อ่าน และแสดงรายการ venue ผ่าน gRPC ได้
- venue ของ organizer อื่นต้องได้ `NotFound` เหมือนกับ id ที่ไม่มีอยู่จริง
- ได้เรียนรู้ contract-first, generated code, การแปลง error เป็น gRPC status และการอ่าน actor จาก metadata

### สิ่งที่ไม่อยู่ในรอบนี้

- update, delete และ pagination ของ venue
- authentication จริง และ mTLS
- gRPC reflection, health check และ TLS
- `buf breaking` ใน Makefile (ทำตอนตั้ง CI เพราะต้องมี proto บน `main` ก่อนจึงจะมีของให้เทียบ)
- การเรียกจาก BFF

## การตัดสินใจ

| เรื่อง | ที่เลือก | เหตุผล |
| --- | --- | --- |
| ตำแหน่ง `.proto` | `proto/` | ตรงกับโฟลเดอร์ที่มีอยู่ และยังไม่มี GraphQL หรือ OpenAPI ให้ต้องรวมไว้ด้วยกัน การตัดสินใจนี้แทนที่ `contracts/` ใน `docs/handoff/handoff-project-structure-mise-toolchains.md` |
| ตำแหน่งโค้ดที่ generate | `services/catalog/internal/gen/` และ commit เข้า repo | แต่ละ Go module แยกอิสระ เหมือน `internal/store` ของ sqlc |
| ตัวตนของผู้เรียก | metadata `x-user-id` และ `x-organizer-id` | ทางชั่วคราวจนกว่าจะมี authentication ดู[เรื่องที่พักไว้](#เรื่องที่พักไว้) |
| การอ่าน actor | เรียก `actorFromContext` จากแต่ละ handler | service บังคับรับ `Actor` จึงลืมไม่ได้ และไม่ต้องมีรายการยกเว้นแบบ interceptor |
| การ test handler | `bufconn` | metadata และ status ผ่าน gRPC จริงโดยไม่ต้องใช้ port หรือ Docker |
| address เริ่มต้น | `127.0.0.1:50051` | catalog เชื่อ metadata โดยไม่ตรวจ จึงไม่ควรเปิดทุก network interface ตั้งแต่ค่าเริ่มต้น |

## สัญญา

ไฟล์ `proto/ticketlite/catalog/v1/venue.proto` เป็น package `ticketlite.catalog.v1`

```proto
service VenueService {
  rpc CreateVenue(CreateVenueRequest) returns (CreateVenueResponse);
  rpc GetVenue(GetVenueRequest) returns (GetVenueResponse);
  rpc ListVenues(ListVenuesRequest) returns (ListVenuesResponse);
}

message Venue {
  string id = 1;
  string name = 2;
  string address = 3;
  string timezone = 4;
  google.protobuf.Timestamp created_at = 5;
  google.protobuf.Timestamp updated_at = 6;
}

message CreateVenueRequest {
  string name = 1;
  string address = 2;
  string timezone = 3;
}

message CreateVenueResponse {
  Venue venue = 1;
}

message GetVenueRequest {
  string id = 1;
}

message GetVenueResponse {
  Venue venue = 1;
}

message ListVenuesRequest {}

message ListVenuesResponse {
  repeated Venue venues = 1;
}
```

- ไม่ส่ง `organizer_id`, `created_by` และ `updated_by` เพราะยังไม่มีผู้เรียกที่ต้องใช้ เพิ่มทีหลังได้โดยไม่กระทบ client เดิม แต่ถ้าส่งไปแล้วจะเอาออกทีหลังถือเป็น breaking change
- ไม่มี `organizer_id` ใน request เพราะค่านี้มาจาก metadata
- `.proto` ไม่ใส่ `option go_package` เพราะแต่ละ service กำหนด path ของตัวเองตอน generate

## การ generate โค้ด

| ไฟล์ | หน้าที่ |
| --- | --- |
| `buf.yaml` (ที่ root) | module อยู่ที่ `proto` ใช้กฎ lint `STANDARD` และกฎ breaking `FILE` |
| `services/catalog/buf.gen.yaml` | ค่าตั้งการ generate ของ catalog |
| `Makefile` | เพิ่ม `proto-lint` และ `proto-gen SVC=<svc>` |

```yaml
# services/catalog/buf.gen.yaml
version: v2
managed:
  enabled: true
  override:
    - file_option: go_package_prefix
      value: github.com/coregatekit/ticketlite/services/catalog/internal/gen
plugins:
  - local: protoc-gen-go
    out: services/catalog/internal/gen
    opt: paths=source_relative
  - local: protoc-gen-go-grpc
    out: services/catalog/internal/gen
    opt: paths=source_relative
```

รันจาก root ของ repo

```bash
buf generate --template services/catalog/buf.gen.yaml --path proto/ticketlite/catalog
```

`make proto-gen SVC=catalog` ต้องรันคำสั่งนี้ โดยใช้ `$(SVC)` แทน `catalog` ทั้งสองจุด ถ้าวันหลัง service ไหนต้อง generate proto ของ service อื่น ค่อยปรับ target ตอนนั้น

ผลที่ได้คือ `venue.pb.go` และ `venue_grpc.pb.go` ใน `services/catalog/internal/gen/ticketlite/catalog/v1/` เป็น package `catalogv1` ห้ามแก้ด้วยมือ

catalog ต้องเพิ่ม dependency `google.golang.org/grpc` และ `google.golang.org/protobuf`

## Handler

อยู่ที่ `services/catalog/internal/rpc/venue.go` ไม่ตั้งชื่อ package ว่า `grpc` เพื่อไม่ให้ชนกับ `google.golang.org/grpc`

```go
type VenueService interface {
	Create(ctx context.Context, actor venue.Actor, in venue.CreateInput) (venue.Venue, error)
	Get(ctx context.Context, actor venue.Actor, id uuid.UUID) (venue.Venue, error)
	List(ctx context.Context, actor venue.Actor) ([]venue.Venue, error)
}

type VenueHandler struct {
	catalogv1.UnimplementedVenueServiceServer
	svc VenueService
}
```

ทุก RPC ทำงานตามลำดับนี้

1. อ่าน actor ด้วย `actorFromContext(ctx)`
2. ตรวจ input ของ RPC นั้น
3. เรียก service
4. แปลงผลเป็น proto

`actorFromContext` ต้องพบ `x-user-id` และ `x-organizer-id` อย่างละหนึ่งค่า และค่าต้องไม่ว่างหลังตัดช่องว่าง ถ้าส่งมาหลายค่าถือว่าไม่ผ่าน

### การแปลง error

| สถานการณ์ | gRPC status | ข้อความที่ client เห็น |
| --- | --- | --- |
| metadata ขาด ว่าง หรือมีหลายค่า | `Unauthenticated` | บอกว่าขาดตัวตนของผู้เรียก |
| `id` ไม่ใช่ UUID | `InvalidArgument` | บอกว่า id ไม่ถูกต้อง |
| `venue.ErrInvalid` | `InvalidArgument` | ข้อความจาก service ที่บอกว่า field ไหนผิด |
| `venue.ErrNotFound` | `NotFound` | `venue not found` |
| error อื่นทั้งหมด | `Internal` | ข้อความกลางๆ ส่วนรายละเอียดจริงลง log ด้วย `slog` |

สองกรณีแรกต้องไม่เรียก service เลย

## Server

`cmd/server/main.go` ใช้รูปแบบเดียวกับ `cmd/migrate/main.go` คือ `main` สร้าง context จาก signal แล้วเรียก `run(ctx)` ที่คืน error

| ตัวแปร | จำเป็น | ค่าเริ่มต้น | ใช้ทำอะไร |
| --- | --- | --- | --- |
| `CATALOG_DATABASE_URL` | ใช่ | ไม่มี | ต่อ Postgres ถ้าไม่มีให้คืน error ทันที |
| `CATALOG_GRPC_ADDR` | ไม่ | `127.0.0.1:50051` | address ที่ server รอรับ |

ลำดับงานใน `run`

1. อ่านตัวแปรทั้งสอง
2. สร้าง `pgxpool` แล้ว `Ping` เพื่อให้ server หยุดตั้งแต่ตอนเริ่มถ้าต่อ database ไม่ได้
3. ประกอบ `store.New(pool)`, `venue.NewService` และ `rpc.NewVenueHandler`
4. สร้าง `grpc.NewServer()`, register handler แล้ว `Serve` ใน goroutine
5. รอ signal แล้วเรียก `GracefulStop`

## Test

test อยู่ที่ `services/catalog/internal/rpc/venue_test.go` เป็น package `rpc_test` และทำตาม [GO_TESTING.md](../../../GO_TESTING.md)

- mock `VenueService` ด้วย moq ในไฟล์ `_moq_test.go`
- helper `newTestClient(t, svc)` รัน server บน `bufconn` คืน client ที่ generate มา และปิดทุกอย่างด้วย `t.Cleanup`
- mock ที่ไม่ได้ตั้ง `XxxFunc` จะ panic ใน goroutine ของ server ซึ่งทำให้ test binary พังทั้งตัว ไม่ใช่แค่ test เดียว

### เงื่อนไขตามลำดับ TDD

| # | RPC | เงื่อนไข | ผลที่ต้องการ |
| --- | --- | --- | --- |
| 1 | `GetVenue` | สำเร็จ | ส่ง actor กับ id ถูกต้อง และแปลงทั้ง 6 ช่องถูก |
| 2 | `GetVenue` | metadata ไม่ครบ: ไม่มีเลย, ขาดแต่ละ key, ค่าว่าง, มีหลายค่า | `Unauthenticated` และไม่เรียก service |
| 3 | `GetVenue` | `id` ไม่ใช่ UUID | `InvalidArgument` และไม่เรียก service |
| 4 | `GetVenue` | `ErrNotFound` | `NotFound` |
| 5 | `GetVenue` | error อื่น | `Internal` และข้อความไม่มีรายละเอียดของ error จริง |
| 6 | `CreateVenue` | สำเร็จ | ส่ง actor กับ input ถูกต้อง และคืน venue |
| 7 | `CreateVenue` | ไม่มี metadata | `Unauthenticated` และไม่เรียก service |
| 8 | `CreateVenue` | `ErrInvalid` ที่ห่อข้อความมา | `InvalidArgument` และมีข้อความ `name is required` |
| 9 | `CreateVenue` | error อื่น | `Internal` |
| 10 | `ListVenues` | สำเร็จ | ส่ง actor ถูกต้อง และคงลำดับเดิม |
| 11 | `ListVenues` | ไม่มี venue | `len == 0` ไม่เช็ก `nil` เพราะ repeated field ที่ว่างจะไม่ถูกส่ง |
| 12 | `ListVenues` | ไม่มี metadata | `Unauthenticated` และไม่เรียก service |
| 13 | `ListVenues` | error อื่น | `Internal` |

`main.go` ไม่มี unit test จึงแยก commit และเช็กด้วยการรันจริงแทน

### เกณฑ์ว่าเสร็จ

รัน server กับ Postgres จริง แล้วเรียกด้วย `buf curl` ไม่ต้องติดตั้ง `grpcurl`

```bash
buf curl --schema proto --protocol grpc --http2-prior-knowledge \
  -H 'x-user-id: user-1' -H 'x-organizer-id: org-1' \
  -d '{"name":"Hall A","address":"Bangkok","timezone":"Asia/Bangkok"}' \
  http://127.0.0.1:50051/ticketlite.catalog.v1.VenueService/CreateVenue
```

1. สร้าง venue ด้วย `org-1` แล้ว `GetVenue` ด้วย `org-1` ต้องเจอ
2. `GetVenue` ด้วย `org-2` ต้องได้ `NotFound`
3. ไม่ส่ง metadata ต้องได้ `Unauthenticated`
4. `buf lint`, `make test SVC=catalog` และ `make test-integration SVC=catalog` ต้องผ่าน

## ลำดับการทำงาน

1. `.proto`, `buf.yaml`, `buf.gen.yaml`, make target และโค้ดที่ generate
2. handler ตามเงื่อนไขข้อ 1–13 ทีละเงื่อนไข
3. `main.go`
4. เช็กตามเกณฑ์ว่าเสร็จ

## เรื่องที่พักไว้

| เรื่อง | ตอนนี้ | กลับมาทำเมื่อ |
| --- | --- | --- |
| ตัวตนของผู้เรียก | catalog เชื่อ metadata จาก BFF โดยไม่ตรวจ ใครที่เข้าถึง port ได้ก็ปลอมเป็น organizer ไหนก็ได้ port จึงต้องเปิดให้เฉพาะ service ภายใน | ทำ authentication เสร็จ ให้ทบทวนว่า catalog ควรตรวจ JWT เองหรือไม่ แก้เฉพาะ `actorFromContext` ส่วน `venue.Service` ไม่ต้องแก้ |
| interceptor สำหรับ actor | ทุก handler เรียก `actorFromContext` เอง | ทำ authentication เสร็จและมี RPC มากขึ้น |
| `context.Canceled` และ `DeadlineExceeded` | เป็น `Internal` และลง log | มี client จริงที่ใช้ deadline หรือ log เริ่มรก |
| ธรรมเนียมการส่ง user id | diagram มี `CancelBooking(bookingId, userId จาก token)` ซึ่งดูเหมือนส่งเป็น argument | ทำ booking ให้เลือกวิธีเดียวแล้วใช้เหมือนกันทุก service |
| address ตอน deploy | ค่าเริ่มต้นเปิดเฉพาะ localhost | deploy ใน container ต้องตั้ง `CATALOG_GRPC_ADDR=:50051` และมีกฎเครือข่ายกันคนนอก |

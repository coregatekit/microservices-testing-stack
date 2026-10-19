# คู่มือการเขียน query (sqlc)

query ทั้งหมดของ catalog service เขียนเป็น SQL ในโฟลเดอร์นี้ แล้วให้ [sqlc](https://docs.sqlc.dev) สร้างโค้ด Go ที่ type-safe ไว้ใน `internal/store/`

ตัวอย่างในคู่มือนี้ทดสอบกับ schema จริงของ catalog ด้วย sqlc 1.31.1 แล้ว

## ขั้นตอนการทำงาน

1. เขียนหรือแก้ query ในไฟล์ `.sql` ของโฟลเดอร์นี้
2. รัน `sqlc generate` ใน `services/catalog/`
3. ถ้า error ให้แก้ SQL แล้วรันใหม่ sqlc ตรวจชื่อตาราง ชื่อคอลัมน์ และชนิดข้อมูลกับ migration ให้ตั้งแต่ตอน generate เช่น
   ```text
   db/queries/events.sql:2:28: column "titel" does not exist
   ```
4. เขียน integration test ให้ query ใหม่ (ดู [การทดสอบ](#การทดสอบ))
5. commit ทั้งไฟล์ `.sql` และโค้ดที่ generate ใน `internal/store/` ไปด้วยกัน

sqlc อ่าน schema จาก `db/migrations/` โดยตรง ถ้าเพิ่มหรือแก้ migration ต้องรัน `sqlc generate` ใหม่ทุกครั้ง แม้จะไม่ได้แก้ query เลย เพราะ struct ใน `models.go` จะเปลี่ยนตาม และ `SELECT *` จะถูกขยายเป็นรายชื่อคอลัมน์ใหม่

## กฎของโปรเจกต์

- **ห้ามแก้ไฟล์ใน `internal/store/` ด้วยมือ** ทุกไฟล์ในโฟลเดอร์นั้นเป็นของ sqlc และจะถูกเขียนทับตอน generate ครั้งถัดไป ถ้าใครแก้ `sqlc diff` จะเจอ (ดู [ตรวจว่าโค้ดตรงกับ SQL](#ตรวจว่าโค้ดตรงกับ-sql))
- **แยกไฟล์ตามตารางหลัก** เช่น `venues.sql`, `events.sql`, `showtimes.sql` แต่ละไฟล์จะได้ไฟล์ Go ชื่อเดียวกัน เช่น `events.sql.go`
- **ตั้งชื่อ query ขึ้นต้นด้วยคำกริยา** เช่น `CreateX`, `GetX`, `ListXByY`, `UpdateX`, `DeleteX` ชื่อนี้จะกลายเป็นชื่อ method ใน Go
- **ข้อมูลที่เป็นของ organizer ต้องกรองด้วย `organizer_id` ทุกครั้ง** รวมถึง Get, Update และ Delete ไม่ใช่แค่ List เพื่อกัน IDOR (ผู้ใช้เดา id แล้วเข้าถึงข้อมูลของคนอื่นได้) ตัวอย่างคือ `GetVenue` ที่ใช้ `WHERE venue_id = @venue_id AND organizer_id = @organizer_id`
- **INSERT ต้องใส่ `created_by` และ `updated_by`** ส่วน UPDATE ต้องใส่ `updated_by` เสมอ ให้ใช้พารามิเตอร์ชื่อ `@actor` ตาม `CreateVenue` ส่วน `created_at` และ `updated_at` ไม่ต้องใส่ เพราะ DB ใส่ให้เอง
- **List ต้องมี `ORDER BY` เสมอ** ถ้าไม่มี Postgres จะคืนแถวในลำดับที่ไม่แน่นอน ตาราง id เป็น uuidv7 ซึ่งเรียงตามเวลาที่สร้าง `ORDER BY <table>_id` จึงได้ "เก่าไปใหม่"

## คำสั่งท้ายชื่อ query

ทุก query ต้องขึ้นต้นด้วย comment บอกชื่อและชนิด:

```sql
-- name: GetVenue :one
```

| ชนิด                                    | ใช้เมื่อ                                     | method ที่ได้                                       |
| --------------------------------------- | -------------------------------------------- | --------------------------------------------------- |
| `:one`                                  | คืน 1 แถว เช่น Get หรือ INSERT ... RETURNING | `(T, error)` ถ้าไม่เจอแถวได้ `pgx.ErrNoRows`        |
| `:many`                                 | คืนหลายแถว                                   | `([]T, error)` ไม่เจอแถวได้ slice ว่าง ไม่ใช่ error |
| `:exec`                                 | ไม่สนผลลัพธ์                                 | `error`                                             |
| `:execrows`                             | ต้องรู้ว่ามีกี่แถวถูกแก้ไข                   | `(int64, error)`                                    |
| `:copyfrom`                             | insert หลายพันแถวพร้อมกัน                    | `(int64, error)`                                    |
| `:batchexec`, `:batchone`, `:batchmany` | ส่งหลาย query ไปในรอบเดียว                   | `*XBatchResults`                                    |

ถ้าใช้ `:one` แล้วไม่เจอแถว ให้เช็คด้วย `errors.Is(err, pgx.ErrNoRows)` แล้วแปลงเป็น error ของ domain เช่น `ErrVenueNotFound` อย่าส่ง `pgx.ErrNoRows` ออกไปนอกชั้นที่คุยกับ DB

## พารามิเตอร์

| รูปแบบ              | ความหมาย                                                              |
| ------------------- | --------------------------------------------------------------------- |
| `@name`             | พารามิเตอร์ปกติ ชื่อในโค้ดจะเป็น `Name` (ย่อมาจาก `sqlc.arg('name')`) |
| `sqlc.narg('name')` | พารามิเตอร์ที่ส่งเป็น NULL ได้ ใช้กับเงื่อนไขที่ไม่บังคับ             |
| `@name::uuid[]`     | cast เพื่อบอกชนิดให้ sqlc เมื่อเดาเองไม่ได้                           |

ถ้า query มีพารามิเตอร์ตัวเดียว method จะรับค่านั้นตรงๆ เช่น `ListVenuesByOrganizer(ctx, organizerID string)` ถ้ามีหลายตัว sqlc จะสร้าง struct `XParams` ให้

ใช้ชื่อเดียวกันซ้ำได้ เช่น `@actor` ใน `CreateVenue` ใช้กับทั้ง `created_by` และ `updated_by` ฝั่ง Go จะเห็นแค่ฟิลด์ `Actor` ฟิลด์เดียว

## ชนิดข้อมูลใน Go

ตั้งค่าไว้ใน `sqlc.yaml`:

| คอลัมน์ใน Postgres | NOT NULL    | ว่างได้ (nullable)   |
| ------------------ | ----------- | -------------------- |
| `uuid`             | `uuid.UUID` | `pgtype.UUID`        |
| `timestamptz`      | `time.Time` | `pgtype.Timestamptz` |
| `text`             | `string`    | `pgtype.Text`        |
| `integer`          | `int32`     | `pgtype.Int4`        |
| `smallint`         | `int16`     | `pgtype.Int2`        |
| `bigint`           | `int64`     | `pgtype.Int8`        |
| `count(*)`         | `int64`     | —                    |

ชนิด `pgtype.X` มีฟิลด์ `Valid` บอกว่าเป็น NULL หรือไม่ เช่น `pgtype.Text{String: "THB", Valid: true}` ค่า zero value (`pgtype.Text{}`) หมายถึง NULL

## สูตรที่ใช้บ่อย

### Get ที่กัน IDOR

```sql
-- name: GetEvent :one
SELECT * FROM events
WHERE event_id = @event_id AND organizer_id = @organizer_id;
```

### Update พร้อมกันแก้ทับกัน (optimistic locking)

`events.version` มีไว้กันกรณีสองคนแก้งานเดียวกันพร้อมกัน ให้อ่าน version ไปพร้อมข้อมูล แล้วตอน UPDATE ต้องส่งค่าที่อ่านมากลับมาด้วย:

```sql
-- name: UpdateEventTitle :execrows
UPDATE events
SET title = @title, updated_by = @actor, version = version + 1
WHERE event_id = @event_id
  AND organizer_id = @organizer_id
  AND version = @expected_version;
```

ใช้ `:execrows` เพื่อรู้ผล ถ้าได้ `0` แปลว่าไม่เจองานนั้น หรือมีคนแก้ไปก่อนแล้ว (version ไม่ตรง) ถ้าต้องแยกสองกรณีนี้ ให้ Get ซ้ำอีกครั้ง

### เงื่อนไขที่ส่งหรือไม่ส่งก็ได้ + แบ่งหน้า

```sql
-- name: ListEventsFiltered :many
SELECT * FROM events
WHERE organizer_id = @organizer_id
  AND (sqlc.narg('status')::text IS NULL OR status = sqlc.narg('status'))
  AND (sqlc.narg('after_id')::uuid IS NULL OR event_id > sqlc.narg('after_id'))
ORDER BY event_id
LIMIT @page_size;
```

จะได้:

```go
type ListEventsFilteredParams struct {
	OrganizerID string
	Status      pgtype.Text // Valid: false = ไม่กรองตาม status
	AfterID     pgtype.UUID // Valid: false = หน้าแรก
	PageSize    int32
}
```

การแบ่งหน้าใช้แบบ keyset คือส่ง id ตัวสุดท้ายของหน้าก่อนมาเป็น `after_id` แทนการใช้ `OFFSET` เพราะ `OFFSET 10000` ต้องอ่านทิ้ง 10,000 แถวทุกครั้ง แต่ `event_id > x` กระโดดไปที่ index ได้ทันที

ใช้ `narg` แบบนี้เมื่อมีเงื่อนไขไม่เกิน 2-3 ตัว ถ้ามากกว่านี้ ดู [เมื่อ sqlc ไม่พอ](#เมื่อ-sqlc-ไม่พอ)

### ค้นด้วยรายการ id

```sql
-- name: ListEventsByIDs :many
SELECT * FROM events
WHERE event_id = ANY(@event_ids::uuid[]);
```

ได้ method `ListEventsByIDs(ctx, eventIds []uuid.UUID)`

> **อย่าใช้ `sqlc.slice` กับ Postgres** sqlc จะ generate ผ่าน แต่ได้ SQL เป็น `IN ($1)` ซึ่งจะ error ตอนรันจริง `sqlc.slice` ใช้ได้เฉพาะกับ MySQL และ SQLite เท่านั้น

### JOIN แล้วได้ struct ซ้อนกัน

```sql
-- name: ListShowtimesWithVenue :many
SELECT sqlc.embed(showtimes), sqlc.embed(venues)
FROM showtimes
JOIN venues ON venues.venue_id = showtimes.venue_id
WHERE showtimes.event_id = @event_id
ORDER BY showtimes.starts_at;
```

จะได้ struct ที่ใช้ model เดิมของแต่ละตาราง:

```go
type ListShowtimesWithVenueRow struct {
	Showtime Showtime
	Venue    Venue
}
```

ถ้าไม่ใช้ `sqlc.embed` sqlc จะรวมทุกคอลัมน์ไว้ใน struct เดียวแบบแบน และคอลัมน์ที่ชื่อซ้ำกัน เช่น `created_at` จะได้ชื่อฟิลด์ที่อ่านยาก เช่น `CreatedAt_2`

### Aggregate

```sql
-- name: CountShowtimesByEvent :many
SELECT e.event_id, e.title, count(s.showtime_id) AS showtime_count
FROM events e
LEFT JOIN showtimes s ON s.event_id = e.event_id
WHERE e.organizer_id = @organizer_id
GROUP BY e.event_id, e.title;
```

ต้องตั้งชื่อคอลัมน์ที่คำนวณด้วย `AS` เสมอ ไม่งั้น sqlc จะตั้งชื่อฟิลด์เป็น `Count`

### Insert จำนวนมาก (เก้าอี้ในผัง)

ผังหนึ่งมีเก้าอี้ได้หลายพันที่ ถ้า INSERT ทีละแถวจะช้ามาก ให้ใช้ `:copyfrom` ซึ่งใช้คำสั่ง `COPY` ของ Postgres:

```sql
-- name: InsertSeats :copyfrom
INSERT INTO seat_map_seats (seat_map_id, seat_id, section_code, row_label, seat_number)
VALUES (@seat_map_id, @seat_id, @section_code, @row_label, @seat_number);
```

ได้ method `InsertSeats(ctx, []InsertSeatsParams) (int64, error)`

ข้อจำกัดของ `COPY`:

- ใช้ `RETURNING` ไม่ได้
- ใช้ `ON CONFLICT` ไม่ได้ ถ้ามีแถวไหนผิด constraint จะล้มทั้งชุด
- ควรเรียกใน transaction เดียวกับการสร้างผัง ผังจะได้ไม่ค้างครึ่งๆ กลางๆ

### Batch

ใช้เมื่อต้องรัน query เดิมหลายครั้งด้วยค่าต่างกัน แล้วอยากส่งไป DB ในรอบเดียว:

```sql
-- name: BumpEventVersion :batchexec
UPDATE events SET version = version + 1, updated_by = @actor
WHERE event_id = @event_id;
```

ถ้าเป็น INSERT ล้วนๆ จำนวนมาก ให้ใช้ `:copyfrom` จะเร็วกว่า

## ใช้ query ใน transaction

query ทุกตัวที่ sqlc สร้างใช้ใน transaction ได้ผ่าน `WithTx`:

```go
err := pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error {
	q := store.New(pool).WithTx(tx)
	n, err := q.UpdateEventTitle(ctx, params)
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrEventConflict
	}
	return q.InsertOutbox(ctx, outboxParams) // อยู่ใน tx เดียวกัน
})
```

`BeginFunc` จะ commit ให้เมื่อ function คืน `nil` และ rollback ให้เมื่อคืน error

งานที่ต้องแก้หลายตารางพร้อมกัน (เช่น แก้ event + บวก version + เขียน outbox) ให้รวมไว้ในชั้น repository (`internal/postgres`) ไม่ให้ service เป็นคนเปิด transaction เอง

## เมื่อ sqlc ไม่พอ

ลองทุกวิธีข้างบนก่อน ส่วนใหญ่ sqlc ทำได้ กรณีที่ควรเขียน SQL เองมีไม่กี่แบบ:

- **WHERE หรือ ORDER BY เปลี่ยนไปตามที่ผู้ใช้เลือก** เช่น หน้าค้นหาที่มี filter หลายตัวและเลือกการเรียงได้หลายแบบ ถ้าใช้ `narg` จะได้ SQL ที่อ่านยาก และ Postgres อาจเลือก index ได้ไม่ดี
- **SQL ที่ sqlc parse ไม่ได้** ซึ่งเจอไม่บ่อย

ทางเลือกก่อนเขียนเอง: ย้ายความซับซ้อนไปเป็น view หรือ function ใน migration ซึ่ง sqlc อ่านได้ แล้วเขียน query ธรรมดาเรียกมันอีกที

ถ้าต้องเขียนเองจริงๆ:

- **เขียนในชั้น repository (`internal/postgres`) ไม่ใช่ใน `internal/store`** เพื่อให้ `internal/store` เป็นโค้ดที่ generate ล้วนๆ
- **ใส่ค่าทุกค่าผ่าน `$1, $2, ...` เสมอ** ห้ามใช้ `fmt.Sprintf` เอาค่าจากผู้ใช้ไปต่อเป็น SQL เพราะจะโดน SQL injection
- **ชื่อคอลัมน์ใน `ORDER BY` ต้องมาจาก map ที่เรากำหนดเอง** เช่น `map[string]string{"newest": "event_id DESC", "title": "title"}` ห้ามเอาชื่อคอลัมน์จาก request มาใส่ตรงๆ
- **ใช้ struct เดิมของ `store` ได้** ผ่าน `pgx.CollectRows(rows, pgx.RowToStructByName[store.Event])` แต่ต้องเปิด `emit_db_tags: true` ใน `sqlc.yaml` ก่อน
- **ต้องมี integration test เสมอ** เพราะไม่มี sqlc ช่วยตรวจตอน generate แล้ว

## การทดสอบ

query ทุกตัวควรมี integration test ที่รันกับ Postgres จริงผ่าน testcontainers (build tag `integration`) อย่า mock DB เพราะสิ่งที่ต้องทดสอบคือ SQL เอง เช่น:

- เงื่อนไข `organizer_id` กันข้อมูลของ organizer คนอื่นได้จริงไหม (Get ด้วย organizer อื่นต้องได้ `pgx.ErrNoRows`)
- `ORDER BY` และการแบ่งหน้าคืนลำดับถูกไหม
- `narg` ที่เป็น NULL ไม่กรองจริงไหม
- `:execrows` คืน 0 เมื่อ version ไม่ตรงไหม
- constraint ใน DB ปฏิเสธข้อมูลผิดจริงไหม

รัน:

```sh
go test -tags integration ./internal/store/...
```

## ตรวจว่าโค้ดตรงกับ SQL

```sh
sqlc diff
```

คำสั่งนี้ไม่เขียนไฟล์ แต่จะแสดง diff ถ้าโค้ดใน `internal/store/` ไม่ตรงกับที่ sqlc ควรสร้าง เช่น ลืม generate หลังแก้ query หรือมีคนแก้ไฟล์ generate ด้วยมือ ควรใส่ไว้ใน CI ด้วย

## Checklist ก่อน commit

- [ ] query กรองด้วย `organizer_id` ถ้าเป็นข้อมูลของ organizer
- [ ] INSERT/UPDATE ใส่ `@actor` ให้ `created_by` / `updated_by`
- [ ] UPDATE ของ events ตรวจและบวก `version`
- [ ] `:many` มี `ORDER BY`
- [ ] คอลัมน์ที่คำนวณมี `AS` ตั้งชื่อ
- [ ] รัน `sqlc generate` แล้ว และ `sqlc diff` ไม่มีผลต่าง
- [ ] มี integration test และผ่าน

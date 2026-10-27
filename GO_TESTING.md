# แนวทางการเขียน test ใน Go

test ของ service ที่เขียนด้วย Go ใช้แพ็กเกจ `testing` ของ standard library อย่างเดียว เช็กผลด้วย `if` แล้วรายงานด้วย `t.Errorf` / `t.Fatalf` ไม่ใช้ assertion library เช่น testify

เอกสารนี้อธิบายว่าทำไมถึงเลือกแบบนี้ และกติกาที่ test ทุกไฟล์ใช้ร่วมกัน ตัวอย่างทั้งหมดมาจาก [venue_test.go](services/catalog/internal/venue/venue_test.go)

## ทำไมไม่ใช้ assertion library

Go ไม่มี assertion ทั้งในตัวภาษาและใน standard library ทีม Go ตั้งใจออกแบบให้เป็นแบบนี้ (ดู [Go FAQ](https://go.dev/doc/faq#assertions) และ [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments#assert-libraries)) โปรเจกต์นี้ทำตามด้วยเหตุผล 3 ข้อ

1. **test เป็นโค้ด Go ธรรมดา** ใช้ `if`, `!=`, `errors.Is` ชุดเดียวกับที่ใช้เขียนโค้ดจริง ไม่ต้องจำ API ของ library เพิ่ม (testify มี assertion หลายสิบฟังก์ชัน)
2. **ข้อความตอน fail ต้องเขียนเอง** จึงบอกบริบทได้ตรงจุด เช่น `CreateVenue was called 0 times, want 1` อ่านแล้วรู้เลยว่าเรียกอะไร ได้อะไร และต้องการอะไร
3. **เลือกได้เองว่าจะหยุดหรือไปต่อ** ทุกจุดที่เช็ก (ดู [`t.Errorf` กับ `t.Fatalf`](#terrorf-กับ-tfatalf))

อีกเหตุผลสำหรับ repo นี้คือใช้เรียน Go การเขียนแบบ standard library ทำให้เห็นว่า assertion จริงๆ ก็แค่ `if` + `t.Errorf` วันหลังถ้าไปทำงานกับทีมที่ใช้ testify ก็ debug ได้ เพราะรู้ว่าข้างในทำอะไร

### เทียบกับ testify

```go
// standard library (แบบที่ใช้ในโปรเจกต์นี้)
calls := q.CreateVenueCalls()
if len(calls) != 1 {
	t.Fatalf("CreateVenue was called %d times, want 1", len(calls))
}
if got := calls[0].Arg; got != want {
	t.Errorf("CreateVenue arg = %+v, want %+v", got, want)
}

// testify
calls := q.CreateVenueCalls()
require.Len(t, calls, 1)
assert.Equal(t, want, calls[0].Arg)
```

|                       | standard library                | testify                                                                                       |
| --------------------- | ------------------------------- | --------------------------------------------------------------------------------------------- |
| ความยาว               | ยาวกว่า                         | สั้นกว่า                                                                                      |
| ข้อความตอน fail       | เขียนเอง บอกบริบทได้ตรงจุด      | มีให้อัตโนมัติ มี diff ของ struct แต่บอกบริบทน้อย                                             |
| สิ่งที่ต้องเรียนเพิ่ม | ไม่มี                           | API ของ library                                                                               |
| ข้อผิดพลาดที่พบบ่อย   | ลืมเขียนข้อความ หรือเขียนไม่ครบ | สลับ `want` กับ `got` ใน `assert.Equal` แล้ว compile ผ่าน แต่ข้อความ expected/actual กลับด้าน |

testify เป็น library ที่ใช้กันแพร่หลายและไม่ได้ผิด แค่โปรเจกต์นี้เลือกใช้ standard library

> testify มีอยู่ใน `go.mod` ของ catalog แบบ `// indirect` เพราะ dependency อื่นดึงเข้ามา ไม่ได้แปลว่าใช้ได้ ห้าม import ใน test

### เมื่อเทียบ struct แล้วยาวเกินไป

ข้อเสียที่เห็นชัดที่สุดของแบบ standard library คือการเทียบ struct ทีละช่อง ถ้าเทียบทั้ง struct ด้วย `!=` ได้ ให้ทำแบบนั้นก่อน ถ้าทำไม่ได้ (struct มี slice หรือ map อยู่ข้างใน) หรืออยากเห็น diff ว่าช่องไหนต่าง ให้พิจารณา [go-cmp](https://github.com/google/go-cmp) ก่อนจะไปใช้ testify เพราะแก้แค่เรื่องการเทียบ โดยที่ส่วนอื่นยังเป็นโค้ด Go ธรรมดา

```go
if diff := cmp.Diff(want, got); diff != "" {
	t.Errorf("Create returned venue mismatch (-want +got):\n%s", diff)
}
```

ตอนนี้ยังไม่ได้เพิ่ม go-cmp ใน `go.mod`

## กติกา

### `t.Errorf` กับ `t.Fatalf`

- **`t.Errorf`** บันทึกว่า fail แล้วทำต่อ ใช้เป็นค่าเริ่มต้น จะได้เห็นทุกจุดที่ผิดในรอบเดียว
- **`t.Fatalf`** บันทึกว่า fail แล้วหยุด subtest ทันที ใช้เมื่อบรรทัดถัดไปทำงานต่อไม่ได้ถ้าเงื่อนไขนี้ไม่ผ่าน

```go
calls := q.CreateVenueCalls()
if len(calls) != 1 {
	// ต้องหยุด เพราะบรรทัดถัดไปอ่าน calls[0] จะ panic ถ้า slice ว่าง
	t.Fatalf("CreateVenue was called %d times, want 1", len(calls))
}
if got := calls[0].Arg; got != want {
	t.Errorf("CreateVenue arg = %+v, want %+v", got, want)
}
```

อย่ารวมหลายเงื่อนไขไว้ใน `if` เดียว เช่น `if err == nil || errors.Is(err, venue.ErrInvalid)` เพราะตอน fail จะไม่รู้ว่าเป็นกรณีไหน ให้แยกเป็น `if` ละเงื่อนไข

### ข้อความตอน fail

รูปแบบคือ `<สิ่งที่เรียก> returned <ค่า> = <ที่ได้>, want <ที่ต้องการ>`

```go
t.Errorf("Create returned err = %v, want ErrInvalid", err)
t.Errorf("CreateVenue was called %d times, want 0", n)
```

- ใส่ค่าที่**ได้จริง**ไว้ในข้อความเสมอ ไม่ใช่แค่บอกว่าผิด
- เทียบ struct ให้ใช้ `%+v` ซึ่งแสดงชื่อช่องด้วย จะเห็นว่าช่องไหนผิด

### เช็ก error

- ใช้ `errors.Is(err, venue.ErrInvalid)` ไม่ใช้ `err == venue.ErrInvalid` เพราะ service ห่อ error ด้วย `fmt.Errorf("%w: ...")` ตัว error ที่ได้จึงไม่ใช่ตัวเดียวกับ sentinel
- ถ้า service ต้องส่ง error ของ dependency ต่อขึ้นไป ให้เช็กทั้ง 2 ด้าน คือต้องห่อ error เดิมไว้ และต้องไม่กลายเป็น error ของ domain ผิดตัว

```go
if !errors.Is(err, dbErr) {
	t.Fatalf("Create returned err = %v, want it to wrap %v", err, dbErr)
}
if errors.Is(err, venue.ErrInvalid) {
	t.Errorf("Create returned err = %v, must not be ErrInvalid", err)
}
```

### table-driven test และ subtest

กรณีที่ต่างกันแค่ input แต่ผลที่ต้องการเหมือนกัน ให้เขียนเป็นตารางแล้ววนด้วย `t.Run` ตาม `TestCreate_Invalid`

```go
tests := []struct {
	name string
	in   venue.CreateInput
}{
	{"EmptyName", venue.CreateInput{Name: "", Address: "a", Timezone: "Asia/Bangkok"}},
	{"BlankName", venue.CreateInput{Name: "   ", Address: "a", Timezone: "Asia/Bangkok"}},
}
for _, tt := range tests {
	t.Run(tt.name, func(t *testing.T) { /* ... */ })
}
```

ตั้งชื่อ subtest เป็น CamelCase ไม่มีช่องว่าง จะได้รันเฉพาะกรณีได้ด้วย `go test -run 'TestCreate_Invalid/EmptyName'`

### ค่าใน fixture ต้องไม่ซ้ำกัน

ข้อมูลที่ mock คืนมาควรต่างจาก input และต่างกันเองทุกช่อง ไม่อย่างนั้น test จะจับไม่ได้ถ้าโค้ดเอาค่าผิดที่มาใช้

```go
row := store.Venue{
	OrganizerID: "org-from-db",     // ต่างจาก actor.OrganizerID
	Name:        "Inserted Name",   // ต่างจาก input
	CreatedBy:   "creator-from-db",
	UpdatedBy:   "updater-from-db", // ต่างจาก CreatedBy จึงจับได้ถ้าโค้ดใส่สลับช่อง
	// ...
}
```

- เวลาให้ใช้ `time.Date(...)` เป็นค่าคงที่ ห้ามใช้ `time.Now()` เพราะผลจะเปลี่ยนทุกครั้งที่รัน
- ถ้าต้องการพิสูจน์ว่า id มาจาก DB ให้เทียบว่าเท่ากับค่าที่ mock คืน ไม่ใช่แค่เช็กว่าไม่ใช่ `uuid.Nil`

### mock ด้วย moq

mock ของ interface สร้างด้วย [moq](https://github.com/matryer/moq) ผ่านบรรทัด `//go:generate` ในไฟล์ของ package นั้น ไฟล์ที่ได้ลงท้ายด้วย `_moq_test.go` จึงไม่ถูกรวมเข้า binary

```bash
cd services/catalog
go generate ./internal/venue/
```

- mock จะ **panic** ถ้าถูกเรียก method ที่ไม่ได้ตั้ง `XxxFunc` ไว้ test ที่ต้องการให้ไม่เรียก DB เลย (เช่นตอน input ไม่ถูกต้อง) จึงไม่ต้องตั้ง Func เลย ถ้าโค้ดเผลอเรียก test จะพังให้เห็นทันที
- เช็กว่าเรียกกี่ครั้งและส่งอะไรไปด้วย `q.XxxCalls()`

### unit test กับ integration test

|            | unit test                                          | integration test                              |
| ---------- | -------------------------------------------------- | --------------------------------------------- |
| ทดสอบอะไร  | logic ของ service เช่น validation และการแปลงข้อมูล | query จริงกับ Postgres ที่รันใน container     |
| dependency | mock ด้วย moq                                      | Postgres จริง                                 |
| build tag  | ไม่มี                                              | บรรทัดแรกของไฟล์เป็น `//go:build integration` |
| ตัวอย่าง   | `internal/venue/venue_test.go`                     | `internal/store/venues_test.go`               |

```bash
make test SVC=catalog              # เฉพาะ unit test
make test-integration SVC=catalog  # unit test และ integration test
```

ไฟล์ test อยู่ใน package `<pkg>_test` (เช่น `venue_test`) เพื่อทดสอบผ่าน API ที่ export เท่านั้น เหมือนที่โค้ดภายนอกเรียกใช้

### TDD

เขียน test ทีละเงื่อนไข และ commit แยกเป็นขั้น

1. `test: …` เพิ่ม test ที่ compile ผ่านแต่ fail ที่ assertion
2. `feat: …` หรือ `fix: …` เขียนโค้ดให้ผ่านเท่าที่จำเป็น
3. `refactor: …` จัดโค้ดให้ดีขึ้นโดยไม่เปลี่ยน behavior (ข้ามได้ถ้าไม่มีอะไรต้องแก้)

prefix ของ commit บอกว่าแก้อะไร commit ที่แก้แค่ไฟล์ test ใช้ `test:` เสมอ แม้จะเป็นการแก้ test เพื่อจับ bug ก็ตาม

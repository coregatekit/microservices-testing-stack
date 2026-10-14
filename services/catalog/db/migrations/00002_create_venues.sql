-- +goose Up
-- ตารางแม่สุดของกลุ่มสถานที่ ไม่มี FK ไปหาตารางอื่น จึงสร้างเป็นตารางแรก
CREATE TABLE
    venues (
        -- uuidv7 เรียงตามเวลา ค่าใหม่ต่อท้าย index เสมอ ไม่กระจายแบบ v4 ที่ทำให้ B-tree แตกหน้าบ่อย
        venue_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        -- ไม่มี FK เพราะ organizer อยู่ใน Keycloak คนละระบบ database ตรวจข้ามระบบไม่ได้
        -- ใช้ text แทน uuid เผื่อเปลี่ยน identity provider ที่ id ไม่ใช่ UUID
        organizer_id text NOT NULL,
        -- ทุกคอลัมน์ NOT NULL ไว้ก่อน ผ่อนให้ว่างได้ทีหลังง่าย แต่เพิ่ม NOT NULL ตอนมีข้อมูลแล้ว
        -- ต้องไล่เติมข้อมูลเก่าให้ครบก่อน
        name text NOT NULL,
        address text NOT NULL,
        -- ไว้แสดงเวลารอบตามเวลาท้องถิ่นของสถานที่ เช่น Asia/Bangkok
        -- ไม่มี CHECK เพราะ CHECK ต้องเป็น immutable ค้นในรายชื่อ timezone ของระบบไม่ได้
        -- service จึงต้องตรวจเองว่าเป็นชื่อ timezone ที่มีอยู่จริง
        timezone text NOT NULL,
        -- เวลาให้ database ใส่เอง (updated_at ใช้ trigger) ส่วนผู้สร้าง/ผู้แก้ไม่มี DEFAULT
        -- เพราะ service ต่อ DB ด้วย catalog_service เสมอ DB จึงไม่รู้ว่าผู้ใช้จริงคือใคร
        -- ถ้า service ลืมส่ง INSERT จะ error ทันที แทนที่จะได้แถวที่ไม่รู้ว่าใครสร้าง
        created_at timestamptz NOT NULL DEFAULT now (),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now (),
        updated_by text NOT NULL
    );

-- Postgres สร้าง index ให้อัตโนมัติแค่ PK กับ UNIQUE คอลัมน์ที่ใช้กรองต้องสร้างเอง
-- query ที่ใช้บ่อยคือ "สถานที่ของ organizer คนนี้"
CREATE INDEX venues_organizer_id_idx ON venues (organizer_id);

-- BEFORE เพราะต้องแก้ค่าใน NEW ก่อนแถวถูกเขียนลง disk ถ้าเป็น AFTER แถวถูกบันทึกไปแล้ว
CREATE TRIGGER venues_set_updated_at BEFORE
UPDATE ON venues FOR EACH ROW EXECUTE FUNCTION set_updated_at ();

-- +goose Down
-- ไม่ต้อง DROP INDEX หรือ TRIGGER เพราะหายไปพร้อมตาราง
DROP TABLE venues;

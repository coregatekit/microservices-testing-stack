-- +goose Up
CREATE TABLE
    seat_maps (
        -- uuidv7 เรียงตามเวลา ค่าใหม่ต่อท้าย index เสมอ ไม่กระจายแบบ v4 ที่ทำให้ B-tree แตกหน้าบ่อย
        seat_map_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        -- RESTRICT: ห้ามลบ venue ที่ยังมีผัง ถ้าใช้ CASCADE ผังที่ showtime ใช้อยู่จะหายตาม
        -- และตั๋วที่ขายไปแล้วจะชี้ไปที่เก้าอี้ที่ไม่มีอยู่จริง
        -- ไม่ต้องสร้าง index แยกให้ venue_id เพราะ UNIQUE (venue_id, version) ด้านล่างใช้แทนได้
        venue_id uuid NOT NULL REFERENCES venues (venue_id) ON DELETE RESTRICT,
        -- ผังแก้ไม่ได้หลังล็อก การเปลี่ยนผังจึงต้องคัดลอกเป็นรุ่นใหม่ เลขรุ่นใช้แยกแต่ละแบบ
        version integer NOT NULL CHECK (version > 0),
        -- ใช้ text + CHECK แทน ENUM เพราะ ENUM ลบหรือเปลี่ยนชื่อค่าไม่ได้
        -- ส่วน CHECK ลบแล้วสร้างใหม่ได้ใน migration เดียว
        status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'LOCKED')),
        -- ว่างได้เพราะผัง DRAFT ยังไม่ถูกล็อก ความสัมพันธ์กับ status บังคับด้วย CHECK ด้านล่าง
        locked_at timestamptz,
        -- เวลาให้ database ใส่เอง (updated_at ใช้ trigger) ส่วนผู้สร้าง/ผู้แก้ไม่มี DEFAULT
        -- เพราะ service ต่อ DB ด้วย catalog_service เสมอ DB จึงไม่รู้ว่าผู้ใช้จริงคือใคร
        -- ถ้า service ลืมส่ง INSERT จะ error ทันที แทนที่จะได้แถวที่ไม่รู้ว่าใครสร้าง
        created_at timestamptz NOT NULL DEFAULT now (),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now (),
        updated_by text NOT NULL,
        -- สถานที่เดียวกันมีผังแบบที่ 1 ได้แบบเดียว แต่สถานที่อื่นมีแบบที่ 1 ของตัวเองได้
        UNIQUE (venue_id, version),
        -- ดูซ้ำซ้อนกับ PK แต่จำเป็น: showtimes จะใช้ FOREIGN KEY (seat_map_id, venue_id)
        -- เพื่อบังคับว่าผังที่เลือกต้องเป็นของสถานที่เดียวกับรอบ และ Postgres กำหนดว่า
        -- คอลัมน์ปลายทางของ FK ต้องมี UNIQUE ที่ตรงกันทุกคอลัมน์
        UNIQUE (seat_map_id, venue_id),
        -- LOCKED ⇔ มี locked_at กันข้อมูลขัดกันเอง เช่น LOCKED แต่ไม่รู้ว่าล็อกเมื่อไร
        -- ตั้งชื่อเองเพราะชื่ออัตโนมัติ (seat_maps_check) อ่านจาก error แล้วไม่รู้ว่าผิดกฎข้อไหน
        CONSTRAINT seat_maps_locked_at_matches_status CHECK ((status = 'LOCKED') = (locked_at IS NOT NULL))
    );

-- BEFORE เพราะต้องแก้ค่าใน NEW ก่อนแถวถูกเขียนลง disk ถ้าเป็น AFTER แถวถูกบันทึกไปแล้ว
CREATE TRIGGER seat_maps_set_updated_at BEFORE
UPDATE ON seat_maps FOR EACH ROW EXECUTE FUNCTION set_updated_at ();

-- กฎ "ผัง LOCKED ห้ามแก้หรือปลดล็อก" (seat_map_locked) อยู่ใน 00010
-- เพราะต้องตรวจข้ามไปที่ seat_map_sections และ seat_map_seats ด้วย
-- seat_map_sections และ seat_map_seats ด้วย จะทำเป็น migration แยกหลังสร้างสองตารางนั้น
-- +goose Down
DROP TABLE seat_maps;
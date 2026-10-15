-- +goose Up
-- ตารางเดียวที่เชื่อมกลุ่มงานกับกลุ่มสถานที่ จึงต้องสร้างหลัง events และ seat_maps
CREATE TABLE
    showtimes (
        -- uuidv7 เรียงตามเวลา ค่าใหม่ต่อท้าย index เสมอ ไม่กระจายแบบ v4 ที่ทำให้ B-tree แตกหน้าบ่อย
        showtime_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        -- CASCADE: รอบเป็นส่วนหนึ่งของงาน ลบงานแล้วรอบต้องหายตาม
        -- (ลบงานได้เฉพาะตอนเป็นร่าง service ตรวจ จึงยังไม่มีตั๋วชี้มาที่รอบ)
        -- ไม่ต้องสร้าง index แยกให้ event_id เพราะ UNIQUE (event_id, starts_at) ด้านล่างใช้แทนได้
        event_id uuid NOT NULL REFERENCES events (event_id) ON DELETE CASCADE,
        -- ไม่มี FK ไป venues ตรงๆ เพราะ FK คู่ (seat_map_id, venue_id) ด้านล่างรับประกันอยู่แล้ว:
        -- คู่นี้ต้องมีใน seat_maps และ seat_maps.venue_id ก็มี FK ไป venues
        -- เก็บ venue_id ไว้ในรอบเพราะใช้บ่อยตอนแสดงผลและส่งให้ booking โดยไม่ต้อง JOIN ผัง
        venue_id uuid NOT NULL,
        seat_map_id uuid NOT NULL,
        -- timestamptz เก็บเป็น UTC แสดงเป็นเวลาท้องถิ่นด้วย venues.timezone
        -- กฎ "เวลาใหม่ต้องอยู่ในอนาคต" ใช้ CHECK ไม่ได้ เพราะ now() ไม่ใช่ immutable
        -- แถวที่ผ่านวันนี้จะกลายเป็นผิดในวันหน้า service จึงต้องตรวจตอนสร้างหรือเลื่อนรอบ
        starts_at timestamptz NOT NULL,
        ends_at timestamptz NOT NULL,
        -- เวลาให้ database ใส่เอง (updated_at ใช้ trigger) ส่วนผู้สร้าง/ผู้แก้ไม่มี DEFAULT
        -- เพราะ service ต่อ DB ด้วย catalog_service เสมอ DB จึงไม่รู้ว่าผู้ใช้จริงคือใคร
        -- ถ้า service ลืมส่ง INSERT จะ error ทันที แทนที่จะได้แถวที่ไม่รู้ว่าใครสร้าง
        created_at timestamptz NOT NULL DEFAULT now (),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now (),
        updated_by text NOT NULL,
        -- FK คู่: บังคับว่าผังที่เลือกต้องเป็นของสถานที่เดียวกับรอบ
        -- ถ้า FK แค่ seat_map_id จะเก็บ venue_id ของ Hall A คู่กับผังของ Hall B ได้
        -- RESTRICT: ห้ามลบผังที่มีรอบใช้อยู่ ไม่งั้นตั๋วที่ขายไปจะชี้ไปที่เก้าอี้ที่ไม่มีจริง
        -- ตั้งชื่อเองเพราะชื่ออัตโนมัติยาวและไม่บอกว่ากฎนี้คือ "ผังต้องตรงกับสถานที่"
        CONSTRAINT showtimes_seat_map_venue_fkey FOREIGN KEY (seat_map_id, venue_id) REFERENCES seat_maps (seat_map_id, venue_id) ON DELETE RESTRICT,
        -- งานเดียวกันไม่มีสองรอบที่เริ่มพร้อมกัน แต่ต่างงานเริ่มเวลาเดียวกันได้
        CONSTRAINT showtimes_event_starts_at_key UNIQUE (event_id, starts_at),
        -- จบต้องหลังเริ่ม ถ้าเท่ากันก็คือรอบที่ไม่มีความยาว
        CONSTRAINT showtimes_ends_after_starts CHECK (ends_at > starts_at)
    );

-- ตอนลบผัง Postgres ต้องหาว่ามีรอบไหนใช้ผังนี้ (เพื่อเช็ก RESTRICT)
-- ไม่มี index นี้จะต้องอ่านทั้งตาราง showtimes ทุกครั้งที่ลบผัง
-- UNIQUE ด้านบนขึ้นต้นด้วย event_id จึงใช้แทนไม่ได้
CREATE INDEX showtimes_seat_map_id_idx ON showtimes (seat_map_id);

-- BEFORE เพราะต้องแก้ค่าใน NEW ก่อนแถวถูกเขียนลง disk ถ้าเป็น AFTER แถวถูกบันทึกไปแล้ว
CREATE TRIGGER showtimes_set_updated_at BEFORE
UPDATE ON showtimes FOR EACH ROW EXECUTE FUNCTION set_updated_at ();

-- +goose Down
DROP TABLE showtimes;
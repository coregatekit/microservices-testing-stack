-- +goose Up
CREATE TABLE
    seat_map_sections (
        -- CASCADE ต่างจาก venues → seat_maps ที่ใช้ RESTRICT เพราะโซนเป็นส่วนหนึ่งของผัง
        -- ไม่มีความหมายถ้าไม่มีผัง ลบผัง DRAFT ทิ้งก็ควรลบโซนตามไปด้วย
        -- ผังที่ใช้งานอยู่ลบไม่ได้อยู่แล้ว เพราะ showtimes จะ RESTRICT ไว้อีกชั้น
        seat_map_id uuid NOT NULL REFERENCES seat_maps (seat_map_id) ON DELETE CASCADE,
        -- booking เอารหัสโซนไปใช้ต่อและแสดงบนตั๋ว จึงบังคับรูปแบบ: ตัวพิมพ์ใหญ่/ตัวเลข/_/-
        -- ยาวไม่เกิน 16 ตัว ขึ้นต้นด้วยตัวอักษรหรือตัวเลข (กันค่าว่างไปในตัว)
        section_code text NOT NULL CHECK (section_code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
        name text NOT NULL,
        -- composite PK แทน uuid: โซนระบุตัวด้วย "ผังไหน + รหัสอะไร" อยู่แล้ว
        -- ทำให้ seat_map_seats ทำ FK (seat_map_id, section_code) มาที่นี่ได้
        -- ซึ่งบังคับว่าเก้าอี้ต้องอยู่ในโซนของผังเดียวกันกับตัวเอง ถ้าใช้ uuid จะบังคับข้อนี้ไม่ได้
        -- PK นี้สร้าง index ที่ขึ้นต้นด้วย seat_map_id ให้ จึงไม่ต้องสร้าง index แยกให้ FK
        PRIMARY KEY (seat_map_id, section_code)
    );

-- +goose Down
DROP TABLE seat_map_sections;

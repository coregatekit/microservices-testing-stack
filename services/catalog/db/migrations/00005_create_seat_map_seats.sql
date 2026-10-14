-- +goose Up
CREATE TABLE seat_map_seats (
    -- ไม่มี REFERENCES seat_maps ตรงๆ เพราะ FK ไปที่ seat_map_sections ด้านล่างครอบคลุมแล้ว
    -- (โซนต้องมีผังอยู่จริง เก้าอี้ต้องมีโซนอยู่จริง จึงได้ผังอยู่จริงไปด้วย)
    seat_map_id uuid NOT NULL,
    -- รหัสที่ระบบใช้ เช่น A-12 booking คัดลอกไปนับว่าตัวไหนว่าง จึงบังคับรูปแบบ
    seat_id text NOT NULL CHECK (seat_id ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
    section_code text NOT NULL,
    -- แถวกับเลขที่นั่งไว้ให้คนอ่าน แยกจาก seat_id เพราะรูปแบบที่แสดงแต่ละสถานที่ไม่เหมือนกัน
    row_label text NOT NULL CHECK (row_label <> ''),
    seat_number integer NOT NULL CHECK (seat_number > 0),
    -- PK ขึ้นต้นด้วย seat_map_id จึงใช้กับ query "เก้าอี้ทั้งหมดของผังนี้" ที่ booking เรียกตอนเปิดขายได้
    PRIMARY KEY (seat_map_id, seat_id),
    -- composite FK: บังคับว่าโซนของเก้าอี้ต้องอยู่ในผังเดียวกับเก้าอี้เอง
    -- ถ้า FK แค่ section_code จะชี้ไปโซน A ของผังไหนก็ได้
    -- CASCADE เพราะเก้าอี้เป็นส่วนหนึ่งของโซน ลบผัง → ลบโซน → ลบเก้าอี้ ต่อกันเป็นทอด
    FOREIGN KEY (seat_map_id, section_code) REFERENCES seat_map_sections (seat_map_id, section_code) ON DELETE CASCADE,
    -- รวม section_code ด้วย เพราะสถานที่จริงมักมี "แถว A ที่ 12" ซ้ำกันในหลายโซน
    -- และเพราะขึ้นต้นด้วย (seat_map_id, section_code) จึงใช้เป็น index ของ FK ด้านบนได้
    -- ตั้งชื่อเองเพราะชื่ออัตโนมัติยาวเกิน 63 ตัวอักษร Postgres จะตัดท้ายทิ้ง
    CONSTRAINT seat_map_seats_position_key UNIQUE (seat_map_id, section_code, row_label, seat_number)
);

-- +goose Down
DROP TABLE seat_map_seats;

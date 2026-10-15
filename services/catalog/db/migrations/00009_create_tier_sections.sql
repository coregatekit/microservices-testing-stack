-- +goose Up
-- จับคู่โซนกับระดับราคาของงาน อยู่กลุ่มงานไม่ใช่กลุ่มสถานที่
-- เพราะผังเดียวกันใช้ได้หลายงาน งานหนึ่งให้โซน B เป็น VIP อีกงานให้เป็น REG ได้
-- ไม่มี audit columns เพราะผู้ใช้ไม่ได้แก้ทีละแถว ทั้งชุดถูกแก้ผ่านหน้าระดับราคาของงาน
CREATE TABLE
    tier_sections (
        -- ไม่มี FK ไป events ตรงๆ เพราะ FK คู่ (event_id, tier_code) ด้านล่างรับประกันอยู่แล้ว
        -- คู่นี้ต้องมีใน ticket_tiers ซึ่งมี FK ไป events อีกที
        event_id uuid NOT NULL,
        -- ไม่มี FK ไป seat_map_sections เพราะงานหนึ่งมีหลายรอบที่อาจใช้ผังต่างกัน
        -- ชื่อโซนเดียวจึงต้องชี้ไปได้หลายผังพร้อมกัน ซึ่ง FK ทำไม่ได้
        -- service ตรวจตอนประกาศงานว่าทุกโซนในทุกผังที่ใช้มีราคาครบ
        -- CHECK รูปแบบเดียวกับ seat_map_sections.section_code เพราะต้องเทียบกันได้ตรงตัว
        section_code text NOT NULL CHECK (section_code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
        -- ไม่ต้องใส่ CHECK รูปแบบซ้ำ เพราะ FK บังคับให้ต้องเป็นรหัสที่มีใน ticket_tiers อยู่แล้ว
        tier_code text NOT NULL,
        -- หนึ่งโซนได้ราคาเดียวในงานหนึ่ง แต่ระดับราคาหนึ่งครอบได้หลายโซน
        PRIMARY KEY (event_id, section_code),
        -- FK คู่: ระดับราคาต้องเป็นของงานเดียวกัน ถ้า FK แค่ tier_code จะชี้ไป VIP ของงานไหนก็ได้
        -- CASCADE: ลบระดับราคาแล้วการจับคู่ต้องหายตาม โซนนั้นจะกลับเป็น "ยังไม่มีราคา"
        -- ซึ่ง service จะจับได้ตอนกดประกาศ
        -- ไม่สร้าง index ให้ (event_id, tier_code) เพราะ PK ขึ้นต้นด้วย event_id อยู่แล้ว
        -- ตอนลบระดับราคา Postgres หาจาก event_id ได้ แล้วกรองแค่ไม่กี่โซนของงานนั้น
        FOREIGN KEY (event_id, tier_code) REFERENCES ticket_tiers (event_id, tier_code) ON DELETE CASCADE
    );

-- +goose Down
DROP TABLE tier_sections;

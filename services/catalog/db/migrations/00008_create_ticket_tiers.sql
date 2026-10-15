-- +goose Up
-- ระดับราคาของงาน ราคาเท่ากันทุกรอบของงาน จึงผูกกับ events ไม่ใช่ showtimes
CREATE TABLE
    ticket_tiers (
        -- CASCADE: ระดับราคาเป็นส่วนหนึ่งของงาน ลบงาน (ได้เฉพาะตอนร่าง) แล้วต้องหายตาม
        -- ไม่ต้องสร้าง index แยกให้ event_id เพราะ PK ด้านล่างขึ้นต้นด้วย event_id
        event_id uuid NOT NULL REFERENCES events (event_id) ON DELETE CASCADE,
        -- รหัสสั้นที่คนตั้งเอง เช่น VIP, REG ใช้ร่วมกับ event_id เป็น PK แทน uuid
        -- เพราะ tier_sections จะอ้างด้วย (event_id, tier_code) ทำให้ FK บังคับได้ว่า
        -- โซนต้องจับคู่กับระดับราคาของงานเดียวกันเท่านั้น
        -- CHECK รูปแบบเดียวกับ section_code เพราะ booking และ payment เก็บรหัสนี้ไปใช้ต่อ
        tier_code text NOT NULL CHECK (tier_code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
        -- ชื่อที่แสดงให้ลูกค้าเห็น เช่น "VIP Front Row" แก้ได้โดยไม่กระทบรหัส
        name text NOT NULL,
        -- เก็บเป็นหน่วยย่อยของสกุลเงิน (สตางค์) เป็นจำนวนเต็ม 5,000 บาท = 500000
        -- ไม่ใช้ numeric/float เพื่อไม่ให้มีปัญหาปัดทศนิยม และ payment provider ส่วนใหญ่รับหน่วยย่อย
        -- สกุลเงินอยู่ที่ events.currency ทุกระดับในงานเดียวกันจึงใช้สกุลเดียวกันเสมอ
        -- ต้องมากกว่า 0 เพราะ flow จองต้องผ่าน payment เสมอ ตั๋วราคา 0 จะค้างที่ขั้นจ่ายเงิน
        price_minor bigint NOT NULL CHECK (price_minor > 0),
        -- เวลาให้ database ใส่เอง (updated_at ใช้ trigger) ส่วนผู้สร้าง/ผู้แก้ไม่มี DEFAULT
        -- เพราะ service ต่อ DB ด้วย catalog_service เสมอ DB จึงไม่รู้ว่าผู้ใช้จริงคือใคร
        -- ถ้า service ลืมส่ง INSERT จะ error ทันที แทนที่จะได้แถวที่ไม่รู้ว่าใครสร้าง
        created_at timestamptz NOT NULL DEFAULT now(),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now(),
        updated_by text NOT NULL,
        -- งานเดียวกันมี VIP ได้แถวเดียว แต่งานอื่นมี VIP ของตัวเองได้
        PRIMARY KEY (event_id, tier_code)
    );
-- BEFORE เพราะต้องแก้ค่าใน NEW ก่อนแถวถูกเขียนลง disk ถ้าเป็น AFTER แถวถูกบันทึกไปแล้ว
CREATE TRIGGER ticket_tiers_set_updated_at BEFORE
UPDATE ON ticket_tiers FOR EACH ROW EXECUTE FUNCTION set_updated_at ();

-- +goose Down
DROP TABLE ticket_tiers;
-- +goose Up
-- ตารางแม่ของกลุ่มงาน (Events) ไม่มี FK ไปหาตารางอื่น จึงสร้างก่อน showtimes และ ticket_tiers
CREATE TABLE
    events (
        -- uuidv7 เรียงตามเวลา ค่าใหม่ต่อท้าย index เสมอ ไม่กระจายแบบ v4 ที่ทำให้ B-tree แตกหน้าบ่อย
        event_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        -- ไม่มี FK เพราะ organizer อยู่ใน Keycloak คนละระบบ เหมือน venues.organizer_id
        organizer_id text NOT NULL,
        title text NOT NULL,
        -- เดินหน้าอย่างเดียว ลำดับการเปลี่ยนสถานะ service เป็นคนตรวจ
        -- CHECK ตรวจได้แค่ค่าในแถวปัจจุบัน ไม่รู้ว่าก่อนหน้านี้เป็นสถานะอะไร
        status text NOT NULL DEFAULT 'DRAFT' CHECK (
            status IN (
                'DRAFT',
                'PUBLISHED',
                'ON_SALE',
                'SOLD_OUT',
                'SALES_CLOSED',
                'CANCELLED'
            )
        ),
        -- รหัส ISO 4217 เช่น THB ใช้ text + CHECK แทน char(3)
        -- เพราะ char(n) เติมช่องว่างท้ายให้เองแบบเงียบๆ ส่วน CHECK จะปฏิเสธ 'thb' หรือ 'TH' ทันที
        -- ตั๋วทุกระดับของงานใช้สกุลเงินเดียวกัน จึงเก็บไว้ที่งาน ไม่เก็บที่ ticket_tiers
        currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
        -- booking ใช้สองค่านี้ตัดสินว่ายังจองได้ไหม ถ้าข้อมูลผิด ลูกค้าจะจองได้นอกช่วงขาย
        sales_open_at timestamptz NOT NULL,
        sales_close_at timestamptz NOT NULL,
        -- smallint พอ (สูงสุด 32767) จำกัดต่อคนต่อรอบ ต้องมากกว่า 0 ไม่งั้นไม่มีใครซื้อได้
        max_tickets_per_user smallint NOT NULL CHECK (max_tickets_per_user > 0),
        -- บวก 1 ทุกครั้งที่ข้อมูลในกลุ่มงานเปลี่ยน รวมถึงตอน showtimes และ ticket_tiers เปลี่ยน
        -- service จึงต้องเป็นคนบวกใน transaction เดียวกัน (trigger ที่ events เห็นแค่การแก้ตารางนี้)
        -- booking ใช้ค่านี้ทิ้งจดหมายเก่าที่มาถึงช้า และ service ใช้กันสองคนแก้ทับกัน
        -- (UPDATE ... WHERE version = <ค่าที่อ่านมา>) bigint เพราะไม่มีวันลดลงและไม่ควรล้น
        version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
        -- ว่างได้เพราะงานส่วนใหญ่ไม่ถูกยกเลิก ความสัมพันธ์กับ status บังคับด้วย CHECK ด้านล่าง
        -- แยกจาก updated_* เพราะ updated_* จะถูกทับเมื่อมีการแก้ครั้งถัดไป
        cancelled_at timestamptz,
        cancelled_by text,
        cancelled_reason text,
        -- เวลาให้ database ใส่เอง (updated_at ใช้ trigger) ส่วนผู้สร้าง/ผู้แก้ไม่มี DEFAULT
        -- เพราะ service ต่อ DB ด้วย catalog_service เสมอ DB จึงไม่รู้ว่าผู้ใช้จริงคือใคร
        -- ถ้า service ลืมส่ง INSERT จะ error ทันที แทนที่จะได้แถวที่ไม่รู้ว่าใครสร้าง
        created_at timestamptz NOT NULL DEFAULT now(),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now(),
        updated_by text NOT NULL,
        -- ปิดขายต้องหลังเปิดขาย ถ้าเท่ากันก็ไม่มีช่วงให้ขาย
        CONSTRAINT events_sales_window_valid CHECK (sales_close_at > sales_open_at),
        -- CANCELLED ต้องมีครบ 3 ช่อง ส่วนสถานะอื่นต้องว่างทั้ง 3 ช่อง
        -- num_nonnulls นับช่องที่ไม่ว่าง จึงกันกรณีมีแค่บางช่องได้ด้วย เช่นยกเลิกแต่ไม่บอกเหตุผล
        CONSTRAINT events_cancelled_fields_match_status CHECK (
            num_nonnulls(cancelled_at, cancelled_by, cancelled_reason) = CASE
                WHEN status = 'CANCELLED' THEN 3
                ELSE 0
            END
        )
    );

-- query ที่ใช้บ่อยคือ "งานของ organizer คนนี้"
CREATE INDEX events_organizer_id_idx ON events (organizer_id);

-- BEFORE เพราะต้องแก้ค่าใน NEW ก่อนแถวถูกเขียนลง disk ถ้าเป็น AFTER แถวถูกบันทึกไปแล้ว
CREATE TRIGGER events_set_updated_at BEFORE UPDATE ON events
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE events;
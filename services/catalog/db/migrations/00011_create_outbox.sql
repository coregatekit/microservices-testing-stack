-- +goose Up
-- Transactional outbox: service เขียนจดหมายลงตารางนี้ใน transaction เดียวกับการเปลี่ยนข้อมูลงาน
-- "ข้อมูลเปลี่ยน" กับ "มีจดหมายรอส่ง" จึง commit หรือ rollback คู่กันเสมอ
-- ถ้าส่งเข้า NATS ตรงๆ อาจเกิดกรณีงานถูกยกเลิกแล้วแต่ข่าวไม่ถึง booking ทำให้ยังขายต่อ
-- จากนั้นตัวส่ง (publisher) หยิบจดหมายที่ยังไม่ส่งไปส่งเข้า NATS แล้วใส่ published_at
CREATE TABLE
    outbox (
        -- id ของจดหมาย ใช้เป็น Nats-Msg-Id ด้วย ให้ JetStream ตัดฉบับที่ส่งซ้ำ
        -- และให้ฝั่งรับเช็กว่าเคยรับแล้วหรือยัง เพราะตัวส่งอาจส่งซ้ำได้ (ส่งแล้วแต่ตายก่อนใส่ published_at)
        -- uuidv7 เรียงตามเวลา ตัวส่งจึง ORDER BY event_id เพื่อส่งตามลำดับที่เกิดได้
        -- และไม่ต้องมี created_at เพราะดึงเวลาจาก id ได้ด้วย uuid_extract_timestamp(event_id)
        event_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        -- id ของงาน (events.event_id) ไม่มี FK เพราะจดหมายคือบันทึกว่าเกิดอะไรขึ้นแล้ว
        -- ต้องเก็บไว้แม้งานจะถูกลบ และถ้ามี FK การลบงานจะติดเพราะยังมีจดหมายชี้อยู่
        aggregate_id uuid NOT NULL,
        -- ค่า events.version ตอนที่เกิดจดหมายนี้ ฝั่งรับใช้ทิ้งจดหมายเก่าที่มาถึงช้า
        -- (ถ้า version ที่ถืออยู่ใหม่กว่า ไม่ต้องทำอะไร)
        aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
        -- ใช้ text + CHECK แบบเดียวกับ status เพิ่มประเภทใหม่ต้องทำ migration
        -- ซึ่งดีกว่าปล่อยให้พิมพ์ผิดแล้วฝั่งรับไม่รู้จัก ฝั่งรับใช้ค่านี้เลือกว่าจะทำอะไร
        event_type text NOT NULL CHECK (
            event_type IN (
                'EventPublished',
                'SalesOpened',
                'ShowtimeRescheduled',
                'EventCancelled'
            )
        ),
        -- เนื้อจดหมายตามสัญญาของแต่ละ event_type ใช้ jsonb ไม่ใช่ json เพราะตรวจว่าเป็น JSON
        -- ที่ถูกต้องตอนเขียน และ query เข้าไปดูข้างในได้ตอน debug
        -- บังคับเป็น object เพราะสัญญาทุกประเภทเป็น object การเพิ่ม field ทีหลังจึงไม่ทำให้ฝั่งรับพัง
        payload jsonb NOT NULL CHECK (jsonb_typeof (payload) = 'object'),
        -- ว่าง = ยังไม่ได้ส่ง ตัวส่งใส่เวลาหลัง NATS ตอบรับแล้ว
        -- ไม่มี audit columns และ trigger updated_at เพราะไม่มีผู้ใช้แก้ตารางนี้
        -- และแถวถูกแก้แค่ครั้งเดียวตอนส่ง
        published_at timestamptz
    );

-- query หลักของตัวส่ง:
--   SELECT ... FROM outbox WHERE published_at IS NULL ORDER BY event_id LIMIT 100 FOR UPDATE SKIP LOCKED
-- partial index เก็บเฉพาะแถวที่ยังไม่ส่ง ตารางจะโตแค่ไหน index นี้ก็เล็กอยู่
-- เพราะปกติจดหมายรอส่งมีแค่ไม่กี่ฉบับ และเรียงตาม event_id ตรงกับ ORDER BY จึงไม่ต้อง sort
-- SKIP LOCKED ทำให้รันตัวส่งหลายตัวพร้อมกันได้โดยไม่หยิบฉบับเดียวกัน
CREATE INDEX outbox_unpublished_idx ON outbox (event_id)
WHERE
    published_at IS NULL;

-- +goose Down
DROP TABLE outbox;
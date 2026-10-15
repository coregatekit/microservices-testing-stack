-- +goose Up
-- กฎ seat_map_locked: ผังที่ LOCKED แล้วห้ามแก้ผัง โซน และเก้าอี้ ห้ามปลดล็อก และห้ามลบผัง
-- เพื่อให้ตั๋วที่ขายไปแล้วชี้ไปที่เก้าอี้ที่มีอยู่จริงเสมอ ถ้าอยากเปลี่ยนผังต้องคัดลอกเป็นรุ่นใหม่
-- ใช้ trigger เพราะ CHECK ดูได้แค่แถวตัวเอง ส่วนกฎนี้ต้องดูสถานะของผังซึ่งอยู่อีกตาราง
-- ตั้ง CONSTRAINT = 'seat_map_locked' ใน error ให้ service อ่านจาก error เหมือน constraint ปกติ
-- (pgx ได้จาก PgError.ConstraintName) และใช้ ERRCODE 55000 object_not_in_prerequisite_state
-- เพราะความหมายตรงที่สุด: ข้อมูลอยู่ในสถานะที่ทำสิ่งนี้ไม่ได้แล้ว

-- +goose StatementBegin
-- ใช้ร่วมกันระหว่าง trigger ของโซนและเก้าอี้
CREATE FUNCTION assert_seat_map_not_locked (p_seat_map_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
BEGIN
    -- FOR SHARE กันกรณีแย่งกัน: ถ้าอีก transaction กำลังล็อกผังนี้อยู่ คำสั่งนี้จะรอจนอีกฝั่ง commit
    -- แล้วอ่านสถานะล่าสุดใหม่ ถ้าไม่ล็อก ทั้งสองฝั่งต่างเห็น DRAFT แล้ว commit ผ่าน
    -- จะได้เก้าอี้ใหม่ในผังที่ล็อกแล้ว (FK ล็อกแถวแม่แบบ KEY SHARE ซึ่งไม่ขวางการ UPDATE status)
    -- ห้ามใส่ status = 'LOCKED' ใน WHERE เพราะแถวที่ยังเห็นเป็น DRAFT จะถูกกรองทิ้งก่อนล็อก
    SELECT status INTO v_status FROM seat_maps WHERE seat_map_id = p_seat_map_id FOR SHARE;
    -- ไม่เจอแถว (v_status เป็น NULL) คือผังถูกลบใน transaction นี้แล้ว เช่นตอน CASCADE
    -- จากการลบผัง DRAFT ให้ผ่านไป
    IF v_status = 'LOCKED' THEN
        RAISE EXCEPTION 'seat map % is locked', p_seat_map_id
            USING ERRCODE = 'object_not_in_prerequisite_state', CONSTRAINT = 'seat_map_locked';
    END IF;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
-- ดูแค่ OLD เพราะสิ่งที่ห้ามคือแตะผังที่ "เคย" ล็อก ส่วน DRAFT → LOCKED ยังทำได้
-- ห้ามทุกการแก้ ไม่ใช่แค่ status เพราะผังที่ล็อกต้องคงเดิมทั้งแถว
CREATE FUNCTION seat_maps_guard_locked () RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status = 'LOCKED' THEN
        RAISE EXCEPTION 'seat map % is locked', OLD.seat_map_id
            USING ERRCODE = 'object_not_in_prerequisite_state', CONSTRAINT = 'seat_map_locked';
    END IF;
    -- BEFORE trigger ต้องคืนแถว ถ้าคืน NULL Postgres จะข้ามแถวนั้นไปเงียบๆ
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
-- ฟังก์ชันเดียวใช้กับ seat_map_sections และ seat_map_seats เพราะทั้งคู่มีคอลัมน์ seat_map_id
-- UPDATE เช็กทั้ง OLD และ NEW กันการย้ายแถวออกจากผังที่ล็อก หรือย้ายเข้าไปในผังที่ล็อก
CREATE FUNCTION seat_map_children_guard_locked () RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM assert_seat_map_not_locked (OLD.seat_map_id);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM assert_seat_map_not_locked (NEW.seat_map_id);
        RETURN NEW;
    END IF;
    RETURN OLD;
END
$$;
-- +goose StatementEnd

-- BEFORE เพื่อปฏิเสธก่อนแถวถูกเขียน และ DELETE ด้วยเพราะ RESTRICT จาก showtimes
-- กันได้แค่ผังที่มีรอบใช้อยู่ ผังที่ล็อกแล้วแต่ยังไม่มีรอบก็ต้องห้ามลบเหมือนกัน
CREATE TRIGGER seat_maps_guard_locked BEFORE
UPDATE OR DELETE ON seat_maps FOR EACH ROW EXECUTE FUNCTION seat_maps_guard_locked ();

CREATE TRIGGER seat_map_sections_guard_locked BEFORE INSERT
OR UPDATE OR DELETE ON seat_map_sections FOR EACH ROW EXECUTE FUNCTION seat_map_children_guard_locked ();

CREATE TRIGGER seat_map_seats_guard_locked BEFORE INSERT
OR UPDATE OR DELETE ON seat_map_seats FOR EACH ROW EXECUTE FUNCTION seat_map_children_guard_locked ();

-- +goose Down
-- ลบ trigger ก่อน เพราะฟังก์ชันที่ trigger ยังใช้อยู่ลบไม่ได้
DROP TRIGGER seat_map_seats_guard_locked ON seat_map_seats;
DROP TRIGGER seat_map_sections_guard_locked ON seat_map_sections;
DROP TRIGGER seat_maps_guard_locked ON seat_maps;
DROP FUNCTION seat_map_children_guard_locked ();
DROP FUNCTION seat_maps_guard_locked ();
DROP FUNCTION assert_seat_map_not_locked (uuid);

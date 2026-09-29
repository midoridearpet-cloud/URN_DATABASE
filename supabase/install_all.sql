-- URN size recommender: paste entire file into Supabase SQL Editor and Run
-- Safe on shared project: only creates urn_* objects

-- ===== supabase\migrations\001_urn_schema.sql =====
-- Pet urn size recommender (safe to run on shared Supabase project)
-- Creates only urn_* objects; does not alter existing booking/ERP tables.

CREATE TABLE IF NOT EXISTS urn_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series VARCHAR(50) NOT NULL,
    size_label VARCHAR(20) NOT NULL,
    outer_height NUMERIC,
    outer_diameter NUMERIC,
    inner_diameter NUMERIC,
    inner_depth NUMERIC,
    usable_volume_ml INTEGER NOT NULL,
    shape_notes TEXT,
    is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (series, size_label)
);

CREATE TABLE IF NOT EXISTS urn_breed_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category VARCHAR(30) NOT NULL,
    breed_name VARCHAR(100) NOT NULL UNIQUE,
    base_ratio_ml_per_kg NUMERIC NOT NULL DEFAULT 130,
    min_head_diameter_cm NUMERIC NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 100,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS urn_system_factors (
    factor_key VARCHAR(50) PRIMARY KEY,
    factor_value NUMERIC NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS urn_recommendation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(100),
    category VARCHAR(50),
    breed VARCHAR(100),
    input_health_weight NUMERIC,
    input_leave_weight NUMERIC,
    input_age NUMERIC,
    is_powdered BOOLEAN,
    process_method VARCHAR(20),
    has_keepsakes BOOLEAN,
    calculated_volume_ml INTEGER,
    recommended_urn_ids JSONB,
    actual_fit_status VARCHAR(50),
    feedback_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_urn_breed_category ON urn_breed_configs (category, sort_order);
CREATE INDEX IF NOT EXISTS idx_urn_products_active ON urn_products (is_active, usable_volume_ml);

ALTER TABLE urn_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE urn_breed_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE urn_system_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE urn_recommendation_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS urn_products_public_read ON urn_products;
CREATE POLICY urn_products_public_read ON urn_products
    FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS urn_breed_configs_public_read ON urn_breed_configs;
CREATE POLICY urn_breed_configs_public_read ON urn_breed_configs
    FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS urn_system_factors_public_read ON urn_system_factors;
CREATE POLICY urn_system_factors_public_read ON urn_system_factors
    FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS urn_recommendation_logs_anon_insert ON urn_recommendation_logs;
CREATE POLICY urn_recommendation_logs_anon_insert ON urn_recommendation_logs
    FOR INSERT TO anon, authenticated WITH CHECK (true);

GRANT SELECT ON urn_products TO anon, authenticated;
GRANT SELECT ON urn_breed_configs TO anon, authenticated;
GRANT SELECT ON urn_system_factors TO anon, authenticated;
GRANT INSERT ON urn_recommendation_logs TO anon, authenticated;

CREATE OR REPLACE FUNCTION match_suitable_urns(
    p_breed_name VARCHAR,
    p_health_weight NUMERIC DEFAULT NULL,
    p_leave_weight NUMERIC DEFAULT NULL,
    p_is_powdered BOOLEAN DEFAULT FALSE,
    p_age NUMERIC DEFAULT NULL,
    p_process_method VARCHAR DEFAULT 'fire',
    p_has_keepsakes BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    product_id UUID,
    series VARCHAR,
    size_label VARCHAR,
    usable_volume_ml INTEGER,
    inner_diameter NUMERIC,
    fill_ratio NUMERIC,
    is_primary BOOLEAN,
    is_estimated BOOLEAN,
    warning_tag TEXT,
    calculated_volume_ml INTEGER,
    process_method VARCHAR
) AS $$
DECLARE
    v_base_weight NUMERIC;
    v_base_ratio NUMERIC;
    v_min_dia NUMERIC;
    v_method_ratio NUMERIC := 1.0;
    v_buffer_ratio NUMERIC := 1.10;
    v_age_ratio NUMERIC := 1.0;
    v_fill_cap NUMERIC := 0.85;
    v_target_volume NUMERIC;
    v_method VARCHAR;
BEGIN
    v_method := lower(coalesce(p_process_method, 'fire'));
    IF v_method NOT IN ('fire', 'water') THEN
        RAISE EXCEPTION 'process_method must be fire or water';
    END IF;

    IF p_health_weight IS NULL AND p_leave_weight IS NULL THEN
        RAISE EXCEPTION 'At least one of health_weight or leave_weight is required';
    END IF;

    -- Prefer healthy weight for skeleton size (covers both weight loss and edema)
    v_base_weight := coalesce(p_health_weight, p_leave_weight);

    SELECT b.base_ratio_ml_per_kg, b.min_head_diameter_cm
    INTO v_base_ratio, v_min_dia
    FROM urn_breed_configs b
    WHERE b.breed_name = p_breed_name;

    IF NOT FOUND THEN
        v_base_ratio := 130;
        v_min_dia := 8.0;
    END IF;

    IF v_method = 'water' THEN
        IF p_is_powdered THEN
            SELECT factor_value INTO v_method_ratio
            FROM urn_system_factors WHERE factor_key = 'water_powdered_ratio';
        ELSE
            SELECT factor_value INTO v_method_ratio
            FROM urn_system_factors WHERE factor_key = 'water_cremation_ratio';
        END IF;
    ELSE
        IF p_is_powdered THEN
            SELECT factor_value INTO v_method_ratio
            FROM urn_system_factors WHERE factor_key = 'powdered_ratio';
        ELSE
            v_method_ratio := 1.0;
        END IF;
    END IF;

    IF v_method_ratio IS NULL THEN
        v_method_ratio := CASE
            WHEN v_method = 'water' AND p_is_powdered THEN 0.45
            WHEN v_method = 'water' THEN 1.20
            WHEN p_is_powdered THEN 0.35
            ELSE 1.0
        END;
    END IF;

    IF p_has_keepsakes THEN
        SELECT factor_value INTO v_buffer_ratio
        FROM urn_system_factors WHERE factor_key = 'safety_buffer_keepsake';
        IF v_buffer_ratio IS NULL THEN v_buffer_ratio := 1.25; END IF;
    ELSE
        SELECT factor_value INTO v_buffer_ratio
        FROM urn_system_factors WHERE factor_key = 'safety_buffer_default';
        IF v_buffer_ratio IS NULL THEN v_buffer_ratio := 1.10; END IF;
    END IF;

    IF p_age IS NOT NULL AND p_age < 1 THEN
        SELECT factor_value INTO v_age_ratio
        FROM urn_system_factors WHERE factor_key = 'age_juvenile_ratio';
        IF v_age_ratio IS NULL THEN v_age_ratio := 0.80; END IF;
    ELSIF p_age IS NOT NULL AND p_age >= 8 AND p_is_powdered THEN
        SELECT factor_value INTO v_age_ratio
        FROM urn_system_factors WHERE factor_key = 'age_senior_powdered_ratio';
        IF v_age_ratio IS NULL THEN v_age_ratio := 0.90; END IF;
    END IF;

    SELECT factor_value INTO v_fill_cap
    FROM urn_system_factors WHERE factor_key = 'safety_fill_cap';
    IF v_fill_cap IS NULL THEN v_fill_cap := 0.85; END IF;

    v_target_volume := round(
        v_base_weight * v_base_ratio * v_method_ratio * v_age_ratio * v_buffer_ratio
    );

    RETURN QUERY
    SELECT
        u.id,
        u.series,
        u.size_label,
        u.usable_volume_ml,
        u.inner_diameter,
        round((v_target_volume / u.usable_volume_ml)::numeric, 2) AS fill_ratio,
        (
            round((v_target_volume / u.usable_volume_ml)::numeric, 2) BETWEEN 0.55 AND v_fill_cap
        ) AS is_primary,
        u.is_estimated,
        CASE
            WHEN NOT p_is_powdered AND u.inner_diameter < v_min_dia
                THEN '瓶口偏窄，未磨粉放入頭骨風險較高'
            WHEN u.series = '極光' AND NOT p_is_powdered
                THEN '極光系列罐口較窄，未磨粉請特別留意'
            WHEN u.is_estimated
                THEN '容量為推估值，建議再向店家確認'
            WHEN round((v_target_volume / u.usable_volume_ml)::numeric, 2) > 0.75
                THEN '接近容量上限，若骨骸較鬆散建議大一號'
            ELSE '空間適宜'
        END AS warning_tag,
        v_target_volume::integer AS calculated_volume_ml,
        v_method::varchar AS process_method
    FROM urn_products u
    WHERE u.is_active = TRUE
      AND (u.usable_volume_ml * v_fill_cap) >= v_target_volume
      AND (p_is_powdered = TRUE OR u.inner_diameter >= v_min_dia)
    ORDER BY u.usable_volume_ml ASC, u.series ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION match_suitable_urns(
    VARCHAR, NUMERIC, NUMERIC, BOOLEAN, NUMERIC, VARCHAR, BOOLEAN
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';


-- ===== supabase\seed\002_urn_factors.sql =====
INSERT INTO urn_system_factors (factor_key, factor_value, description) VALUES
('powdered_ratio', 0.35, '火化磨粉後的體積倍率'),
('water_cremation_ratio', 1.20, '水化未磨粉的體積倍率'),
('water_powdered_ratio', 0.45, '水化磨粉後的體積倍率'),
('safety_buffer_default', 1.10, '一般安全容積緩衝（保留約10%）'),
('safety_buffer_keepsake', 1.25, '放置陪葬品或防潮包的緩衝（保留約25%）'),
('age_juvenile_ratio', 0.80, '幼年（未滿1歲）骨骼未完全鈣化倍率'),
('age_senior_powdered_ratio', 0.90, '高齡（8歲以上）且磨粉時的脆化倍率'),
('safety_fill_cap', 0.85, '可用容量安全填充上限（不可裝超過此比例）')
ON CONFLICT (factor_key) DO UPDATE
SET factor_value = EXCLUDED.factor_value,
    description = EXCLUDED.description;


-- ===== supabase\seed\003_urn_products.sql =====
-- Sourced from 骨灰罐尺寸測量.xlsx
-- 白陶 6/7 寸 volumes are Gemini geometric estimates (Excel still marked unmeasurable)

TRUNCATE TABLE urn_products;

INSERT INTO urn_products (
    series, size_label, outer_height, outer_diameter, inner_diameter, inner_depth,
    usable_volume_ml, shape_notes, is_estimated, is_active
) VALUES
('美濃燒', '2寸', 6.7, 6.3, 5.7, 5.5, 50, '蓋深1.6cm', FALSE, TRUE),
('美濃燒', '2.5寸', 8.1, 7.6, 6.7, 6.5, 110, '蓋深2cm', FALSE, TRUE),
('美濃燒', '3寸', 10.0, 9.6, 8.7, 8.1, 275, '蓋深2cm', FALSE, TRUE),
('美濃燒', '4寸', 13.0, 12.5, 12.1, 11.0, 700, '蓋深2.5cm', FALSE, TRUE),
('美濃燒', '5寸', 17.5, 15.0, 14.3, 13.5, 1400, '蓋深2.5cm', FALSE, TRUE),
('白陶', '2寸', 7.0, 6.0, 5.4, 5.0, 70, '平蓋無深度', FALSE, TRUE),
('白陶', '2.3寸', 8.8, 7.0, 6.4, 6.4, 150, '平蓋無深度', FALSE, TRUE),
('白陶', '3寸', 11.0, 9.0, 8.5, 8.0, 350, '平蓋無深度', FALSE, TRUE),
('白陶', '3.5寸', 12.5, 10.5, 9.2, 9.5, 580, '平蓋無深度', FALSE, TRUE),
('白陶', '4寸', 14.5, 12.0, 11.4, 10.3, 830, '平蓋無深度', FALSE, TRUE),
('白陶', '5寸', 18.5, 15.0, 14.2, 13.5, 1890, '平蓋無深度', FALSE, TRUE),
('白陶', '6寸', 20.0, 18.0, 17.2, 14.5, 3000, '平蓋；容量為幾何推估值', TRUE, TRUE),
('白陶', '7寸', 25.5, 21.0, 20.2, 19.0, 5400, '平蓋；容量為幾何推估值', TRUE, TRUE),
('小房子', 'S', 9.0, 7.5, 4.9, 5.4, 150, '罐口圓形, 內部為方形, 蓋深1.4cm', FALSE, TRUE),
('小房子', 'M', 12.5, 9.7, 7.4, 7.2, 480, '罐口圓形, 內部為方形, 蓋深1.6cm', FALSE, TRUE),
('極光', '2.3寸', 9.0, 6.0, 3.8, 6.0, 100, '罐口較窄, 蛋型瓶身', FALSE, TRUE),
('極光', '3寸', 13.5, 10.0, 7.1, 8.2, 450, '罐口較窄, 蛋型瓶身', FALSE, TRUE);


-- ===== supabase\seed\004_urn_breeds.sql =====
TRUNCATE TABLE urn_breed_configs;

INSERT INTO urn_breed_configs (category, breed_name, base_ratio_ml_per_kg, min_head_diameter_cm, sort_order, notes) VALUES
-- 犬
('犬', '吉娃娃', 120, 5.5, 10, '超小型骨架'),
('犬', '約克夏', 120, 5.5, 20, '超小型骨架'),
('犬', '馬爾濟斯', 120, 6.0, 30, '骨質輕細'),
('犬', '博美犬', 125, 6.0, 40, '毛蓬骨架小'),
('犬', '玩具貴賓', 125, 6.0, 50, '骨骼修長'),
('犬', '迷你品(迷你杜賓)', 120, 5.5, 60, '骨架極小'),
('犬', '迷你臘腸犬 / 標準臘腸犬', 130, 7.5, 70, '脊椎較長骨灰量略多'),
('犬', '貴賓犬(迷你/標準)', 125, 7.0, 80, '標準體型'),
('犬', '比熊犬', 125, 7.0, 90, '骨架比博美略寬'),
('犬', '西施犬', 130, 8.0, 100, '短吻頭骨略寬'),
('犬', '雪納瑞(迷你)', 130, 7.5, 110, '骨架紮實'),
('犬', '巴哥犬', 135, 9.5, 120, '短吻犬頭骨寬圓'),
('犬', '傑克羅素梗', 130, 7.5, 130, '骨架結實'),
('犬', '狐狸犬(日本銀狐)', 130, 8.0, 140, '骨架中等偏細'),
('犬', '查理斯王騎士犬', 130, 8.5, 150, '骨架中等'),
('犬', '義大利灰狗', 120, 6.5, 160, '骨架細長'),
('犬', '米克斯-小型(10kg以下)', 130, 8.0, 170, '小型混血犬'),
('犬', '柴犬(含豆柴)', 130, 9.0, 180, '骨架精實'),
('犬', '法國鬥牛犬', 135, 10.5, 190, '短吻大頭，開口極重要'),
('犬', '柯基(潘布魯克/卡提根)', 135, 9.5, 200, '骨骼粗壯'),
('犬', '喜樂蒂牧羊犬', 130, 8.5, 210, '頭骨窄長'),
('犬', '英國鬥牛犬', 140, 12.0, 220, '骨骼極粗重，頭骨巨大'),
('犬', '米格魯(小獵犬)', 130, 9.0, 230, '骨骼結實'),
('犬', '台灣犬(土狗)', 130, 10.0, 240, '骨架均勻結實'),
('犬', '邊境牧羊犬', 130, 10.5, 250, '骨架發育完整'),
('犬', '鬆獅犬', 135, 11.5, 260, '頭骨大且寬'),
('犬', '米克斯-中型(10-20kg)', 130, 11.0, 270, '中型混血犬'),
('犬', '黃金獵犬', 140, 13.5, 280, '大骨量大型犬'),
('犬', '拉布拉多', 140, 13.5, 290, '骨骼粗重大犬'),
('犬', '薩摩耶', 135, 12.5, 300, '毛蓬骨量中大'),
('犬', '哈士奇(雪橇犬)', 135, 12.5, 310, '骨架結實長型'),
('犬', '德國牧羊犬(狼犬)', 140, 13.5, 320, '大骨架工作犬'),
('犬', '杜賓犬', 135, 12.5, 330, '骨架高大'),
('犬', '羅威納', 145, 14.5, 340, '骨質密度極高'),
('犬', '伯恩山犬', 145, 15.0, 350, '巨型犬骨量'),
('犬', '秋田犬', 140, 13.5, 360, '大型犬骨架'),
('犬', '阿拉斯加雪橇犬', 145, 14.5, 370, '巨型雪橇犬'),
('犬', '巨型貴賓(標準型貴賓)', 135, 12.0, 380, '高大修長骨架'),
('犬', '米克斯-大型(20kg以上)', 135, 13.5, 390, '大型混血犬'),
('犬', '其他狗狗品種(請依體重推估)', 130, 9.0, 999, '通用犬類預設值'),

-- 貓
('貓', '米克斯貓(家貓/虎斑/三花/橘貓/黑貓)', 130, 8.0, 10, '一般混血家貓'),
('貓', '英國短毛貓(英短)', 135, 8.5, 20, '臉腮較寬圓'),
('貓', '美國短毛貓(美短)', 130, 8.0, 30, '體型結實標準'),
('貓', '暹羅貓', 125, 7.0, 40, '體態纖細'),
('貓', '俄羅斯藍貓', 125, 7.5, 50, '骨架修長細緻'),
('貓', '孟加拉豹貓', 130, 8.0, 60, '肌肉結實骨量標準'),
('貓', '阿比西尼亞貓', 125, 7.0, 70, '骨骼輕巧修長'),
('貓', '波斯貓', 130, 8.5, 80, '頭骨圓寬'),
('貓', '異國短毛貓(加菲貓)', 130, 8.5, 90, '短吻扁臉頭骨圓'),
('貓', '金吉拉', 125, 8.0, 100, '骨架適中'),
('貓', '曼赤肯(短腿貓)', 125, 8.0, 110, '四肢短但頭身同成貓'),
('貓', '蘇格蘭折耳貓', 130, 8.0, 120, '骨骼較脆'),
('貓', '斯芬克斯無毛貓', 125, 7.5, 130, '體態精瘦'),
('貓', '布偶貓', 135, 9.0, 140, '體型大近小型犬'),
('貓', '緬因貓', 140, 10.0, 150, '大型貓骨架近柴犬'),
('貓', '挪威森林貓', 135, 9.0, 160, '骨架大厚實'),
('貓', '西伯利亞森林貓', 135, 9.0, 170, '大型骨架'),
('貓', '其他貓咪品種(請依體重推估)', 130, 8.0, 999, '通用貓類預設值'),

-- 兔
('兔', '侏儒兔(波蘭兔)', 110, 6.0, 10, '極小型兔'),
('兔', '荷蘭垂耳兔/獅子兔', 115, 7.0, 20, '小型垂耳兔'),
('兔', '迷你兔(常見混血兔)', 115, 7.0, 30, '台灣常見混血小兔'),
('兔', '家兔/雷克斯兔/肉兔', 120, 8.5, 40, '成年體型大'),
('兔', '巨型花色兔/巨兔', 125, 10.0, 50, '體型堪比小型犬'),
('兔', '其他兔種(請依體重推估)', 115, 7.0, 999, '通用兔類預設值'),

-- 鼠類 / 特寵
('鼠類', '倉鼠(三線/一線/老公公)', 60, 3.5, 10, '微型骨架'),
('鼠類', '黃金鼠(熊鼠)', 70, 4.0, 20, '小型骨架'),
('特寵', '天竺鼠(豚鼠)', 110, 5.5, 30, '骨量多於倉鼠'),
('特寵', '刺蝟(非洲侏儒刺蝟)', 100, 5.0, 40, '骨架小'),
('特寵', '蜜袋鼯', 70, 4.0, 50, '骨骼極輕細'),
('特寵', '龍貓(絨鼠)', 110, 6.0, 60, '骨架近天竺鼠'),
('特寵', '雪貂', 120, 6.5, 70, '體型修長'),
('特寵', '狐獴/土撥鼠', 125, 7.5, 80, '骨架近幼貓'),

-- 鳥類 / 爬蟲
('鳥類', '小型雀鳥(文鳥/虎皮/愛情鳥)', 60, 3.0, 10, '中空骨極輕'),
('鳥類', '中型鸚鵡(玄鳳/和尚/凱克)', 70, 5.0, 20, '留意鳥喙寬度'),
('鳥類', '大型鸚鵡(金剛/灰鸚/巴丹)', 80, 8.0, 30, '骨架長且喙堅硬'),
('鳥類', '柯爾鴨/蘆丁雞/寵物雞', 100, 6.0, 40, '骨骼較密實'),
('爬蟲', '守宮(豹紋/睫角)', 60, 3.5, 10, '骨量微小'),
('爬蟲', '蜥蜴(鬆獅蜥/藍舌蜥)', 110, 6.0, 20, '骨骼粗'),
('爬蟲', '蛇類(玉米蛇/球蟒)', 80, 4.0, 30, '骨量主要為脊椎'),
('爬蟲', '小型水龜/斑龜/巴西龜', 220, 5.0, 40, '含背甲火化量大'),
('爬蟲', '大型陸龜(蘇卡達/豹龜)', 260, 10.0, 50, '甲殼厚重骨量巨大'),
('特寵', '其他特殊寵物(請依體重推估)', 100, 5.0, 999, '通用特寵預設值');



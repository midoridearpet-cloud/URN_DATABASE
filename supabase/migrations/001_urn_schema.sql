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

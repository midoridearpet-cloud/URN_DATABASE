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

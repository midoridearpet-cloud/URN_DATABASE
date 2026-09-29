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

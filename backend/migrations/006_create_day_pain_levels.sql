CREATE TABLE day_pain_levels (
  id CHAR(36) NOT NULL,
  day_entry_id CHAR(36) NOT NULL,
  pain_category_id CHAR(36) NOT NULL,
  level TINYINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_pain_category (day_entry_id, pain_category_id),
  KEY idx_day_pain_updated (updated_at),
  CONSTRAINT fk_day_pain_entry FOREIGN KEY (day_entry_id) REFERENCES day_entries(id) ON DELETE CASCADE,
  CONSTRAINT fk_day_pain_category FOREIGN KEY (pain_category_id) REFERENCES pain_categories(id) ON DELETE CASCADE,
  CONSTRAINT chk_day_pain_level CHECK (level BETWEEN 1 AND 4)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

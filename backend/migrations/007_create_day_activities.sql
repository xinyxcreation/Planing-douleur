CREATE TABLE day_activities (
  id CHAR(36) NOT NULL,
  day_entry_id CHAR(36) NOT NULL,
  activity_type_id CHAR(36) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_activity (day_entry_id, activity_type_id),
  KEY idx_day_activity_updated (updated_at),
  CONSTRAINT fk_day_activity_entry FOREIGN KEY (day_entry_id) REFERENCES day_entries(id) ON DELETE CASCADE,
  CONSTRAINT fk_day_activity_type FOREIGN KEY (activity_type_id) REFERENCES activity_types(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

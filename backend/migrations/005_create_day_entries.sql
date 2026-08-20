CREATE TABLE day_entries (
  id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  entry_date DATE NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_entries_user_date (user_id, entry_date),
  KEY idx_day_entries_user_updated (user_id, updated_at),
  CONSTRAINT fk_day_entries_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

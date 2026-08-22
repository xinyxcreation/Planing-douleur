CREATE DATABASE IF NOT EXISTS pwa_planning_douleur
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE pwa_planning_douleur;

CREATE TABLE IF NOT EXISTS pain_categories (
  id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  name VARCHAR(120) NOT NULL,
  position INT NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pain_categories_user_name (user_id, name),
  KEY idx_pain_categories_user (user_id, deleted_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS activity_types (
  id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  name VARCHAR(120) NOT NULL,
  position INT NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_activity_types_user_name (user_id, name),
  KEY idx_activity_types_user (user_id, deleted_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS day_entries (
  id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  entry_date DATE NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_entries_user_date (user_id, entry_date),
  KEY idx_day_entries_user_date (user_id, entry_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS day_pain_levels (
  id CHAR(36) NOT NULL,
  day_entry_id CHAR(36) NOT NULL,
  pain_category_id CHAR(36) NOT NULL,
  level TINYINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_pain_category (day_entry_id, pain_category_id),
  KEY idx_day_pain_entry (day_entry_id),
  CONSTRAINT chk_day_pain_level CHECK (level BETWEEN 0 AND 3),
  CONSTRAINT fk_day_pain_entry
    FOREIGN KEY (day_entry_id) REFERENCES day_entries(id),
  CONSTRAINT fk_day_pain_category
    FOREIGN KEY (pain_category_id) REFERENCES pain_categories(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS day_activities (
  id CHAR(36) NOT NULL,
  day_entry_id CHAR(36) NOT NULL,
  activity_type_id CHAR(36) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_day_activity (day_entry_id, activity_type_id),
  KEY idx_day_activity_entry (day_entry_id),
  CONSTRAINT fk_day_activity_entry
    FOREIGN KEY (day_entry_id) REFERENCES day_entries(id),
  CONSTRAINT fk_day_activity_type
    FOREIGN KEY (activity_type_id) REFERENCES activity_types(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sync_changes (
  sync_cursor BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id CHAR(36) NOT NULL,
  entity VARCHAR(40) NOT NULL,
  entity_id CHAR(36) NOT NULL,
  operation VARCHAR(10) NOT NULL,
  changed_at DATETIME(6) NOT NULL,
  PRIMARY KEY (sync_cursor),
  KEY idx_sync_user_cursor (user_id, sync_cursor)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sync_cursor (
  id TINYINT UNSIGNED NOT NULL,
  cursor_value BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

INSERT INTO sync_cursor (id, cursor_value, updated_at)
VALUES (1, 0, UTC_TIMESTAMP(6))
ON DUPLICATE KEY UPDATE id = id;

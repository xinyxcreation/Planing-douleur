CREATE TABLE sync_changes (
  sync_cursor BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id CHAR(36) NOT NULL,
  entity VARCHAR(50) NOT NULL,
  entity_id CHAR(36) NOT NULL,
  operation ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
  changed_at DATETIME(6) NOT NULL,
  PRIMARY KEY (sync_cursor),
  KEY idx_sync_changes_user_cursor (user_id, sync_cursor),
  KEY idx_sync_changes_entity (entity, entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 邮件系统数据库结构 (MySQL 5.7+ / 8.0+)
-- ============================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- 用户表
-- ----------------------------
DROP TABLE IF EXISTS `ms_users`;
CREATE TABLE `ms_users` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `password` varchar(255) NOT NULL,
  `email` varchar(128) DEFAULT NULL,
  `display_name` varchar(64) DEFAULT NULL,
  `role` enum('admin','user') NOT NULL DEFAULT 'user',
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `last_login_at` datetime DEFAULT NULL,
  `last_login_ip` varchar(45) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`),
  KEY `idx_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 域名表
-- ----------------------------
DROP TABLE IF EXISTS `ms_domains`;
CREATE TABLE `ms_domains` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `domain` varchar(128) NOT NULL,
  `owner_id` int(11) unsigned NOT NULL,
  `dkim_private` text,
  `dkim_public` text,
  `dkim_selector` varchar(32) DEFAULT 'mail',
  `mx_record` varchar(128) DEFAULT NULL,
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `is_default` tinyint(1) NOT NULL DEFAULT '0',
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_domain` (`domain`),
  KEY `idx_owner` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 邮箱表
-- ----------------------------
DROP TABLE IF EXISTS `ms_mailboxes`;
CREATE TABLE `ms_mailboxes` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) unsigned NOT NULL,
  `domain_id` int(11) unsigned NOT NULL,
  `local_part` varchar(64) NOT NULL,
  `full_address` varchar(128) NOT NULL,
  `password` varchar(255) NOT NULL,
  `display_name` varchar(64) DEFAULT NULL,
  `quota_mb` int(11) NOT NULL DEFAULT '1024',
  `used_mb` int(11) NOT NULL DEFAULT '0',
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `last_login_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_address` (`full_address`),
  KEY `idx_user` (`user_id`),
  KEY `idx_domain` (`domain_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 端口配置表
-- ----------------------------
DROP TABLE IF EXISTS `ms_ports`;
CREATE TABLE `ms_ports` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `service` enum('smtp','pop3','imap') NOT NULL,
  `port` int(11) NOT NULL,
  `ssl` tinyint(1) NOT NULL DEFAULT '0',
  `tls` tinyint(1) NOT NULL DEFAULT '0',
  `bind_ip` varchar(45) DEFAULT '0.0.0.0',
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_service_port_ssl` (`service`,`port`,`ssl`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 邮件表
-- ----------------------------
DROP TABLE IF EXISTS `ms_emails`;
CREATE TABLE `ms_emails` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `mailbox_id` int(11) unsigned NOT NULL,
  `message_id` varchar(255) DEFAULT NULL,
  `from_address` varchar(255) NOT NULL,
  `from_name` varchar(128) DEFAULT NULL,
  `to_addresses` text NOT NULL,
  `cc_addresses` text,
  `bcc_addresses` text,
  `subject` varchar(998) DEFAULT NULL,
  `body_text` longtext,
  `body_html` longtext,
  `headers` longtext,
  `size_bytes` int(11) NOT NULL DEFAULT '0',
  `folder` enum('INBOX','SENT','DRAFTS','TRASH','JUNK','STARRED') NOT NULL DEFAULT 'INBOX',
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `is_starred` tinyint(1) NOT NULL DEFAULT '0',
  `direction` enum('in','out') NOT NULL DEFAULT 'in',
  `status` enum('queued','sent','failed','received') NOT NULL DEFAULT 'received',
  `error_message` varchar(500) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mailbox` (`mailbox_id`),
  KEY `idx_folder` (`folder`),
  KEY `idx_status` (`status`),
  KEY `idx_message_id` (`message_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 附件表
-- ----------------------------
DROP TABLE IF EXISTS `ms_attachments`;
CREATE TABLE `ms_attachments` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `email_id` int(11) unsigned NOT NULL,
  `filename` varchar(255) NOT NULL,
  `content_type` varchar(128) DEFAULT NULL,
  `size_bytes` int(11) NOT NULL DEFAULT '0',
  `storage_path` varchar(500) NOT NULL,
  `content_id` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_email` (`email_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- API 密钥表
-- ----------------------------
DROP TABLE IF EXISTS `ms_api_keys`;
CREATE TABLE `ms_api_keys` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) unsigned NOT NULL,
  `name` varchar(64) NOT NULL,
  `access_key` varchar(64) NOT NULL,
  `secret_key` varchar(128) NOT NULL,
  `permissions` varchar(255) DEFAULT 'read,send',
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `expires_at` datetime DEFAULT NULL,
  `last_used_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_access_key` (`access_key`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 系统设置表
-- ----------------------------
DROP TABLE IF EXISTS `ms_settings`;
CREATE TABLE `ms_settings` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `key_name` varchar(64) NOT NULL,
  `value` longtext,
  `group_name` varchar(32) DEFAULT 'general',
  `description` varchar(255) DEFAULT NULL,
  `is_public` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_key` (`key_name`),
  KEY `idx_group` (`group_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 操作日志表
-- ----------------------------
DROP TABLE IF EXISTS `ms_logs`;
CREATE TABLE `ms_logs` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) unsigned DEFAULT NULL,
  `action` varchar(64) NOT NULL,
  `target` varchar(255) DEFAULT NULL,
  `description` varchar(500) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL,
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`),
  KEY `idx_action` (`action`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------
-- 会话表
-- ----------------------------
DROP TABLE IF EXISTS `ms_sessions`;
CREATE TABLE `ms_sessions` (
  `id` varchar(128) NOT NULL,
  `user_id` int(11) unsigned DEFAULT NULL,
  `payload` longtext,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL,
  `last_activity` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`),
  KEY `idx_activity` (`last_activity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================
-- 初始化数据
-- ============================================

-- 默认管理员 (密码: admin123) - 实际使用请通过安装程序生成
-- 密码 hash 由 password_hash('admin123', PASSWORD_DEFAULT) 生成
INSERT INTO `ms_users` (`username`, `password`, `email`, `display_name`, `role`, `status`)
VALUES ('admin', '$2y$10$PLACEHOLDERWILLBEREGENERATEDBYINSTALLER', 'admin@localhost', '系统管理员', 'admin', 1);

-- 默认端口配置
INSERT INTO `ms_ports` (`service`, `port`, `ssl`, `tls`, `bind_ip`, `enabled`, `description`) VALUES
('smtp', 25,  0, 0, '0.0.0.0', 1, 'SMTP (明文)'),
('smtp', 465, 1, 0, '0.0.0.0', 1, 'SMTP SSL (SMTPS)'),
('smtp', 587, 0, 1, '0.0.0.0', 1, 'SMTP STARTTLS (提交端口)'),
('pop3', 110, 0, 0, '0.0.0.0', 1, 'POP3 (明文)'),
('pop3', 995, 1, 0, '0.0.0.0', 1, 'POP3 SSL (POP3S)'),
('imap', 143, 0, 1, '0.0.0.0', 1, 'IMAP STARTTLS'),
('imap', 993, 1, 0, '0.0.0.0', 1, 'IMAP SSL (IMAPS)');

-- 默认设置
INSERT INTO `ms_settings` (`key_name`, `value`, `group_name`, `description`, `is_public`) VALUES
('site_name', 'MailSystem', 'general', '站点名称', 1),
('site_logo', '', 'general', '站点 Logo URL', 1),
('admin_path', 'admin', 'security', '后台管理路径', 0),
('admin_port', '8080', 'security', '后台管理端口', 0),
('web_port', '80', 'general', 'Web 端口', 1),
('mail_hostname', 'mail.local', 'mail', '邮件服务器主机名', 0),
('max_mail_size', '26214400', 'mail', '单封邮件最大尺寸 (字节，默认 25MB)', 0),
('default_quota_mb', '1024', 'mail', '新邮箱默认配额 (MB)', 0),
('allow_registration', '0', 'security', '是否允许自助注册', 1),
('api_enabled', '1', 'api', '是否启用 API', 1),
('api_rate_limit', '60', 'api', 'API 每分钟请求限制', 0),
('smtp_banner', 'MailSystem ESMTP', 'mail', 'SMTP 欢迎语', 0),
('imap_idle_timeout', '1800', 'mail', 'IMAP IDLE 超时 (秒)', 0),
('mail_storage', 'maildir', 'mail', '邮件存储格式 (maildir/mbox)', 0);

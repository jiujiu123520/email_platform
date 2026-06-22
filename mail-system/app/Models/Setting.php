<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Setting
{
    public static function get(string $key, $default = null)
    {
        $row = Database::getInstance()->fetchOne('SELECT value FROM ms_settings WHERE key_name = ?', [$key]);
        return $row ? $row['value'] : $default;
    }
    public static function set(string $key, $value, string $group = 'general', string $description = '', bool $isPublic = false): void
    {
        $db = Database::getInstance();
        $exists = $db->fetchOne('SELECT id FROM ms_settings WHERE key_name = ?', [$key]);
        if ($exists) {
            $db->update('ms_settings', ['value' => $value, 'group_name' => $group], 'key_name = :k', ['k' => $key]);
        } else {
            $db->insert('ms_settings', [
                'key_name'    => $key,
                'value'       => $value,
                'group_name'  => $group,
                'description' => $description,
                'is_public'   => $isPublic ? 1 : 0,
            ]);
        }
    }
    public static function allByGroup(string $group): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_settings WHERE group_name = ?', [$group]);
    }
    public static function allPublic(): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_settings WHERE is_public = 1');
    }
    public static function all(): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_settings ORDER BY group_name, id');
    }
}

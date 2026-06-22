<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class ApiKey
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_api_keys WHERE id = ?', [$id]);
    }
    public static function findByAccessKey(string $key): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_api_keys WHERE access_key = ?', [$key]);
    }
    public static function allByUser(int $userId, bool $all = false): array
    {
        $sql = 'SELECT id, name, access_key, permissions, status, last_used_at, expires_at, created_at FROM ms_api_keys';
        $params = [];
        if (!$all) {
            $sql .= ' WHERE user_id = ?';
            $params[] = $userId;
        }
        $sql .= ' ORDER BY id DESC';
        return Database::getInstance()->fetchAll($sql, $params);
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_api_keys', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_api_keys', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_api_keys', 'id = :id', ['id' => $id]);
    }
}

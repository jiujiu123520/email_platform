<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class User
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_users WHERE id = ?', [$id]);
    }
    public static function findByUsername(string $u): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_users WHERE username = ?', [$u]);
    }
    public static function all(): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_users ORDER BY id ASC');
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_users', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_users', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_users', 'id = :id', ['id' => $id]);
    }
}

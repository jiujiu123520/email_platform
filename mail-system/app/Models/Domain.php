<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Domain
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_domains WHERE id = ?', [$id]);
    }
    public static function findByName(string $domain): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_domains WHERE domain = ?', [$domain]);
    }
    public static function allByOwner(int $ownerId, bool $includeAll = false): array
    {
        $sql = 'SELECT * FROM ms_domains';
        $params = [];
        if (!$includeAll) {
            $sql .= ' WHERE owner_id = ?';
            $params[] = $ownerId;
        }
        $sql .= ' ORDER BY id ASC';
        return Database::getInstance()->fetchAll($sql, $params);
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_domains', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_domains', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_domains', 'id = :id', ['id' => $id]);
    }
}

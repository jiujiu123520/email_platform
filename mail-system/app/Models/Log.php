<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Log
{
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_logs', $data);
    }
    public static function list(int $limit = 100, int $offset = 0, array $filters = []): array
    {
        $sql = 'SELECT l.*, u.username FROM ms_logs l LEFT JOIN ms_users u ON l.user_id = u.id WHERE 1=1';
        $params = [];
        if (!empty($filters['action'])) { $sql .= ' AND l.action = ?'; $params[] = $filters['action']; }
        if (!empty($filters['user_id'])) { $sql .= ' AND l.user_id = ?'; $params[] = (int) $filters['user_id']; }
        $sql .= ' ORDER BY l.id DESC LIMIT ' . (int) $limit . ' OFFSET ' . (int) $offset;
        return Database::getInstance()->fetchAll($sql, $params);
    }
}

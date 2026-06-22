<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Port
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_ports WHERE id = ?', [$id]);
    }
    public static function all(): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_ports ORDER BY service, `ssl` DESC, port ASC');
    }
    public static function allEnabled(): array
    {
        return Database::getInstance()->fetchAll('SELECT * FROM ms_ports WHERE enabled = 1 ORDER BY service, `ssl` DESC, port ASC');
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_ports', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_ports', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_ports', 'id = :id', ['id' => $id]);
    }
}

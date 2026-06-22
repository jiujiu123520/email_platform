<?php
/**
 * HTTP 响应封装
 */

namespace MailSystem\Core;

class Response
{
    public static function json($data, int $code = 200): void
    {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    public static function success($data = null, string $message = 'OK'): void
    {
        self::json(['code' => 0, 'message' => $message, 'data' => $data]);
    }

    public static function error(string $message = 'Error', int $code = 1, int $http = 200, $data = null): void
    {
        self::json(['code' => $code, 'message' => $message, 'data' => $data], $http);
    }

    public static function unauthorized(string $message = 'Unauthorized'): void
    {
        self::error($message, 401, 401);
    }

    public static function forbidden(string $message = 'Forbidden'): void
    {
        self::error($message, 403, 403);
    }

    public static function notFound(string $message = 'Not Found'): void
    {
        self::error($message, 404, 404);
    }

    public static function html(string $content, int $code = 200): void
    {
        http_response_code($code);
        header('Content-Type: text/html; charset=utf-8');
        echo $content;
        exit;
    }

    public static function redirect(string $url, int $code = 302): void
    {
        http_response_code($code);
        header('Location: ' . $url);
        exit;
    }

    public static function download(string $content, string $filename, string $contentType = 'application/octet-stream'): void
    {
        http_response_code(200);
        header('Content-Type: ' . $contentType);
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . strlen($content));
        echo $content;
        exit;
    }
}

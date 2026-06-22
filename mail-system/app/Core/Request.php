<?php
/**
 * HTTP 请求封装
 */

namespace MailSystem\Core;

class Request
{
    private string $method;
    private string $path;
    private array $query;
    private array $body;
    private array $headers;
    private array $server;
    private ?array $json = null;

    public function __construct()
    {
        $this->method  = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $this->server  = $_SERVER;
        $this->query   = $_GET;
        $this->body    = $_POST;
        $this->headers = $this->collectHeaders();

        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $uri = parse_url($uri, PHP_URL_PATH) ?: '/';
        $this->path = '/' . trim($uri, '/');

        if (isset($_SERVER['CONTENT_TYPE']) && stripos($_SERVER['CONTENT_TYPE'], 'application/json') !== false) {
            $raw = file_get_contents('php://input');
            if ($raw) {
                $decoded = json_decode($raw, true);
                if (is_array($decoded)) {
                    $this->json = $decoded;
                }
            }
        }
    }

    private function collectHeaders(): array
    {
        $headers = [];
        foreach ($_SERVER as $k => $v) {
            if (str_starts_with($k, 'HTTP_')) {
                $name = str_replace('_', '-', strtolower(substr($k, 5)));
                $headers[$name] = $v;
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = $_SERVER['CONTENT_TYPE'];
        }
        if (isset($_SERVER['PHP_AUTH_USER'])) {
            $headers['php-auth-user'] = $_SERVER['PHP_AUTH_USER'];
        }
        return $headers;
    }

    public function method(): string { return $this->method; }
    public function path(): string   { return $this->path; }
    public function query(?string $key = null, $default = null)
    {
        if ($key === null) return $this->query;
        return $this->query[$key] ?? $default;
    }
    public function input(?string $key = null, $default = null)
    {
        $data = array_merge($this->body, $this->json ?? []);
        if ($key === null) return $data;
        return $data[$key] ?? $default;
    }
    public function header(string $name, $default = null)
    {
        return $this->headers[strtolower($name)] ?? $default;
    }
    public function ip(): string
    {
        foreach (['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'REMOTE_ADDR'] as $k) {
            if (!empty($this->server[$k])) {
                return explode(',', $this->server[$k])[0];
            }
        }
        return '0.0.0.0';
    }
    public function userAgent(): string
    {
        return $this->server['HTTP_USER_AGENT'] ?? '';
    }
    public function bearerToken(): ?string
    {
        $auth = $this->header('authorization', '');
        if (stripos($auth, 'Bearer ') === 0) {
            return substr($auth, 7);
        }
        return null;
    }
    public function isJson(): bool
    {
        $ct = $this->header('content-type', '');
        return stripos($ct, 'application/json') !== false;
    }
}

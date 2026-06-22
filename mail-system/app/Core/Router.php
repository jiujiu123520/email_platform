<?php
/**
 * 简易路由器
 */

namespace MailSystem\Core;

class Router
{
    private array $routes = [];
    private array $middleware = [];
    private string $prefix = '';

    public function group(string $prefix, callable $callback, array $middleware = []): void
    {
        $prevPrefix = $this->prefix;
        $prevMiddleware = $this->middleware;
        $this->prefix .= $prefix;
        $this->middleware = array_merge($this->middleware, $middleware);
        $callback($this);
        $this->prefix = $prevPrefix;
        $this->middleware = $prevMiddleware;
    }

    public function get(string $path, $handler): void      { $this->add('GET',  $path, $handler); }
    public function post(string $path, $handler): void     { $this->add('POST', $path, $handler); }
    public function put(string $path, $handler): void      { $this->add('PUT',  $path, $handler); }
    public function delete(string $path, $handler): void   { $this->add('DELETE', $path, $handler); }
    public function any(string $path, $handler): void      { foreach (['GET','POST','PUT','DELETE','PATCH'] as $m) $this->add($m, $path, $handler); }

    private function add(string $method, string $path, $handler): void
    {
        $fullPath = rtrim($this->prefix . $path, '/') ?: '/';
        $this->routes[] = [
            'method'     => $method,
            'path'       => $fullPath,
            'handler'    => $handler,
            'middleware' => $this->middleware,
        ];
    }

    public function dispatch(Request $request): void
    {
        $method = $request->method();
        $path = $request->path();

        foreach ($this->routes as $route) {
            if ($route['method'] !== $method) continue;
            $params = $this->match($route['path'], $path);
            if ($params === null) continue;

            // 中间件
            foreach ($route['middleware'] as $mw) {
                $instance = new $mw();
                $result = $instance->handle($request);
                if ($result === false) {
                    Response::forbidden('Middleware denied');
                }
            }

            $handler = $route['handler'];
            if (is_array($handler) && count($handler) === 2) {
                [$class, $action] = $handler;
                $instance = new $class();
                $instance->$action($request, $params);
            } elseif (is_callable($handler)) {
                $handler($request, $params);
            } else {
                Response::error('Invalid handler');
            }
            return;
        }
        Response::notFound('Route not found: ' . $method . ' ' . $path);
    }

    private function match(string $pattern, string $path): ?array
    {
        $regex = preg_replace('#\{([a-zA-Z_][a-zA-Z0-9_]*)\}#', '(?P<$1>[^/]+)', $pattern);
        $regex = '#^' . rtrim($regex, '/') . '/?$#';
        if (preg_match($regex, $path, $m)) {
            $args = [];
            foreach ($m as $k => $v) {
                if (!is_int($k)) $args[$k] = $v;
            }
            return $args;
        }
        return null;
    }
}

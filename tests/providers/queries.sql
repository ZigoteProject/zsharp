-- named queries against schema.sql (0001): sqlc's style, a name and a kind before each
-- name: GetUser :one
SELECT id, name, email FROM users WHERE id = :id;

-- name: ListActive :many
SELECT * FROM users WHERE active = :active ORDER BY name;

-- name: OrdersFor :many
SELECT o.id, o.total, u.name AS buyer, COUNT(*) AS n
FROM orders o JOIN users u ON u.id = o.user_id
WHERE o.user_id = :user AND o.total > :least
GROUP BY o.id;

-- name: AddUser :exec
INSERT INTO users (name, email, active) VALUES (:name, :email, :active);

-- name: Rename :exec
UPDATE users SET name = ? WHERE id = ?;

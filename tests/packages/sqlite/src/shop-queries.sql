-- named queries against shop.sql, each run by the function the provider writes
-- name: AddCustomer :exec
INSERT INTO customers (name, email, credit, active, badge) VALUES (:name, :email, :credit, :active, :badge);

-- name: GetCustomer :one
SELECT id, name, email, credit FROM customers WHERE id = :id;

-- name: ActiveCustomers :many
SELECT * FROM customers WHERE active = :active ORDER BY name;

-- name: Deactivate :exec
UPDATE customers SET active = 0 WHERE credit < :credit;

-- name: CountCustomers :one
SELECT COUNT(*) AS n FROM customers;

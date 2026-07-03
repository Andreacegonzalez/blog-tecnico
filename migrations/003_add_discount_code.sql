-- Antes (bloqueaba la tabla orders):
-- CREATE INDEX idx_orders_discount_code ON orders(discount_code);

-- Después (sin bloqueo, seguro para producción):
CREATE INDEX CONCURRENTLY idx_orders_discount_code ON orders(discount_code);

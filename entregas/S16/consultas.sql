-- S16. Parte A: consultas sobre el esquema tienda
-- Alejandro Valencia Sandoval
-- Uso: docker compose exec postgres psql -U curso -d curso entregas\S16\consultas.sql

SET search_path TO tienda;

-- ============================================================
-- 1. Pedido 1003: cliente, producto, cantidad y subtotal (2 filas)
-- ============================================================
SELECT c.nombre AS cliente,
       pr.nombre AS producto,
       d.cantidad,
       d.cantidad * d.precio_unitario AS subtotal
FROM pedido p
JOIN cliente c  ON c.id_cliente  = p.id_cliente
JOIN detalle d  ON d.id_pedido   = p.id_pedido
JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.id_pedido = 1003;

-- ============================================================
-- 2. Cada cliente con quien lo refirió, incluidos los que llegaron solos (8 filas)
-- ============================================================
SELECT c.id_cliente,
       c.nombre AS cliente,
       r.nombre AS referido_por
FROM cliente c
LEFT JOIN cliente r ON r.id_cliente = c.referido_por
ORDER BY c.id_cliente;

-- ============================================================
-- 3. Productos que nunca se han vendido, ni en pedidos cancelados (1 fila)
-- ============================================================
SELECT pr.id_producto, pr.nombre
FROM producto pr
LEFT JOIN detalle d ON d.id_producto = pr.id_producto
WHERE d.id_producto IS NULL;

-- ============================================================
-- 4. Pedidos por cliente (todos), con 0 para quien no tiene (8 filas)
--    count(p.id_pedido) y no count(*): con LEFT JOIN, count(*) contaría
--    la fila "vacía" del cliente sin pedidos como 1.
-- ============================================================
SELECT c.id_cliente,
       c.nombre,
       count(p.id_pedido) AS num_pedidos
FROM cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre
ORDER BY num_pedidos DESC, c.id_cliente;

-- ============================================================
-- 5. Total vendido por categoría, sin cancelados, de mayor a menor (3 filas)
-- ============================================================
SELECT pr.categoria,
       sum(d.cantidad * d.precio_unitario) AS total
FROM detalle d
JOIN pedido p    ON p.id_pedido    = d.id_pedido
JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total DESC;

-- ============================================================
-- 6. Meses de 2026 con ventas (sin cancelados) > 200000 (2 filas)
--    El filtro por total va en HAVING porque depende de un agregado.
-- ============================================================
SELECT extract(month FROM p.fecha) AS mes,
       sum(d.cantidad * d.precio_unitario) AS total
FROM pedido p
JOIN detalle d ON d.id_pedido = p.id_pedido
WHERE p.estado <> 'cancelado'
  AND extract(year FROM p.fecha) = 2026
GROUP BY extract(month FROM p.fecha)
HAVING sum(d.cantidad * d.precio_unitario) > 200000
ORDER BY mes;

-- ============================================================
-- 7. Productos con precio mayor al promedio de SU categoría (4 filas)
-- ============================================================
SELECT pr.nombre, pr.categoria, pr.precio
FROM producto pr
WHERE pr.precio > (SELECT avg(x.precio)
                   FROM producto x
                   WHERE x.categoria = pr.categoria)
ORDER BY pr.categoria, pr.precio DESC;

-- ============================================================
-- 8. Clientes de Cali que compraron al menos un accesorio, sin cancelados,
--    cada uno una vez (2 filas). EXISTS evita duplicados sin DISTINCT.
-- ============================================================
SELECT c.id_cliente, c.nombre
FROM cliente c
WHERE c.ciudad = 'Cali'
  AND EXISTS (SELECT 1
              FROM pedido p
              JOIN detalle d   ON d.id_pedido    = p.id_pedido
              JOIN producto pr ON pr.id_producto = d.id_producto
              WHERE p.id_cliente = c.id_cliente
                AND p.estado <> 'cancelado'
                AND pr.categoria = 'Accesorio');

-- ============================================================
-- 9. Trampa del NOT IN (5 filas)
--    Por qué la consulta original devuelve 0 filas:
--    la subconsulta (SELECT referido_por FROM cliente) contiene NULL
--    (los clientes que llegaron solos tienen referido_por NULL).
--    "x NOT IN (1, 4, 3, NULL)" equivale a x<>1 AND x<>4 AND x<>3 AND x<>NULL;
--    y x<>NULL es UNKNOWN, así que toda la conjunción nunca es TRUE
--    (a lo sumo es UNKNOWN) y WHERE descarta todas las filas.
--    Correcta, con NOT EXISTS (no se confunde con NULL):
-- ============================================================
SELECT c.nombre
FROM cliente c
WHERE NOT EXISTS (SELECT 1
                  FROM cliente r
                  WHERE r.referido_por = c.id_cliente);

-- Alternativa equivalente: filtrar el NULL dentro de la subconsulta
-- SELECT nombre FROM cliente
-- WHERE id_cliente NOT IN (SELECT referido_por FROM cliente
--                          WHERE referido_por IS NOT NULL);

-- ============================================================
-- 10. El o los clientes que más han gastado, sin cancelados (2 filas, hay empate)
--     Se calcula el total por cliente una vez (CTE) y se compara con el máximo,
--     en vez de usar LIMIT 1, que perdería el empate.
-- ============================================================
WITH gasto AS (
    SELECT c.id_cliente, c.nombre,
           sum(d.cantidad * d.precio_unitario) AS total
    FROM cliente c
    JOIN pedido p  ON p.id_cliente = c.id_cliente
    JOIN detalle d ON d.id_pedido  = p.id_pedido
    WHERE p.estado <> 'cancelado'
    GROUP BY c.id_cliente, c.nombre
)
SELECT nombre, total
FROM gasto
WHERE total = (SELECT max(total) FROM gasto);

-- ============================================================
-- 11. Clientes que compraron TODOS los productos de Grano, sin cancelados (2 filas)
--     División con NOT EXISTS doble: no existe un producto de Grano
--     que el cliente no haya comprado en un pedido no cancelado.
-- ============================================================
SELECT c.id_cliente, c.nombre
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto pr
    WHERE pr.categoria = 'Grano'
      AND NOT EXISTS (
          SELECT 1
          FROM pedido p
          JOIN detalle d ON d.id_pedido = p.id_pedido
          WHERE p.id_cliente  = c.id_cliente
            AND p.estado     <> 'cancelado'
            AND d.id_producto = pr.id_producto
      )
);

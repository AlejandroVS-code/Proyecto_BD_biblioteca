-- normalizacion.sql: Hito 3 (S20, parte B). Migracion del esquema biblioteca ya cargado.
--
-- Que hace (resumen; el detalle esta en entregas/S20/hito3-normalizacion.md):
--   1. cuenta.correo pasa a ser unico (sin distinguir mayusculas).
--   2. prestamo.estado se elimina: se calcula en la vista prestamo_con_estado.
--   3. ejemplar.estado queda solo con la condicion fisica ('bueno','dañado','perdido'):
--      'disponible' y 'prestado' se calculan en la vista ejemplar_con_disponibilidad.
--   4. devolucion.estado_ejemplar usa el mismo vocabulario.
--   5. Indices en las FK de los reportes.
--
-- Uso (desde la carpeta del docker-compose, con las cargas y datos-prueba.sql ya corridos):
--   docker compose exec -T postgres psql -U curso -d curso -P pager=off -f /scripts/normalizacion.sql
-- Guardar la salida como evidencia:
--   cmd /c "docker compose exec -T postgres psql -U curso -d curso -P pager=off -f /scripts/normalizacion.sql > docs\salidas\09-migracion-hito3.txt 2>&1"
--
-- Seguridad: todo ocurre en UNA transaccion. Si cualquier verificacion falla, el script se detiene
-- con un ERROR y no se guarda nada (ROLLBACK automatico al cerrarse la sesion).
-- Una base nueva NO necesita este script: postgres/init/01_esquema.sql ya nace normalizada.
-- NO se puede correr dos veces sobre la misma base (la segunda vez ya no existe prestamo.estado).

\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

-- =====================================================================
-- (a) Evidencia ANTES de cambiar nada
-- =====================================================================
\echo
\echo '=== (a) EVIDENCIA ANTES ==='

\echo 'E1. Correos repetidos (debe dar 0 filas; si da filas, el UNIQUE fallaria):'
SELECT lower(correo) AS correo, count(*)
FROM cuenta GROUP BY lower(correo) HAVING count(*) > 1;

\echo 'E4. ejemplar.estado frente a los prestamos abiertos (S19: disponible/f = 86, prestado/t = 8):'
SELECT e.estado,
       EXISTS (SELECT 1 FROM prestamo p
               WHERE p.id_ejemplar = e.id_ejemplar
                 AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id_prestamo)) AS con_prestamo_abierto,
       count(*)
FROM ejemplar e GROUP BY 1, 2 ORDER BY 1, 2;

\echo 'E5. prestamo.estado frente a la existencia de devolucion (S19: devuelto/t = 21, en_uso/f = 8):'
SELECT p.estado, (d.id_prestamo IS NOT NULL) AS tiene_devolucion, count(*)
FROM prestamo p LEFT JOIN devolucion d USING (id_prestamo)
GROUP BY 1, 2 ORDER BY 1, 2;

\echo 'E8. Valores que hay hoy en devolucion.estado_ejemplar (todos deben poderse traducir):'
SELECT estado_ejemplar, count(*) FROM devolucion GROUP BY 1 ORDER BY 1;

\echo 'Conteos ANTES:'
SELECT (SELECT count(*) FROM libro)      AS libros,
       (SELECT count(*) FROM ejemplar)   AS ejemplares,
       (SELECT count(*) FROM prestamo)   AS prestamos,
       (SELECT count(*) FROM devolucion) AS devoluciones;

-- =====================================================================
-- (b) Migracion
-- =====================================================================
BEGIN;

-- Foto de lo que hay ahora, para compararlo con lo que calculen las vistas.
CREATE TEMP TABLE antes_prestamo ON COMMIT DROP AS
SELECT id_prestamo, estado FROM prestamo;

CREATE TEMP TABLE antes_ejemplar ON COMMIT DROP AS
SELECT id_ejemplar, estado FROM ejemplar;

-- 1. cuenta.correo: clave candidata sin proteger (S19, tabla cuenta).
CREATE UNIQUE INDEX cuenta_correo_uq ON cuenta (lower(correo));

-- 2. ejemplar.estado: solo condicion fisica. Primero se suelta el CHECK viejo (nombre que PostgreSQL
--    le dio: ejemplar_estado_check; si no existe, \d ejemplar muestra el real), luego se traducen
--    los valores y se pone el CHECK nuevo.
ALTER TABLE ejemplar DROP CONSTRAINT ejemplar_estado_check;
UPDATE ejemplar SET estado = 'bueno' WHERE estado IN ('disponible', 'prestado');
ALTER TABLE ejemplar ADD CONSTRAINT ejemplar_estado_check
    CHECK (estado IN ('bueno', 'dañado', 'perdido'));

-- 3. devolucion.estado_ejemplar: mismo vocabulario (sigue siendo un dato historico).
UPDATE devolucion SET estado_ejemplar = 'bueno' WHERE estado_ejemplar = 'disponible';
ALTER TABLE devolucion ADD CONSTRAINT devolucion_estado_ejemplar_check
    CHECK (estado_ejemplar IN ('bueno', 'dañado', 'perdido'));

-- 4. Las vistas que reemplazan a los datos derivados (mismas definiciones que 01_esquema.sql).
CREATE VIEW prestamo_con_estado AS
SELECT p.id_prestamo, p.id_usuario_lector, p.id_usuario_registra, p.id_ejemplar,
       p.fecha_prestamo, p.fecha_limite,
       d.fecha_devolucion,
       CASE WHEN d.id_prestamo IS NULL THEN 'en_uso' ELSE 'devuelto' END AS estado
FROM   prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo;

CREATE VIEW ejemplar_con_disponibilidad AS
SELECT x.*, (x.estado = 'bueno' AND NOT x.prestado) AS disponible
FROM (
    SELECT e.id_ejemplar, e.id_libro, e.codigo, e.estado,
           EXISTS (SELECT 1
                   FROM   prestamo p
                   WHERE  p.id_ejemplar = e.id_ejemplar
                     AND  NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id_prestamo)) AS prestado
    FROM   ejemplar e
) x;

CREATE VIEW libro_disponibilidad AS
SELECT l.id_libro, l.isbn, l.titulo, l.autor,
       count(v.id_ejemplar)                  AS ejemplares,
       count(*) FILTER (WHERE v.disponible)  AS disponibles
FROM   libro l
LEFT JOIN ejemplar_con_disponibilidad v ON v.id_libro = l.id_libro
GROUP BY l.id_libro, l.isbn, l.titulo, l.autor;

-- 5. VERIFICAR antes de borrar lo viejo (receta de S19, seccion 4): lo que calculan las vistas
--    debe ser exactamente lo que estaba guardado. Si algo no coincide, el script se detiene aqui.
DO $$
DECLARE
    n integer;
BEGIN
    -- el estado del prestamo calculado = el estado guardado, en las dos direcciones (EXCEPT)
    SELECT count(*) INTO n FROM (
        (SELECT id_prestamo, estado FROM antes_prestamo
         EXCEPT SELECT id_prestamo, estado FROM prestamo_con_estado)
        UNION ALL
        (SELECT id_prestamo, estado FROM prestamo_con_estado
         EXCEPT SELECT id_prestamo, estado FROM antes_prestamo)
    ) t;
    IF n <> 0 THEN
        RAISE EXCEPTION 'prestamo_con_estado no coincide con prestamo.estado en % filas', n;
    END IF;

    -- 'disponible' guardado = disponible calculado; dañado/perdido siguen igual
    SELECT count(*) INTO n
    FROM antes_ejemplar a
    JOIN ejemplar_con_disponibilidad v ON v.id_ejemplar = a.id_ejemplar
    WHERE (a.estado = 'disponible') <> v.disponible
       OR (a.estado IN ('dañado', 'perdido') AND v.estado <> a.estado);
    IF n <> 0 THEN
        RAISE EXCEPTION 'ejemplar_con_disponibilidad no coincide con ejemplar.estado en % filas', n;
    END IF;

    -- no se perdio ninguna fila
    IF (SELECT count(*) FROM prestamo) <> (SELECT count(*) FROM antes_prestamo)
       OR (SELECT count(*) FROM ejemplar_con_disponibilidad) <> (SELECT count(*) FROM antes_ejemplar) THEN
        RAISE EXCEPTION 'cambio el numero de filas';
    END IF;
END $$;

-- 6. Ya verificado: se quita la columna derivada.
ALTER TABLE prestamo DROP COLUMN estado;

-- 7. Indices en las FK de los reportes (mismos nombres que 01_esquema.sql).
CREATE INDEX ejemplar_id_libro_idx          ON ejemplar (id_libro);
CREATE INDEX prestamo_id_ejemplar_idx       ON prestamo (id_ejemplar);
CREATE INDEX prestamo_id_usuario_lector_idx ON prestamo (id_usuario_lector);

COMMIT;

-- =====================================================================
-- (c) Evidencia DESPUES
-- =====================================================================
\echo
\echo '=== (c) EVIDENCIA DESPUES ==='

\echo 'Conteos DESPUES (deben ser iguales a los de antes):'
SELECT (SELECT count(*) FROM libro)      AS libros,
       (SELECT count(*) FROM ejemplar)   AS ejemplares,
       (SELECT count(*) FROM prestamo)   AS prestamos,
       (SELECT count(*) FROM devolucion) AS devoluciones;

\echo 'Estado del prestamo, ahora calculado (esperado: devuelto 21, en_uso 8):'
SELECT estado, count(*) FROM prestamo_con_estado GROUP BY 1 ORDER BY 1;

\echo 'Ejemplares, ahora calculado (esperado: 94 en buen estado = 86 disponibles + 8 prestados):'
SELECT estado, prestado, disponible, count(*)
FROM ejemplar_con_disponibilidad GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

\echo 'Columnas de prestamo (ya no existe estado):'
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'biblioteca' AND table_name = 'prestamo' ORDER BY ordinal_position;

\echo 'Catalogo con disponibilidad (primeros 5 libros):'
SELECT titulo, ejemplares, disponibles FROM libro_disponibilidad ORDER BY id_libro LIMIT 5;

\echo 'E1 despues: el UNIQUE rechaza un correo repetido en cualquier combinacion de mayusculas.'
\echo '(Se prueba dentro de una transaccion que se deshace; el ERROR de abajo es el resultado esperado.)'
\set ON_ERROR_STOP off
BEGIN;
INSERT INTO cuenta (id_rol, usuario, documento, contrasena, nombres, apellidos, correo, telefono)
SELECT c.id_rol, 'prueba_dup', '9999999999', 'x', 'Prueba', 'Duplicado', upper(c.correo), '3000000000'
FROM cuenta c ORDER BY c.id_usuario LIMIT 1;
ROLLBACK;
\set ON_ERROR_STOP on

\echo
\echo 'Siguiente paso: volver a correr datos-prueba.sql y reportes.sql (esperado: 22, 2, 3 y 4 filas).'

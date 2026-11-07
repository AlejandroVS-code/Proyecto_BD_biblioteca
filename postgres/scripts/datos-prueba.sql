-- datos-prueba.sql: datos de prueba para los cuatro reportes (S16, parte B)
--
-- Requisito: la semilla ya cargada (carga-libros.sql y carga-lectores.sql con los CSV limpios).
-- Se puede correr cuantas veces se quiera: primero borra lo que insertó antes (todo lo
-- registrado por la cuenta 'bib_prueba') y luego lo vuelve a crear.
--
-- Uso (desde entorno-docker/, con el archivo en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
--
-- Las fechas son relativas a CURRENT_DATE (p = dias atras del prestamo, d = dias atras de la
-- devolucion, NULL si sigue abierto). Plazo de 14 dias: fecha_limite = fecha_prestamo + 14.
-- Prestamo abierto = sin fila en devolucion. prestamo.estado: 'en_uso' o 'devuelto'.
--
-- ============================================================================================
-- LO QUE DEBE SALIR (escrito antes de correr nada)
-- ============================================================================================
-- Prestamos por lector (29 en total, todos registrados por la cuenta 'bib_prueba'):
--   Mariana   1000000001: 4 devueltos a tiempo
--   Santiago  1000000002: 4 devueltos; Don Quijote devuelto 6 dias tarde
--   Valentina 1000000003: 1 devuelto, 1 abierto en mora (16 dias), 1 abierto a tiempo
--   Juan David 1000000004: 5 abiertos y ninguno devuelto: 2 en mora (26 y 6 dias),
--                          Rayuela vence hoy, 2 a tiempo
--   Camila    1000000005: 2 devueltos y 1 abierto en mora (2 dias)
--   Isabella  1000000007: 3 devueltos      Andres Felipe 1000000008: 3 devueltos
--   Laura     1000000009: 2 devueltos      Daniel        1000000010: 2 devueltos
--   Sebastian 1000000006 y los lectores 1000000011 a 1000000020: ningun prestamo
--
-- Casos de la tabla de la seccion 4 del taller:
--   1  Libro que nadie ha prestado: los libros ...023 a ...032 (10 libros).
--      Reporte 1: NO aparecen (ya hay 22 libros con prestamos; el reporte solo muestra los
--      del top 20 y sus empatados).
--   2  Empate en el ultimo puesto del top: 18 libros con 1 prestamo ocupan los puestos 5 a 22,
--      y el puesto 20 cae en ese grupo. Reporte 1: salen los 18, 22 filas en total.
--   3  Empate en el primer lugar de libros leidos: Mariana y Santiago con 4 devueltos cada uno.
--      Reporte 2: salen los dos.
--   4  Lector con varios abiertos y ninguno devuelto: Juan David (5 prestamos, 0 devueltos).
--      Reporte 2: no sale, aunque tiene mas prestamos que los ganadores.
--   5  Devuelto despues de la fecha limite: Don Quijote de Santiago (limite hace 46 dias,
--      devuelto hace 40). Reportes 3 y 4: no cuenta como mora.
--   6  Abierto que vence hoy: Rayuela de Juan David (fecha_limite = CURRENT_DATE).
--      Regla del grupo: mora solo si fecha_limite < CURRENT_DATE, asi que NO es mora.
--   7  Lector con dos prestamos en mora: Juan David (Ficciones y Cien años de soledad).
--      Reporte 3: aparece 1 vez. Reporte 4: aparece 2 veces.
--   8  Lectores sin ningun prestamo: Sebastian y 1000000011 a 1000000020.
--      Ningun reporte los muestra.

\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

BEGIN;

-- Cuenta de prueba que registra los prestamos (rol bibliotecario).
INSERT INTO cuenta (id_rol, usuario, documento, contrasena, nombres, apellidos, correo, telefono)
SELECT r.id_rol, 'bib_prueba', '9000000001', crypt('9000000001', gen_salt('bf')),
       'Bibliotecario', 'De Prueba', 'bib.prueba@correo-ejemplo.edu.co', '3009000001'
FROM rol r
WHERE r.nombre = 'bibliotecario'
ON CONFLICT DO NOTHING;

-- Limpiar lo que dejo una corrida anterior.
UPDATE ejemplar SET estado = 'disponible'
WHERE id_ejemplar IN (SELECT id_ejemplar FROM prestamo
                      WHERE id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba'));

DELETE FROM devolucion
WHERE id_prestamo IN (SELECT id_prestamo FROM prestamo
                      WHERE id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba'));

DELETE FROM prestamo
WHERE id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba');

-- Los prestamos de prueba, tal como se describen arriba.
CREATE TEMP TABLE t_prueba (
  isbn      varchar,
  copia     integer,
  documento varchar,
  p         integer,
  d         integer
) ON COMMIT DROP;

INSERT INTO t_prueba (isbn, copia, documento, p, d) VALUES
  -- Mariana: 4 devueltos a tiempo
  ('9780000000001', 1, '1000000001', 120, 110),
  ('9780000000004', 1, '1000000001', 100,  90),
  ('9780000000007', 1, '1000000001',  80,  70),
  ('9780000000002', 1, '1000000001',  60,  50),
  -- Santiago: 4 devueltos; el Quijote, 6 dias tarde (caso 5)
  ('9780000000001', 2, '1000000002',  95,  85),
  ('9780000000005', 1, '1000000002',  75,  65),
  ('9780000000009', 1, '1000000002',  60,  40),
  ('9780000000003', 1, '1000000002',  45,  35),
  -- Valentina: 1 devuelto, 1 abierto en mora y 1 abierto a tiempo
  ('9780000000001', 3, '1000000003',  70,  60),
  ('9780000000010', 1, '1000000003',  30, NULL),
  ('9780000000006', 1, '1000000003',   5, NULL),
  -- Juan David: 5 abiertos, ninguno devuelto (casos 4, 6 y 7)
  ('9780000000001', 4, '1000000004',  20, NULL),
  ('9780000000004', 2, '1000000004',  14, NULL),
  ('9780000000007', 2, '1000000004',  40, NULL),
  ('9780000000008', 1, '1000000004',  10, NULL),
  ('9780000000011', 1, '1000000004',   3, NULL),
  -- Camila: 2 devueltos y 1 abierto en mora
  ('9780000000004', 3, '1000000005',  50,  45),
  ('9780000000012', 1, '1000000005',  35,  30),
  ('9780000000013', 1, '1000000005',  16, NULL),
  -- Isabella: 3 devueltos
  ('9780000000009', 2, '1000000007',  55,  45),
  ('9780000000014', 1, '1000000007',  40,  30),
  ('9780000000015', 1, '1000000007',  25,  15),
  -- Andres Felipe: 3 devueltos
  ('9780000000016', 1, '1000000008',  90,  80),
  ('9780000000017', 1, '1000000008',  70,  60),
  ('9780000000018', 1, '1000000008',  50,  40),
  -- Laura: 2 devueltos
  ('9780000000019', 1, '1000000009',  45,  38),
  ('9780000000020', 1, '1000000009',  30,  22),
  -- Daniel: 2 devueltos
  ('9780000000021', 1, '1000000010',  35,  28),
  ('9780000000022', 1, '1000000010',  20,  12);

INSERT INTO prestamo (id_usuario_lector, id_usuario_registra, id_ejemplar, fecha_prestamo, fecha_limite, estado)
SELECT lec.id_usuario, bib.id_usuario, e.id_ejemplar,
       CURRENT_DATE - t.p,
       CURRENT_DATE - t.p + 14,
       CASE WHEN t.d IS NULL THEN 'en_uso' ELSE 'devuelto' END
FROM t_prueba t
JOIN cuenta   lec ON lec.documento = t.documento
JOIN cuenta   bib ON bib.usuario = 'bib_prueba'
JOIN libro    l   ON l.isbn = t.isbn
JOIN ejemplar e   ON e.id_libro = l.id_libro AND e.codigo = t.isbn || '-' || t.copia;

DO $$
DECLARE
  esperados integer;
  reales    integer;
BEGIN
  SELECT count(*) INTO esperados FROM t_prueba;
  SELECT count(*) INTO reales FROM prestamo
  WHERE id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba');
  IF esperados <> reales THEN
    RAISE EXCEPTION 'Se esperaban % prestamos y se insertaron %: revisa que la semilla de libros y lectores este cargada', esperados, reales;
  END IF;
END $$;

INSERT INTO devolucion (id_prestamo, id_usuario_registra, fecha_devolucion, estado_ejemplar)
SELECT pr.id_prestamo, pr.id_usuario_registra, CURRENT_DATE - t.d, 'disponible'
FROM t_prueba t
JOIN libro    l   ON l.isbn = t.isbn
JOIN ejemplar e   ON e.id_libro = l.id_libro AND e.codigo = t.isbn || '-' || t.copia
JOIN cuenta   lec ON lec.documento = t.documento
JOIN prestamo pr  ON pr.id_ejemplar = e.id_ejemplar
                 AND pr.id_usuario_lector = lec.id_usuario
                 AND pr.fecha_prestamo = CURRENT_DATE - t.p
WHERE t.d IS NOT NULL;

-- Los ejemplares con prestamo abierto quedan 'prestado'.
UPDATE ejemplar SET estado = 'prestado'
WHERE id_ejemplar IN (SELECT pr.id_ejemplar
                      FROM prestamo pr
                      WHERE pr.id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba')
                        AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = pr.id_prestamo));

-- Resumen de lo insertado
SELECT count(*)                                           AS prestamos,
       count(*) FILTER (WHERE d.id_prestamo IS NOT NULL)  AS devueltos,
       count(*) FILTER (WHERE d.id_prestamo IS NULL)      AS abiertos
FROM prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
WHERE p.id_usuario_registra = (SELECT id_usuario FROM cuenta WHERE usuario = 'bib_prueba');

COMMIT;

-- reportes.sql: los cuatro reportes del proyecto sobre el esquema biblioteca (S16, parte B)
--
-- Uso (desde entorno-docker/, con el archivo en postgres/scripts/, despues de datos-prueba.sql):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- Reglas generales del grupo:
--   * Un prestamo esta abierto si no tiene fila en devolucion (no se usa prestamo.estado).
--   * Mora: prestamo abierto con fecha_limite < CURRENT_DATE. El que vence hoy NO esta en mora.
--   * Un prestamo devuelto despues de su fecha_limite ya no es mora.
--   * "Libros leidos" = prestamos devueltos.
--   * El prestamo apunta a un ejemplar: el libro se llega por prestamo -> ejemplar -> libro.
--   * El nombre, el correo y el telefono del lector estan en cuenta.

\echo
\echo '== Reporte 1. Los 20 libros mas prestados =='
-- Devuelve: titulo y numero de prestamos de cada libro (todas las copias juntas), de mayor a menor.
-- Decisiones:
--   * Empates: FETCH FIRST 20 ROWS WITH TIES incluye a todos los empatados con el puesto 20.
--   * Libros sin prestamos: el LEFT JOIN los cuenta con 0, pero solo salen si el top 20 no se
--     completa con libros prestados. Con los datos de prueba hay 22 libros con prestamos,
--     asi que los 10 libros sin prestamos (...023 a ...032) no aparecen.
--   * El ORDER BY de afuera solo ordena la presentacion; el corte por empates lo hace el de adentro.
-- Esperado con datos-prueba.sql: 22 filas.
--   Cien años de soledad 4 · Rayuela 3 · Don Quijote de la Mancha 2 · Ficciones 2,
--   y 18 libros con 1 prestamo (ISBN ...002, ...003, ...005, ...006, ...008 y ...010 a ...022),
--   todos empatados en el puesto 20.
SELECT *
FROM (
    SELECT l.titulo, count(p.id_prestamo) AS prestamos
    FROM   biblioteca.libro l
    LEFT JOIN biblioteca.ejemplar e ON e.id_libro    = l.id_libro
    LEFT JOIN biblioteca.prestamo p ON p.id_ejemplar = e.id_ejemplar
    GROUP BY l.id_libro, l.titulo
    ORDER BY prestamos DESC
    FETCH FIRST 20 ROWS WITH TIES
) AS mas_prestados
ORDER BY prestamos DESC, titulo;

\echo
\echo '== Reporte 2. El o los lectores que mas libros han leido (prestamos devueltos) =='
-- Devuelve: el o los lectores con mas prestamos devueltos, con ese numero.
-- Decisiones:
--   * Solo cuentan los prestamos con devolucion.
--   * Empates: = max(...) devuelve a todos los empatados (LIMIT 1 dejaria uno por fuera).
--   * Un lector sin devoluciones no aparece en leidos, asi que no puede salir.
-- Esperado con datos-prueba.sql: 2 filas.
--   Mariana Gómez Rojas 4 · Santiago Rodríguez Pérez 4.
--   Juan David Martínez Ruiz (5 prestamos, ninguno devuelto) no sale.
WITH leidos AS (
    SELECT p.id_usuario_lector, count(*) AS devueltos
    FROM   biblioteca.prestamo p
    JOIN   biblioteca.devolucion d ON d.id_prestamo = p.id_prestamo
    GROUP BY p.id_usuario_lector
)
SELECT c.nombres, c.apellidos, x.devueltos
FROM   leidos x
JOIN   biblioteca.cuenta c ON c.id_usuario = x.id_usuario_lector
WHERE  x.devueltos = (SELECT max(devueltos) FROM leidos)
ORDER BY c.apellidos;

\echo
\echo '== Reporte 3. Lectores morosos (cada uno una vez) =='
-- Devuelve: los lectores con al menos un prestamo vencido y no devuelto, una fila por lector.
-- Decisiones:
--   * Mora = sin devolucion y fecha_limite < CURRENT_DATE (el que vence hoy no cuenta).
--   * EXISTS evita repetir al lector que tiene varios prestamos en mora.
-- Esperado con datos-prueba.sql: 3 filas.
--   Camila Hernández Torres · Valentina López Díaz · Juan David Martínez Ruiz.
--   Santiago (devuelto tarde) y los lectores sin prestamos no salen.
SELECT c.documento, c.nombres, c.apellidos
FROM   biblioteca.cuenta c
WHERE  EXISTS (SELECT 1
               FROM   biblioteca.prestamo p
               WHERE  p.id_usuario_lector = c.id_usuario
                 AND  p.fecha_limite < CURRENT_DATE
                 AND  NOT EXISTS (SELECT 1
                                  FROM   biblioteca.devolucion d
                                  WHERE  d.id_prestamo = p.id_prestamo))
ORDER BY c.apellidos;

\echo
\echo '== Reporte 4. Prestamos en mora (lista de notificacion) =='
-- Devuelve: un prestamo en mora por fila, con nombre, correo y telefono del lector,
-- el libro, la fecha limite y los dias de mora.
-- Decisiones:
--   * Misma regla de mora del reporte 3; aqui la unidad es el prestamo, no el lector.
--   * No hay tabla de notificaciones: esta consulta es la lista que usa el boton de notificar.
--   * Ordenado de mayor a menor mora.
-- Esperado con datos-prueba.sql: 4 filas.
--   Juan David Martínez Ruiz · Ficciones · 26 dias
--   Valentina López Díaz · La sombra del viento · 16 dias
--   Juan David Martínez Ruiz · Cien años de soledad · 6 dias
--   Camila Hernández Torres · Los detectives salvajes · 2 dias
--   Juan David sale 2 veces; Rayuela (vence hoy) y el Quijote de Santiago no salen.
SELECT c.nombres || ' ' || c.apellidos   AS lector,
       c.correo,
       c.telefono,
       l.titulo,
       p.fecha_limite,
       CURRENT_DATE - p.fecha_limite     AS dias_mora
FROM   biblioteca.prestamo p
JOIN   biblioteca.cuenta   c ON c.id_usuario = p.id_usuario_lector
JOIN   biblioteca.ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN   biblioteca.libro    l ON l.id_libro = e.id_libro
WHERE  p.fecha_limite < CURRENT_DATE
  AND  NOT EXISTS (SELECT 1
                   FROM   biblioteca.devolucion d
                   WHERE  d.id_prestamo = p.id_prestamo)
ORDER BY dias_mora DESC;

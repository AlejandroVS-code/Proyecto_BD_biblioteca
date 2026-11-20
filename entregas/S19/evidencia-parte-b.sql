-- evidencia-parte-b.sql: consultas de evidencia de la Parte B del taller S19
--
-- Solo lectura: no modifica ninguna tabla.
-- Requisito: semilla cargada (carga-libros.sql y carga-lectores.sql) y datos-prueba.sql.
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso -P pager=off -f /scripts/evidencia-parte-b.sql
--
-- LO QUE DEBE SALIR con la semilla y datos-prueba.sql (escrito antes de correr nada):
--   E1  0 filas (la carga rechaza correos repetidos)
--   E2  0 filas (un autor por libro)
--   E3  libros = 32, con_editorial = 0
--   E4  disponible/FALSE y prestado/TRUE; sin contradicciones
--   E5  devuelto/TRUE = 21 y en_uso/FALSE = 8
--   E6  14 dias en los 29 prestamos, salvo que los datos incluyan renovaciones
--   E7  0 filas

SET search_path TO biblioteca, public;

\echo '== E1. cuenta: correos repetidos (clave candidata sin UNIQUE) =='
SELECT lower(correo) AS correo, count(*)
FROM cuenta
GROUP BY lower(correo)
HAVING count(*) > 1;

\echo '== E2. libro: listas en la celda autor (debe dar 0 filas) =='
SELECT isbn, autor
FROM libro
WHERE autor ~ '[,;/]' OR autor ~* '\s(y|and|&)\s';

\echo '== E3. libro: cuanto se llena editorial =='
SELECT count(*) AS libros, count(editorial) AS con_editorial
FROM libro;

\echo '== E4. ejemplar: estado frente a prestamos abiertos =='
-- Contradiccion: 'disponible' con TRUE, o 'prestado' con FALSE.
SELECT e.estado,
       EXISTS (SELECT 1 FROM prestamo p
               WHERE p.id_ejemplar = e.id_ejemplar
                 AND NOT EXISTS (SELECT 1 FROM devolucion d
                                 WHERE d.id_prestamo = p.id_prestamo)) AS con_prestamo_abierto,
       count(*)
FROM ejemplar e
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== E5. prestamo: estado frente a la existencia de devolucion =='
SELECT p.estado, (d.id_prestamo IS NOT NULL) AS tiene_devolucion, count(*)
FROM prestamo p
LEFT JOIN devolucion d USING (id_prestamo)
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== E6. prestamo: dias entre prestamo y fecha limite (otros valores = renovaciones) =='
SELECT fecha_limite - fecha_prestamo AS dias, count(*)
FROM prestamo
GROUP BY 1
ORDER BY 2 DESC;

\echo '== E7. prestamo: ejemplares con dos prestamos abiertos (debe dar 0 filas) =='
SELECT p.id_ejemplar, count(*)
FROM prestamo p
WHERE NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id_prestamo)
GROUP BY p.id_ejemplar
HAVING count(*) > 1;

-- =====================================================================
-- S19 · PARTE A: detectar y corregir esquemas mal diseñados
-- Entregable por grupo: casos.sql (los cuatro casos, una sola salida)
-- Grupo: 2   Integrantes: Alejandro Valencia, Maria Alejandra Pizarro Sarria, Nicolas Velasco
--
-- Cada esquema CORREGIDO se crea aparte (gimnasio_norm, farmacia_norm,
-- cursos_libres_norm, envios_norm) y se llena con los datos del original.
-- Los esquemas ORIGINALES (gimnasio, farmacia, cursos_libres, envios) se usan
-- primero como evidencia del "ANTES"; la tabla original se elimina (DROP) al
-- final de cada caso, solo después de verificar la migración.
--
-- Cada caso tiene: (a) diagnóstico, (b) evidencia, (c) esquema corregido,
-- (d) migración dentro de BEGIN ... COMMIT, (e) verificación, (f) retirar lo
-- viejo (DROP) y la pregunta propia.
--
-- Cómo correrlo (desde entorno-docker/, con este archivo y S19-esquemas.sql
-- copiados en postgres/scripts/):
--   cmd /c "docker compose exec -T postgres psql -U curso -d curso -a -f /scripts/casos.sql > S19-salida.txt 2>&1"
--   (-a hace que la salida incluya también los comentarios y las consultas)
-- El script empieza recreando los esquemas originales con S19-esquemas.sql,
-- así que se puede repetir todas las veces que se quiera.
-- =====================================================================

\set ON_ERROR_STOP on

\echo '--- Se recrean los esquemas originales (S19-esquemas.sql) ---'
\i /scripts/S19-esquemas.sql


-- #####################################################################
-- CASO 1: GIMNASIO
--   socio (id_socio PK, nombre, plan, valor_plan, clases)
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) DIAGNÓSTICO
-- ---------------------------------------------------------------------
-- Reglas del enunciado -> dependencias funcionales (DF):
--   id_socio -> nombre, plan, clases
--   plan     -> valor_plan        (cada plan tiene un valor fijo)
-- Clave candidata: id_socio (la única).
--
-- PROBLEMA PRINCIPAL (explica la queja): `clases` guarda una lista separada
--   por ';'. No es atómica -> NO está en 1FN. Contar o buscar con LIKE da
--   respuestas equivocadas.
-- PROBLEMA SECUNDARIO: dependencia transitiva
--   id_socio -> plan -> valor_plan  -> incumple 3FN. El valor del plan se
--   repite en cada socio; cambiar un precio obliga a editar muchas filas.
--   (Como la PK es de una sola columna, aquí no hay problema de 2FN.)
-- OTROS SÍNTOMAS: la misma clase escrita 'Yoga', 'yoga' y 'Yoga ' (con
--   espacio al final).

\echo
\echo '#####################################################################'
\echo '# CASO 1 - ANTES: esquema original gimnasio.socio (con el error)'
\echo '#####################################################################'

\echo '--- Estructura original ---'
\d gimnasio.socio

\echo '--- Datos originales ---'
SELECT * FROM gimnasio.socio ORDER BY id_socio;

\echo '--- ANTES (b1) La queja: conteo con LIKE (Yoga sale 2 y Spinning 3; lo real es 3 y 2) ---'
SELECT 'Yoga' AS clase, count(*) AS socios_segun_sistema
FROM gimnasio.socio WHERE clases LIKE '%Yoga%'
UNION ALL
SELECT 'Spinning', count(*)
FROM gimnasio.socio WHERE clases LIKE '%Spinning%';

\echo '--- ANTES (b2) Por qué falla: el socio 3 escribió yoga en minúscula y LIKE no lo encuentra ---'
SELECT id_socio, nombre, clases
FROM gimnasio.socio
WHERE clases ILIKE '%yoga%' AND clases NOT LIKE '%Yoga%';

\echo '--- ANTES (b3) Por qué falla: Spinning avanzado (socio 2) se cuenta como Spinning ---'
SELECT id_socio, nombre, clases
FROM gimnasio.socio
WHERE clases LIKE '%Spinning%';

\echo '--- ANTES (b4) Redundancia: el valor del plan se repite en cada socio ---'
SELECT plan, valor_plan, count(*) AS socios
FROM gimnasio.socio
GROUP BY plan, valor_plan
ORDER BY plan;

\echo '--- ANTES (b5) ¿Los datos contradicen plan -> valor_plan? (0 filas = no) ---'
SELECT plan FROM gimnasio.socio GROUP BY plan HAVING count(DISTINCT valor_plan) > 1;

\echo '--- ANTES (b6) Anomalía de actualización: cambiar el valor del plan Mensual en UNA fila (se deshace) ---'
BEGIN;
UPDATE gimnasio.socio SET valor_plan = 95000 WHERE id_socio = 1;
-- El plan Mensual queda con DOS valores: los datos se contradicen.
SELECT plan, valor_plan, count(*) AS socios
FROM gimnasio.socio
WHERE plan = 'Mensual'
GROUP BY plan, valor_plan
ORDER BY valor_plan;
ROLLBACK;

-- DECISIÓN sobre los datos (queda escrito por qué):
--   'Yoga', 'yoga' y 'Yoga ' son la misma clase: al migrar se quitan los
--   espacios y se unifica la escritura. 'Spinning' y 'Spinning avanzado'
--   son clases DISTINTAS (el enunciado lo dice): no se mezclan.

\echo '--- Conteos ESPERADOS, calculados antes de migrar ---'
SELECT (SELECT count(*) FROM gimnasio.socio)                       AS socios_esperados,         -- 6
       (SELECT count(DISTINCT plan) FROM gimnasio.socio)           AS planes_esperados,         -- 3
       (SELECT count(DISTINCT lower(trim(c.pedazo)))
          FROM gimnasio.socio s
          CROSS JOIN LATERAL string_to_table(s.clases, ';') AS c(pedazo)
         WHERE trim(c.pedazo) <> '')                               AS clases_esperadas,         -- 5
       (SELECT count(*) FROM (SELECT DISTINCT s.id_socio, lower(trim(c.pedazo))
          FROM gimnasio.socio s
          CROSS JOIN LATERAL string_to_table(s.clases, ';') AS c(pedazo)
         WHERE trim(c.pedazo) <> '') x)                            AS inscripciones_esperadas;  -- 9 (el socio 5 tiene NULL: 0)

-- =====================================================================
-- (c) ESQUEMA CORREGIDO  (esquema nuevo: gimnasio_norm)
--   plan              (nombre_plan PK, valor_plan)
--   socio             (id_socio PK, nombre, plan FK -> plan)
--   clase             (id_clase PK, nombre UNIQUE)
--   inscripcion_clase (id_socio FK, id_clase FK, PK (id_socio, id_clase))
-- La lista en una celda pasa a ser una tabla M:N entre socio y clase.
-- =====================================================================

-- (d) MIGRACIÓN: todo dentro de una transacción
\echo
\echo '#####################################################################'
\echo '# CASO 1 - MIGRACIÓN: se crea gimnasio_norm y se copian los datos'
\echo '#####################################################################'

BEGIN;

DROP SCHEMA IF EXISTS gimnasio_norm CASCADE;   -- solo borra el esquema NUEVO
CREATE SCHEMA gimnasio_norm;

CREATE TABLE gimnasio_norm.plan (
    nombre_plan  varchar(20) PRIMARY KEY,
    valor_plan   integer     NOT NULL CHECK (valor_plan > 0)
);

CREATE TABLE gimnasio_norm.socio (
    id_socio  integer     PRIMARY KEY,
    nombre    varchar(80) NOT NULL,
    plan      varchar(20) NOT NULL REFERENCES gimnasio_norm.plan (nombre_plan)
);

CREATE TABLE gimnasio_norm.clase (
    id_clase  serial      PRIMARY KEY,
    nombre    varchar(60) NOT NULL UNIQUE
);

CREATE TABLE gimnasio_norm.inscripcion_clase (
    id_socio  integer NOT NULL REFERENCES gimnasio_norm.socio (id_socio),
    id_clase  integer NOT NULL REFERENCES gimnasio_norm.clase (id_clase),
    PRIMARY KEY (id_socio, id_clase)
);

INSERT INTO gimnasio_norm.plan (nombre_plan, valor_plan)
SELECT DISTINCT plan, valor_plan FROM gimnasio.socio;

INSERT INTO gimnasio_norm.socio (id_socio, nombre, plan)
SELECT id_socio, nombre, plan FROM gimnasio.socio;

-- Se parte por ';', se quitan espacios (trim) y se unifica la escritura:
-- primera letra en mayúscula y el resto en minúscula ('yoga ' -> 'Yoga').
-- Se usa upper(left())||lower(substr()) y no initcap() para conservar
-- 'Spinning avanzado' y no convertirlo en 'Spinning Avanzado'.
-- string_to_table(NULL, ';') no produce filas: el socio 5 queda sin inscripciones.
INSERT INTO gimnasio_norm.clase (nombre)
SELECT DISTINCT upper(left(trim(c.pedazo), 1)) || lower(substr(trim(c.pedazo), 2))
FROM gimnasio.socio s
CROSS JOIN LATERAL string_to_table(s.clases, ';') AS c(pedazo)
WHERE trim(c.pedazo) <> '';

INSERT INTO gimnasio_norm.inscripcion_clase (id_socio, id_clase)
SELECT DISTINCT s.id_socio, cl.id_clase
FROM gimnasio.socio s
CROSS JOIN LATERAL string_to_table(s.clases, ';') AS c(pedazo)
JOIN gimnasio_norm.clase cl
  ON cl.nombre = upper(left(trim(c.pedazo), 1)) || lower(substr(trim(c.pedazo), 2))
WHERE trim(c.pedazo) <> '';

-- (e) VERIFICACIÓN antes de confirmar
\echo '--- Verificación: esperado vs obtenido ---'
SELECT 'plan' AS tabla, 3 AS esperado, count(*) AS obtenido FROM gimnasio_norm.plan
UNION ALL SELECT 'socio',             6, count(*) FROM gimnasio_norm.socio
UNION ALL SELECT 'clase',             5, count(*) FROM gimnasio_norm.clase
UNION ALL SELECT 'inscripcion_clase', 9, count(*) FROM gimnasio_norm.inscripcion_clase;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM gimnasio_norm.plan) = 3,              'plan: se esperaban 3';
    ASSERT (SELECT count(*) FROM gimnasio_norm.socio) = 6,             'socio: se esperaban 6';
    ASSERT (SELECT count(*) FROM gimnasio_norm.clase) = 5,             'clase: se esperaban 5';
    ASSERT (SELECT count(*) FROM gimnasio_norm.inscripcion_clase) = 9, 'inscripcion_clase: se esperaban 9';
END $$;

\echo '--- Verificación EXCEPT (socio + plan): lo reconstruido con joins vs lo original (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT id_socio, nombre, plan, valor_plan FROM gimnasio.socio
), nuevo AS (
    SELECT s.id_socio, s.nombre, s.plan, p.valor_plan
    FROM gimnasio_norm.socio s
    JOIN gimnasio_norm.plan p ON p.nombre_plan = s.plan
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

\echo '--- Verificación EXCEPT (clases): la lista vieja desarmada vs las inscripciones nuevas (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT s.id_socio,
           upper(left(trim(c.pedazo), 1)) || lower(substr(trim(c.pedazo), 2)) AS clase
    FROM gimnasio.socio s
    CROSS JOIN LATERAL string_to_table(s.clases, ';') AS c(pedazo)
    WHERE trim(c.pedazo) <> ''
), nuevo AS (
    SELECT ic.id_socio, cl.nombre AS clase
    FROM gimnasio_norm.inscripcion_clase ic
    JOIN gimnasio_norm.clase cl ON cl.id_clase = ic.id_clase
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

COMMIT;

-- =====================================================================
-- DESPUÉS: ESQUEMA CORREGIDO Y NORMALIZADO
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# CASO 1 - DESPUÉS: esquema corregido gimnasio_norm'
\echo '#####################################################################'

\echo '--- Estructura nueva (tablas con sus PK, FK y UNIQUE) ---'
\d gimnasio_norm.plan
\d gimnasio_norm.socio
\d gimnasio_norm.clase
\d gimnasio_norm.inscripcion_clase

\echo '--- Datos nuevos ---'
SELECT * FROM gimnasio_norm.plan ORDER BY nombre_plan;
SELECT * FROM gimnasio_norm.socio ORDER BY id_socio;
SELECT * FROM gimnasio_norm.clase ORDER BY id_clase;
SELECT * FROM gimnasio_norm.inscripcion_clase ORDER BY id_socio, id_clase;

\echo '--- DESPUÉS: la queja resuelta (Yoga = 3 y Spinning = 2; Spinning avanzado va aparte) ---'
SELECT cl.nombre AS clase, count(*) AS socios
FROM gimnasio_norm.inscripcion_clase ic
JOIN gimnasio_norm.clase cl ON cl.id_clase = ic.id_clase
GROUP BY cl.nombre
ORDER BY cl.nombre;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM gimnasio_norm.inscripcion_clase ic
              JOIN gimnasio_norm.clase c USING (id_clase) WHERE c.nombre = 'Yoga') = 3,     'Yoga debía tener 3 socios';
    ASSERT (SELECT count(*) FROM gimnasio_norm.inscripcion_clase ic
              JOIN gimnasio_norm.clase c USING (id_clase) WHERE c.nombre = 'Spinning') = 2, 'Spinning debía tener 2 socios';
END $$;

\echo '--- DESPUÉS: cada socio con su plan y sus clases (Sofía no tiene clases: sale con clase vacía) ---'
SELECT s.id_socio, s.nombre, s.plan, p.valor_plan, c.nombre AS clase
FROM gimnasio_norm.socio s
JOIN gimnasio_norm.plan p ON p.nombre_plan = s.plan
LEFT JOIN gimnasio_norm.inscripcion_clase ic ON ic.id_socio = s.id_socio
LEFT JOIN gimnasio_norm.clase c ON c.id_clase = ic.id_clase
ORDER BY s.id_socio, c.nombre;

\echo '--- DESPUÉS: cambiar el valor de un plan es UN solo UPDATE de UNA fila (se deshace) ---'
BEGIN;
UPDATE gimnasio_norm.plan SET valor_plan = 95000 WHERE nombre_plan = 'Mensual';
SELECT s.id_socio, s.nombre, p.nombre_plan, p.valor_plan
FROM gimnasio_norm.socio s
JOIN gimnasio_norm.plan p ON p.nombre_plan = s.plan
WHERE p.nombre_plan = 'Mensual'
ORDER BY s.id_socio;
ROLLBACK;

-- =====================================================================
-- RESUMEN ANTES vs DESPUÉS
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# CASO 1 - RESUMEN: ANTES (original) vs DESPUÉS (normalizado)'
\echo '#####################################################################'
SELECT 'Socios en Yoga' AS indicador,
       (SELECT count(*) FROM gimnasio.socio WHERE clases LIKE '%Yoga%') AS antes_original,
       (SELECT count(*) FROM gimnasio_norm.inscripcion_clase ic
          JOIN gimnasio_norm.clase c USING (id_clase) WHERE c.nombre = 'Yoga') AS despues_normalizado
UNION ALL
SELECT 'Socios en Spinning',
       (SELECT count(*) FROM gimnasio.socio WHERE clases LIKE '%Spinning%'),
       (SELECT count(*) FROM gimnasio_norm.inscripcion_clase ic
          JOIN gimnasio_norm.clase c USING (id_clase) WHERE c.nombre = 'Spinning')
UNION ALL
SELECT 'Veces que se guarda el valor del plan Mensual',
       (SELECT count(valor_plan) FROM gimnasio.socio WHERE plan = 'Mensual'),
       (SELECT count(*) FROM gimnasio_norm.plan WHERE nombre_plan = 'Mensual');

-- =====================================================================
-- (f) RETIRAR LO VIEJO: solo después de verificar (conteos, ASSERT y EXCEPT
-- en 0 filas, queja resuelta). La evidencia del ANTES ya quedó en la salida.
-- =====================================================================
\echo '--- CASO 1: se elimina la tabla original gimnasio.socio (ya verificada) ---'
BEGIN;
DROP TABLE gimnasio.socio;
COMMIT;

\echo '--- Comprobación: la tabla original ya no existe (debe dar t) ---'
SELECT to_regclass('gimnasio.socio') IS NULL AS tabla_original_eliminada;

-- =====================================================================
-- PREGUNTA PROPIA (caso 1): el horario de cada clase (día y hora)
-- ¿En cuál tabla va, y por qué habría sido imposible hacerlo bien con el
-- diseño original?
--   Va en `clase`: el horario depende de la clase (id_clase -> día, hora),
--   no del socio. Si una clase tuviera varias sesiones por semana, iría en
--   una tabla hija horario_clase (id_clase FK, dia, hora,
--   PK (id_clase, dia, hora)).
--   Con el diseño original era imposible: no existía una entidad "clase",
--   solo un texto dentro de `socio`. Habría que meter el horario en la misma
--   celda ('Yoga lunes 6pm; Spinning ...'), se repetiría en cada socio
--   inscrito, un cambio de horario obligaría a editar muchas filas
--   (anomalía de actualización) y una clase sin socios no podría tener horario.
--
-- PREGUNTA ADICIONAL (caso 1): ¿por qué inscripcion_clase usa la PK
-- compuesta (id_socio, id_clase) y no un `id serial`?
--   La pareja (socio, clase) ya identifica la inscripción y, al ser PK,
--   impide inscribir dos veces al mismo socio en la misma clase. Con un
--   `id serial` la pareja podría repetirse y Yoga contaría 4 socios cuando
--   son 3 (el mismo error del caso 3). Habría que agregar además
--   UNIQUE (id_socio, id_clase), así que el `id` no aporta nada: agregar un
--   id no normaliza nada.
-- =====================================================================


-- #####################################################################
-- CASO 2: FARMACIA
--   formula (num_formula PK, fecha, doc_paciente, nombre_paciente,
--            medicamento1, dosis1, medicamento2, dosis2, medicamento3, dosis3)
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) DIAGNÓSTICO
-- ---------------------------------------------------------------------
-- Reglas del enunciado -> dependencias funcionales (DF):
--   num_formula    -> fecha, doc_paciente, medicamento1..3, dosis1..3
--   doc_paciente   -> nombre_paciente
--   (num_formula, medicamento) -> dosis   (un medicamento no se repite en una fórmula)
-- Clave candidata: num_formula (la única).
--
-- PROBLEMA PRINCIPAL (explica la queja): grupo repetido
--   (medicamento1, dosis1), (medicamento2, dosis2), (medicamento3, dosis3)
--   -> NO está en 1FN. Solo caben 3 medicamentos y para buscar uno hay que
--   revisar 3 columnas.
-- PROBLEMA SECUNDARIO: dependencia transitiva
--   num_formula -> doc_paciente -> nombre_paciente  -> incumple 3FN. Los datos
--   del paciente se repiten en cada fórmula.

\echo
\echo '#####################################################################'
\echo '# CASO 2 - ANTES: esquema original farmacia.formula (con el error)'
\echo '#####################################################################'

\echo '--- Estructura original ---'
\d farmacia.formula

\echo '--- Datos originales ---'
SELECT * FROM farmacia.formula ORDER BY num_formula;

\echo '--- ANTES (b1) La queja: para contar fórmulas con acetaminofén hay que mirar 3 columnas ---'
SELECT count(*) AS formulas_con_acetaminofen
FROM farmacia.formula
WHERE medicamento1 ILIKE 'Acetaminof%'
   OR medicamento2 ILIKE 'Acetaminof%'
   OR medicamento3 ILIKE 'Acetaminof%';

\echo '--- ANTES (b2) La queja: fórmulas que ya llenaron las 3 posiciones (no cabe un cuarto) ---'
SELECT num_formula, medicamento1, medicamento2, medicamento3
FROM farmacia.formula
WHERE medicamento3 IS NOT NULL;

\echo '--- ANTES (b3) Redundancia: los datos del paciente se repiten en cada fórmula ---'
SELECT doc_paciente, nombre_paciente, count(*) AS formulas
FROM farmacia.formula
GROUP BY doc_paciente, nombre_paciente
ORDER BY doc_paciente;

\echo '--- ANTES (b4) ¿Los datos contradicen doc_paciente -> nombre_paciente? (0 filas = no) ---'
SELECT doc_paciente FROM farmacia.formula
GROUP BY doc_paciente HAVING count(DISTINCT nombre_paciente) > 1;

\echo '--- ANTES (b5) Anomalía de actualización: corregir el nombre en UNA sola fila (se deshace) ---'
BEGIN;
UPDATE farmacia.formula SET nombre_paciente = 'Rosa Diaz' WHERE num_formula = 701;
-- La misma paciente queda con DOS nombres: los datos se contradicen.
SELECT doc_paciente, nombre_paciente, count(*) AS formulas
FROM farmacia.formula
WHERE doc_paciente = '1110000111'
GROUP BY doc_paciente, nombre_paciente
ORDER BY nombre_paciente;
ROLLBACK;

\echo '--- Conteos ESPERADOS, calculados antes de migrar ---'
SELECT count(DISTINCT doc_paciente) AS pacientes_esperados,   -- 3
       count(*)                     AS formulas_esperadas,    -- 4
       count(medicamento1) + count(medicamento2) + count(medicamento3)
                                    AS medicamentos_esperados -- 8 (2 + 1 + 3 + 2)
FROM farmacia.formula;

-- =====================================================================
-- (c) ESQUEMA CORREGIDO  (esquema nuevo: farmacia_norm)
--   paciente        (doc_paciente PK, nombre_paciente)
--   formula         (num_formula PK, fecha, doc_paciente FK -> paciente)
--   detalle_formula (num_formula FK, medicamento, dosis,
--                    PK (num_formula, medicamento))
-- La PK compuesta de detalle_formula garantiza que un medicamento no se
-- repita en la misma fórmula.
-- =====================================================================

-- (d) MIGRACIÓN: todo dentro de una transacción
\echo
\echo '#####################################################################'
\echo '# CASO 2 - MIGRACIÓN: se crea farmacia_norm y se copian los datos'
\echo '#####################################################################'

BEGIN;

DROP SCHEMA IF EXISTS farmacia_norm CASCADE;   -- solo borra el esquema NUEVO
CREATE SCHEMA farmacia_norm;

CREATE TABLE farmacia_norm.paciente (
    doc_paciente     varchar(15) PRIMARY KEY,
    nombre_paciente  varchar(80) NOT NULL
);

CREATE TABLE farmacia_norm.formula (
    num_formula   integer     PRIMARY KEY,
    fecha         date        NOT NULL,
    doc_paciente  varchar(15) NOT NULL REFERENCES farmacia_norm.paciente (doc_paciente)
);

CREATE TABLE farmacia_norm.detalle_formula (
    num_formula  integer     NOT NULL REFERENCES farmacia_norm.formula (num_formula),
    medicamento  varchar(60) NOT NULL,
    dosis        varchar(40) NOT NULL,
    PRIMARY KEY (num_formula, medicamento)
);

INSERT INTO farmacia_norm.paciente (doc_paciente, nombre_paciente)
SELECT DISTINCT doc_paciente, nombre_paciente FROM farmacia.formula;

INSERT INTO farmacia_norm.formula (num_formula, fecha, doc_paciente)
SELECT num_formula, fecha, doc_paciente FROM farmacia.formula;

-- Columnas numeradas -> filas (UNION ALL). El medicamento 1 siempre existe
-- (NOT NULL); los 2 y 3 solo cuando no son NULL.
INSERT INTO farmacia_norm.detalle_formula (num_formula, medicamento, dosis)
SELECT num_formula, medicamento1, dosis1 FROM farmacia.formula
UNION ALL
SELECT num_formula, medicamento2, dosis2 FROM farmacia.formula WHERE medicamento2 IS NOT NULL
UNION ALL
SELECT num_formula, medicamento3, dosis3 FROM farmacia.formula WHERE medicamento3 IS NOT NULL;

-- (e) VERIFICACIÓN antes de confirmar
\echo '--- Verificación: esperado vs obtenido ---'
SELECT 'paciente' AS tabla, 3 AS esperado, count(*) AS obtenido FROM farmacia_norm.paciente
UNION ALL SELECT 'formula',         4, count(*) FROM farmacia_norm.formula
UNION ALL SELECT 'detalle_formula', 8, count(*) FROM farmacia_norm.detalle_formula;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM farmacia_norm.paciente) = 3,        'paciente: se esperaban 3';
    ASSERT (SELECT count(*) FROM farmacia_norm.formula) = 4,         'formula: se esperaban 4';
    ASSERT (SELECT count(*) FROM farmacia_norm.detalle_formula) = 8, 'detalle_formula: se esperaban 8';
END $$;

\echo '--- Verificación EXCEPT (encabezado): lo reconstruido con joins vs lo original (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT num_formula, fecha, doc_paciente, nombre_paciente FROM farmacia.formula
), nuevo AS (
    SELECT f.num_formula, f.fecha, f.doc_paciente, p.nombre_paciente
    FROM farmacia_norm.formula f
    JOIN farmacia_norm.paciente p ON p.doc_paciente = f.doc_paciente
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

\echo '--- Verificación EXCEPT (medicamentos): lo viejo desarmado vs lo nuevo (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT num_formula, medicamento1 AS medicamento, dosis1 AS dosis FROM farmacia.formula
    UNION ALL
    SELECT num_formula, medicamento2, dosis2 FROM farmacia.formula WHERE medicamento2 IS NOT NULL
    UNION ALL
    SELECT num_formula, medicamento3, dosis3 FROM farmacia.formula WHERE medicamento3 IS NOT NULL
), nuevo AS (
    SELECT num_formula, medicamento, dosis FROM farmacia_norm.detalle_formula
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

COMMIT;

-- =====================================================================
-- DESPUÉS: ESQUEMA CORREGIDO Y NORMALIZADO
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# CASO 2 - DESPUÉS: esquema corregido farmacia_norm'
\echo '#####################################################################'

\echo '--- Estructura nueva (tablas con sus PK y FK) ---'
\d farmacia_norm.paciente
\d farmacia_norm.formula
\d farmacia_norm.detalle_formula

\echo '--- Datos nuevos ---'
SELECT * FROM farmacia_norm.paciente ORDER BY doc_paciente;
SELECT * FROM farmacia_norm.formula ORDER BY num_formula;
SELECT * FROM farmacia_norm.detalle_formula ORDER BY num_formula, medicamento;

\echo '--- DESPUÉS: la queja (2) resuelta: acetaminofén se busca en UNA sola columna (debe dar 3) ---'
SELECT count(DISTINCT num_formula) AS formulas_con_acetaminofen
FROM farmacia_norm.detalle_formula
WHERE medicamento ILIKE 'Acetaminof%';

DO $$
BEGIN
    ASSERT (SELECT count(DISTINCT num_formula) FROM farmacia_norm.detalle_formula
             WHERE medicamento ILIKE 'Acetaminof%') = 3, 'acetaminofén: se esperaban 3 fórmulas';
END $$;

\echo '--- DESPUÉS: la queja (1) resuelta: un cuarto medicamento es solo un INSERT (se deshace) ---'
BEGIN;
INSERT INTO farmacia_norm.detalle_formula (num_formula, medicamento, dosis)
VALUES (703, 'Vitamina C 500 mg', 'cada 24 h');
SELECT num_formula, count(*) AS medicamentos
FROM farmacia_norm.detalle_formula
WHERE num_formula = 703
GROUP BY num_formula;
ROLLBACK;

\echo '--- DESPUÉS: la base ahora rechaza un medicamento repetido en la misma fórmula (debe salir NOTICE OK) ---'
DO $$
BEGIN
    INSERT INTO farmacia_norm.detalle_formula VALUES (701, 'Acetaminofén 500 mg', 'cada 4 h');
    RAISE EXCEPTION 'ERROR: la base aceptó un medicamento repetido';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: la PK rechazó el medicamento repetido';
END $$;

-- =====================================================================
-- RESUMEN ANTES vs DESPUÉS
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# CASO 2 - RESUMEN: ANTES (original) vs DESPUÉS (normalizado)'
\echo '#####################################################################'
SELECT 'Fórmulas con acetaminofén' AS indicador,
       (SELECT count(*) FROM farmacia.formula
         WHERE medicamento1 ILIKE 'Acetaminof%' OR medicamento2 ILIKE 'Acetaminof%'
            OR medicamento3 ILIKE 'Acetaminof%') AS antes_original,
       (SELECT count(DISTINCT num_formula) FROM farmacia_norm.detalle_formula
         WHERE medicamento ILIKE 'Acetaminof%') AS despues_normalizado
UNION ALL
SELECT 'Columnas que hay que revisar para buscar un medicamento', 3::bigint, 1::bigint
UNION ALL
SELECT 'Veces que se guarda el nombre de Rosa Díaz',
       (SELECT count(*) FROM farmacia.formula WHERE doc_paciente = '1110000111'),
       (SELECT count(*) FROM farmacia_norm.paciente WHERE doc_paciente = '1110000111');

-- =====================================================================
-- (f) RETIRAR LO VIEJO: solo después de verificar (conteos, ASSERT y EXCEPT
-- en 0 filas, queja resuelta). La evidencia del ANTES ya quedó en la salida.
-- =====================================================================
\echo '--- CASO 2: se elimina la tabla original farmacia.formula (ya verificada) ---'
BEGIN;
DROP TABLE farmacia.formula;
COMMIT;

\echo '--- Comprobación: la tabla original ya no existe (debe dar t) ---'
SELECT to_regclass('farmacia.formula') IS NULL AS tabla_original_eliminada;

-- =====================================================================
-- PREGUNTA PROPIA (caso 2): ¿por qué no basta con agregar medicamento4 y dosis4?
--  1) Solo corre el límite: el día que un médico recete cinco medicamentos
--     habrá que repetir el ALTER TABLE. El máximo lo decide el esquema, no el
--     negocio.
--  2) Cada columna nueva se llena de NULL en casi todas las filas (la mayoría
--     de fórmulas tienen 1 o 2 medicamentos).
--  3) Las consultas se multiplican: buscar un medicamento exige
--     `col1 = X OR col2 = X OR col3 = X OR col4 = X`, y cada columna nueva
--     obliga a reescribir todas las consultas y reportes.
--  4) No se puede declarar con una restricción simple la regla "un medicamento
--     no se repite en la misma fórmula". Con filas basta una PK
--     (num_formula, medicamento); con columnas haría falta un CHECK que
--     compare todas las columnas entre sí.
--  5) La relación medicamento-dosis depende de que el número de la columna
--     coincida (medicamento3 con dosis3); nada impide desparejarlas.
-- =====================================================================


-- #####################################################################
-- CASO 3: CURSOS LIBRES
--   inscripcion (id PK serial, doc_participante, nombre_participante, correo,
--                cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) DIAGNÓSTICO
-- ---------------------------------------------------------------------
-- Reglas del enunciado -> dependencias funcionales (DF):
--   doc_participante -> nombre_participante, correo
--   correo           -> doc_participante        (el correo identifica a un participante)
--   cod_curso        -> nombre_curso, cod_sede  (cada curso se dicta en una sola sede)
--   cod_sede         -> direccion_sede
--   (doc_participante, cod_curso) -> valor_pagado
-- Claves candidatas: id, (doc_participante, cod_curso), (correo, cod_curso).
--   Las dos últimas nunca se declararon.
--
-- PROBLEMA PRINCIPAL (explica la queja): falta UNIQUE (doc_participante, cod_curso).
--   La inscripción de Juliana Rey a Fotografía digital está dos veces y
--   se suma dos veces: son los 200 000 de más.
-- PROBLEMAS SECUNDARIOS:
--   * 2FN: nombre_participante y correo dependen solo de doc_participante;
--     nombre_curso y cod_sede dependen solo de cod_curso (dependencias de
--     PARTE de una clave candidata). La PK `id` no lo evita: las formas
--     normales se miden contra TODAS las claves candidatas.
--   * 3FN: cod_curso -> cod_sede -> direccion_sede (transitiva).
--   * 1FN: sí cumple.

-- =====================================================================
-- ANTES: ESQUEMA ORIGINAL (con el error)
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# ANTES: esquema original cursos_libres.inscripcion (con el error)'
\echo '#####################################################################'

\echo '--- Estructura original ---'
\d cursos_libres.inscripcion

\echo '--- Datos originales ---'
SELECT * FROM cursos_libres.inscripcion ORDER BY id;

\echo '--- ANTES (b1) Filas repetidas en la clave natural: falta el UNIQUE ---'
SELECT doc_participante, cod_curso, count(*) AS veces
FROM cursos_libres.inscripcion
GROUP BY doc_participante, cod_curso
HAVING count(*) > 1;

\echo '--- ANTES (b2) La queja: recaudo por curso (Fotografía digital sale inflado) ---'
SELECT cod_curso, nombre_curso, count(*) AS filas, sum(valor_pagado) AS recaudo
FROM cursos_libres.inscripcion
GROUP BY cod_curso, nombre_curso
ORDER BY cod_curso;
-- Fotografía digital: 580 000. Lo correcto es 380 000 (200 000 + 180 000).

\echo '--- ANTES (b3) Redundancia: la dirección de la sede se repite en cada inscripción ---'
SELECT cod_sede, direccion_sede, count(*) AS filas
FROM cursos_libres.inscripcion
GROUP BY cod_sede, direccion_sede
ORDER BY cod_sede;

\echo '--- ANTES (b4) Redundancia: los datos del participante se repiten ---'
SELECT doc_participante, nombre_participante, correo, count(*) AS filas
FROM cursos_libres.inscripcion
GROUP BY doc_participante, nombre_participante, correo
ORDER BY doc_participante;

\echo '--- ANTES (b5) ¿Los datos contradicen alguna DF? (0 filas = no hay contradicción) ---'
SELECT doc_participante FROM cursos_libres.inscripcion
    GROUP BY doc_participante
HAVING count(DISTINCT nombre_participante) > 1 OR count(DISTINCT correo) > 1;

SELECT correo FROM cursos_libres.inscripcion
    GROUP BY correo HAVING count(DISTINCT doc_participante) > 1;

SELECT cod_curso FROM cursos_libres.inscripcion
    GROUP BY cod_curso
HAVING count(DISTINCT nombre_curso) > 1 OR count(DISTINCT cod_sede) > 1;

SELECT cod_sede FROM cursos_libres.inscripcion
    GROUP BY cod_sede HAVING count(DISTINCT direccion_sede) > 1;

-- DECISIÓN sobre el dato duplicado (queda escrito por qué):
--   Las dos filas de Juliana Rey en C20 tienen el mismo valor (200 000) y
--   solo difieren en `id`. La regla dice "a lo sumo una vez por curso" y
--   Contabilidad reporta exactamente 200 000 de diferencia: es un registro
--   doble. Se conserva la primera (menor id) y se descarta la otra.

\echo '--- Conteos ESPERADOS, calculados antes de migrar ---'
SELECT count(DISTINCT doc_participante) AS participantes_esperados,   -- 4
        count(DISTINCT cod_sede)         AS sedes_esperadas,           -- 2
        count(DISTINCT cod_curso)        AS cursos_esperados,          -- 3
        (SELECT count(*) FROM (SELECT DISTINCT doc_participante, cod_curso
                                FROM cursos_libres.inscripcion) x)
                                        AS inscripciones_esperadas,   -- 7 (8 menos 1 duplicada)
        sum(valor_pagado) - 200000       AS recaudo_total_esperado     -- 1 370 000 - 200 000 = 1 170 000
FROM cursos_libres.inscripcion;

-- =====================================================================
-- (c) ESQUEMA CORREGIDO  (esquema nuevo: cursos_libres_norm)
--   participante (doc_participante PK, nombre, correo UNIQUE)
--   sede         (cod_sede PK, direccion)
--   curso        (cod_curso PK, nombre, cod_sede FK -> sede)
--   inscripcion  (doc_participante FK, cod_curso FK, valor_pagado,
--                 PK (doc_participante, cod_curso))
-- La clave natural pasa a ser la PK, así que ya no hace falta el `id`.
-- =====================================================================

-- (d) MIGRACIÓN: todo dentro de una transacción
\echo
\echo '#####################################################################'
\echo '# MIGRACIÓN: se crea cursos_libres_norm y se copian los datos'
\echo '#####################################################################'

BEGIN;

DROP SCHEMA IF EXISTS cursos_libres_norm CASCADE;   -- solo borra el esquema NUEVO
CREATE SCHEMA cursos_libres_norm;

CREATE TABLE cursos_libres_norm.sede (
    cod_sede   char(2)     PRIMARY KEY,
    direccion  varchar(60) NOT NULL
);

CREATE TABLE cursos_libres_norm.curso (
    cod_curso  char(3)     PRIMARY KEY,
    nombre     varchar(60) NOT NULL,
    cod_sede   char(2)     NOT NULL REFERENCES cursos_libres_norm.sede
);

CREATE TABLE cursos_libres_norm.participante (
    doc_participante  varchar(15)  PRIMARY KEY,
    nombre            varchar(80)  NOT NULL,
    correo            varchar(120) NOT NULL UNIQUE
);

CREATE TABLE cursos_libres_norm.inscripcion (
    doc_participante  varchar(15) NOT NULL REFERENCES cursos_libres_norm.participante,
    cod_curso         char(3)     NOT NULL REFERENCES cursos_libres_norm.curso,
    valor_pagado      integer     NOT NULL CHECK (valor_pagado >= 0),
    PRIMARY KEY (doc_participante, cod_curso)
);

INSERT INTO cursos_libres_norm.sede
SELECT DISTINCT cod_sede, direccion_sede FROM cursos_libres.inscripcion;

INSERT INTO cursos_libres_norm.curso
SELECT DISTINCT cod_curso, nombre_curso, cod_sede FROM cursos_libres.inscripcion;

INSERT INTO cursos_libres_norm.participante
SELECT DISTINCT doc_participante, nombre_participante, correo FROM cursos_libres.inscripcion;

-- DISTINCT ON deja una sola fila por (participante, curso): la de menor id
INSERT INTO cursos_libres_norm.inscripcion (doc_participante, cod_curso, valor_pagado)
SELECT DISTINCT ON (doc_participante, cod_curso) doc_participante, cod_curso, valor_pagado
FROM cursos_libres.inscripcion
ORDER BY doc_participante, cod_curso, id;

-- (e) VERIFICACIÓN antes de confirmar
\echo '--- Verificación: esperado vs obtenido ---'
SELECT 'participante' AS tabla, 4 AS esperado, count(*) AS obtenido FROM cursos_libres_norm.participante
UNION ALL SELECT 'sede',                       2,       count(*) FROM cursos_libres_norm.sede
UNION ALL SELECT 'curso',                      3,       count(*) FROM cursos_libres_norm.curso
UNION ALL SELECT 'inscripcion',                7,       count(*) FROM cursos_libres_norm.inscripcion
UNION ALL SELECT 'recaudo total (1 170 000)',  1170000, sum(valor_pagado) FROM cursos_libres_norm.inscripcion;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM cursos_libres_norm.participante) = 4, 'participante: se esperaban 4';
    ASSERT (SELECT count(*) FROM cursos_libres_norm.sede) = 2,         'sede: se esperaban 2';
    ASSERT (SELECT count(*) FROM cursos_libres_norm.curso) = 3,        'curso: se esperaban 3';
    ASSERT (SELECT count(*) FROM cursos_libres_norm.inscripcion) = 7,  'inscripcion: se esperaban 7';
    ASSERT (SELECT sum(valor_pagado) FROM cursos_libres_norm.inscripcion) = 1170000, 'recaudo: se esperaba 1 170 000';
END $$;

\echo '--- Verificación EXCEPT: lo reconstruido con joins vs lo original (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT doc_participante, nombre_participante, correo, cod_curso, nombre_curso,
            cod_sede, direccion_sede, valor_pagado
    FROM cursos_libres.inscripcion
), nuevo AS (
    SELECT i.doc_participante, p.nombre AS nombre_participante, p.correo, i.cod_curso,
            c.nombre AS nombre_curso, c.cod_sede, s.direccion AS direccion_sede, i.valor_pagado
    FROM cursos_libres_norm.inscripcion i
    JOIN cursos_libres_norm.participante p ON p.doc_participante = i.doc_participante
    JOIN cursos_libres_norm.curso c        ON c.cod_curso = i.cod_curso
    JOIN cursos_libres_norm.sede s         ON s.cod_sede = c.cod_sede
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

COMMIT;

-- =====================================================================
-- DESPUÉS: ESQUEMA CORREGIDO Y NORMALIZADO
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# DESPUÉS: esquema corregido cursos_libres_norm'
\echo '#####################################################################'

\echo '--- Estructura nueva (tablas con sus PK, FK y UNIQUE) ---'
\d cursos_libres_norm.sede
\d cursos_libres_norm.curso
\d cursos_libres_norm.participante
\d cursos_libres_norm.inscripcion

\echo '--- Datos nuevos ---'
SELECT * FROM cursos_libres_norm.sede ORDER BY cod_sede;
SELECT * FROM cursos_libres_norm.curso ORDER BY cod_curso;
SELECT * FROM cursos_libres_norm.participante ORDER BY doc_participante;
SELECT * FROM cursos_libres_norm.inscripcion ORDER BY doc_participante, cod_curso;

\echo '--- DESPUÉS: la queja resuelta (Fotografía digital = 380 000) ---'
SELECT c.nombre AS curso, count(*) AS inscripciones, sum(i.valor_pagado) AS recaudo
FROM cursos_libres_norm.inscripcion i
JOIN cursos_libres_norm.curso c USING (cod_curso)
GROUP BY c.nombre
ORDER BY c.nombre;

\echo '--- DESPUÉS: los datos originales se pueden reconstruir con joins ---'
SELECT p.nombre AS participante, p.correo, c.nombre AS curso, s.direccion AS sede, i.valor_pagado
FROM cursos_libres_norm.inscripcion i
JOIN cursos_libres_norm.participante p ON p.doc_participante = i.doc_participante
JOIN cursos_libres_norm.curso c        ON c.cod_curso = i.cod_curso
JOIN cursos_libres_norm.sede s         ON s.cod_sede = c.cod_sede
ORDER BY c.cod_curso, p.nombre;

\echo '--- DESPUÉS: la base ahora rechaza el duplicado (debe salir NOTICE OK) ---'
DO $$
BEGIN
    INSERT INTO cursos_libres_norm.inscripcion VALUES ('1140000900', 'C20', 200000);
    RAISE EXCEPTION 'ERROR: la base aceptó un duplicado';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: la PK rechazó la inscripción duplicada';
END $$;

-- =====================================================================
-- RESUMEN ANTES vs DESPUÉS
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# RESUMEN: ANTES (original) vs DESPUÉS (normalizado)'
\echo '#####################################################################'
SELECT 'Recaudo de Fotografía digital' AS indicador,
        (SELECT sum(valor_pagado) FROM cursos_libres.inscripcion WHERE cod_curso = 'C20')       AS antes_original,
        (SELECT sum(valor_pagado) FROM cursos_libres_norm.inscripcion WHERE cod_curso = 'C20')  AS despues_normalizado
UNION ALL
SELECT 'Filas de inscripción',
        (SELECT count(*) FROM cursos_libres.inscripcion),
        (SELECT count(*) FROM cursos_libres_norm.inscripcion)
UNION ALL
SELECT 'Veces que se guarda una dirección de sede',
        (SELECT count(direccion_sede) FROM cursos_libres.inscripcion),
        (SELECT count(*) FROM cursos_libres_norm.sede)
UNION ALL
SELECT 'Veces que se guarda un nombre de participante',
        (SELECT count(nombre_participante) FROM cursos_libres.inscripcion),
        (SELECT count(*) FROM cursos_libres_norm.participante);

-- =====================================================================
-- (f) RETIRAR LO VIEJO: solo después de verificar (conteos, ASSERT y EXCEPT
-- en 0 filas, queja resuelta). La evidencia del ANTES ya quedó en la salida.
-- =====================================================================
\echo '--- CASO 3: se elimina la tabla original cursos_libres.inscripcion (ya verificada) ---'
BEGIN;
DROP TABLE cursos_libres.inscripcion;
COMMIT;

\echo '--- Comprobación: la tabla original ya no existe (debe dar t) ---'
SELECT to_regclass('cursos_libres.inscripcion') IS NULL AS tabla_original_eliminada;

-- =====================================================================
-- PREGUNTA PROPIA (caso 3)
-- ¿Por qué la PK de una sola columna no pone la tabla en 2FN?
--   Porque las formas normales se definen respecto a TODAS las claves
--   candidatas, no solo a la PK elegida. (doc_participante, cod_curso)
--   identifica una inscripción según las reglas del negocio, así que es
--   clave candidata aunque nadie la declaró, y nombre_participante
--   depende solo de una parte de ella (doc_participante). Agregar un `id`
--   solo cambió el nombre de la PK; no normalizó nada.
--
-- ¿Qué restricción faltaba y qué habría evitado?
--   UNIQUE (doc_participante, cod_curso) (y UNIQUE sobre correo). Con ella
--   la base habría rechazado la segunda inscripción de Juliana a
--   Fotografía digital y nunca habrían aparecido los 200 000 de más.
-- =====================================================================


-- #####################################################################
-- CASO 4: ENVÍOS
--   envio (num_guia PK, fecha, ciudad_destino, departamento, zona,
--          tarifa_kg, peso_kg, valor)
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) DIAGNÓSTICO
-- ---------------------------------------------------------------------
-- Reglas del enunciado -> dependencias funcionales (DF):
--   num_guia       -> fecha, ciudad_destino, peso_kg
--   ciudad_destino -> departamento, zona
--   zona           -> tarifa_kg
--   (peso_kg, tarifa_kg) -> valor        (valor = peso × tarifa)
-- Clave candidata: num_guia (la única).
--
-- PROBLEMA PRINCIPAL (explica la queja): nada amarra `valor` a la regla
--   peso × tarifa, y un registro la contradice. G07 (Bogotá, 4 kg × 6 000)
--   debería valer 24 000 y dice 42 000: se cobraron 18 000 de más.
--   Guardar `valor` NO es el error: es lo cobrado en su fecha (dato
--   histórico, ver la pregunta propia). El error es el registro que
--   contradice la regla.
-- PROBLEMAS SECUNDARIOS (3FN, dependencias transitivas):
--   * num_guia -> ciudad_destino -> zona -> tarifa_kg
--   * num_guia -> ciudad_destino -> departamento
--   Los datos de la ciudad y la tarifa de la zona se repiten en cada
--   envío; cambiar una tarifa obliga a editar muchas filas.

-- =====================================================================
-- ANTES: ESQUEMA ORIGINAL (con el error)
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# ANTES: esquema original envios.envio (con el error)'
\echo '#####################################################################'

\echo '--- Estructura original ---'
\d envios.envio

\echo '--- Datos originales ---'
SELECT * FROM envios.envio ORDER BY num_guia;

\echo '--- ANTES (b1) La queja: valor guardado distinto de peso × tarifa ---'
SELECT num_guia, ciudad_destino, peso_kg, tarifa_kg, valor,
       (peso_kg * tarifa_kg)::integer          AS valor_esperado,
       valor - (peso_kg * tarifa_kg)::integer  AS cobrado_de_mas
FROM envios.envio
WHERE valor <> peso_kg * tarifa_kg;
-- Solo G07: 42 000 cobrado contra 24 000 esperado.

\echo '--- ANTES (b2) Redundancia: la tarifa de la zona se repite en cada envío ---'
SELECT zona, tarifa_kg, count(*) AS envios
FROM envios.envio
GROUP BY zona, tarifa_kg
ORDER BY zona;

\echo '--- ANTES (b3) Redundancia: departamento y zona se repiten por ciudad ---'
SELECT ciudad_destino, departamento, zona, count(*) AS envios
FROM envios.envio
GROUP BY ciudad_destino, departamento, zona
ORDER BY ciudad_destino;

\echo '--- ANTES (b4) ¿Los datos contradicen alguna DF? (0 filas = no) ---'
SELECT ciudad_destino FROM envios.envio
    GROUP BY ciudad_destino
HAVING count(DISTINCT departamento) > 1 OR count(DISTINCT zona) > 1;

SELECT zona FROM envios.envio GROUP BY zona HAVING count(DISTINCT tarifa_kg) > 1;

\echo '--- ANTES (b5) Anomalía de actualización: cambiar la tarifa en UNA sola fila (se deshace) ---'
BEGIN;
UPDATE envios.envio SET tarifa_kg = 7000 WHERE num_guia = 'G03';
-- La zona 2 queda con DOS tarifas: los datos se contradicen.
SELECT zona, tarifa_kg, count(*) AS envios
FROM envios.envio
WHERE zona = 2
GROUP BY zona, tarifa_kg
ORDER BY tarifa_kg;
ROLLBACK;

-- DECISIÓN sobre el dato en conflicto (queda escrito por qué):
--   El error es `valor`, no la tarifa: la tarifa de la zona 2 (6 000) es la
--   misma en todos sus envíos y el peso de G07 (4.0 kg) no está en
--   discusión. La regla del negocio (valor = peso × tarifa) manda y el
--   reclamo del cliente (cobro de más) coincide. En el esquema nuevo el
--   valor de G07 se corrige a 24 000; Facturación debe revisar la
--   devolución de 18 000.

\echo '--- Conteos ESPERADOS, calculados antes de migrar ---'
SELECT count(*)                       AS envios_esperados,    -- 8
        count(DISTINCT ciudad_destino) AS ciudades_esperadas,  -- 5
        count(DISTINCT zona)           AS zonas_esperadas      -- 3
FROM envios.envio;

-- =====================================================================
-- (c) ESQUEMA CORREGIDO  (esquema nuevo: envios_norm)
--   zona   (zona PK, tarifa_kg)
--   ciudad (ciudad PK, departamento, zona FK -> zona)
--   envio  (num_guia PK, fecha, ciudad_destino FK -> ciudad, peso_kg, valor)
--   VISTA envio_calculado: tarifa, zona, departamento y el valor que daría
--   la tarifa ACTUAL (sirve para auditar).
--
-- Sobre `valor`: se guarda como el valor COBRADO en su fecha (dato
-- histórico, ver la pregunta propia al final). Se carga con el valor
-- original y solo se corrige G07 (ver DECISIÓN arriba).
-- =====================================================================

-- (d) MIGRACIÓN: todo dentro de una transacción
\echo
\echo '#####################################################################'
\echo '# MIGRACIÓN: se crea envios_norm y se copian los datos'
\echo '#####################################################################'

BEGIN;

DROP SCHEMA IF EXISTS envios_norm CASCADE;   -- solo borra el esquema NUEVO
CREATE SCHEMA envios_norm;

CREATE TABLE envios_norm.zona (
    zona       smallint PRIMARY KEY,
    tarifa_kg  integer  NOT NULL CHECK (tarifa_kg > 0)
);

CREATE TABLE envios_norm.ciudad (
    ciudad        varchar(40) PRIMARY KEY,
    departamento  varchar(40) NOT NULL,
    zona          smallint    NOT NULL REFERENCES envios_norm.zona
);

CREATE TABLE envios_norm.envio (
    num_guia        char(3)       PRIMARY KEY,
    fecha           date          NOT NULL,
    ciudad_destino  varchar(40)   NOT NULL REFERENCES envios_norm.ciudad,
    peso_kg         numeric(5,1)  NOT NULL CHECK (peso_kg > 0),
    valor           integer       NOT NULL CHECK (valor >= 0)
);

INSERT INTO envios_norm.zona
SELECT DISTINCT zona, tarifa_kg FROM envios.envio;

INSERT INTO envios_norm.ciudad
SELECT DISTINCT ciudad_destino, departamento, zona FROM envios.envio;

-- Se copia el valor original (dato histórico) y se corrige SOLO la guía G07
INSERT INTO envios_norm.envio (num_guia, fecha, ciudad_destino, peso_kg, valor)
SELECT num_guia, fecha, ciudad_destino, peso_kg, valor
FROM envios.envio;

UPDATE envios_norm.envio SET valor = 24000 WHERE num_guia = 'G07';   -- 4.0 kg x 6 000

CREATE VIEW envios_norm.envio_calculado AS
SELECT e.num_guia, e.fecha, e.ciudad_destino, c.departamento, c.zona, z.tarifa_kg,
        e.peso_kg, e.valor AS valor_cobrado,
       (e.peso_kg * z.tarifa_kg)::integer AS valor_calculado
FROM envios_norm.envio e
JOIN envios_norm.ciudad c ON c.ciudad = e.ciudad_destino
JOIN envios_norm.zona z   ON z.zona = c.zona;

-- (e) VERIFICACIÓN antes de confirmar
\echo '--- Verificación: esperado vs obtenido ---'
SELECT 'zona' AS tabla, 3 AS esperado, count(*) AS obtenido FROM envios_norm.zona
UNION ALL SELECT 'ciudad', 5, count(*) FROM envios_norm.ciudad
UNION ALL SELECT 'envio',  8, count(*) FROM envios_norm.envio;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM envios_norm.zona) = 3,   'zona: se esperaban 3';
    ASSERT (SELECT count(*) FROM envios_norm.ciudad) = 5, 'ciudad: se esperaban 5';
    ASSERT (SELECT count(*) FROM envios_norm.envio) = 8,  'envio: se esperaban 8';
END $$;

\echo '--- Verificación EXCEPT: lo reconstruido con joins vs lo original (ambos sentidos, 0 filas) ---'
WITH viejo AS (
    SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg
    FROM envios.envio
), nuevo AS (
    SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg
    FROM envios_norm.envio_calculado
)
(SELECT * FROM viejo EXCEPT SELECT * FROM nuevo)
UNION ALL
(SELECT * FROM nuevo EXCEPT SELECT * FROM viejo);

\echo '--- Verificación del valor: solo G07 debe cambiar (42 000 -> 24 000) ---'
SELECT o.num_guia, o.valor AS valor_original, n.valor AS valor_corregido
FROM envios.envio o
JOIN envios_norm.envio n USING (num_guia)
WHERE o.valor <> n.valor;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM envios.envio o JOIN envios_norm.envio n USING (num_guia)
                WHERE o.valor <> n.valor) = 1, 'solo G07 debía cambiar de valor';
END $$;

COMMIT;

-- =====================================================================
-- DESPUÉS: ESQUEMA CORREGIDO Y NORMALIZADO
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# DESPUÉS: esquema corregido envios_norm'
\echo '#####################################################################'

\echo '--- Estructura nueva (tablas con sus PK, FK y CHECK) ---'
\d envios_norm.zona
\d envios_norm.ciudad
\d envios_norm.envio

\echo '--- Datos nuevos ---'
SELECT * FROM envios_norm.zona ORDER BY zona;
SELECT * FROM envios_norm.ciudad ORDER BY ciudad;
SELECT * FROM envios_norm.envio ORDER BY num_guia;

\echo '--- DESPUÉS: la queja resuelta (envíos a Bogotá; G07 = 24 000) ---'
SELECT num_guia, peso_kg, tarifa_kg, valor_cobrado, valor_calculado
FROM envios_norm.envio_calculado
WHERE ciudad_destino = 'Bogotá'
ORDER BY num_guia;

\echo '--- DESPUÉS: auditoría; envíos cuyo valor no coincide con la tarifa vigente (0 filas) ---'
SELECT num_guia, valor_cobrado, valor_calculado
FROM envios_norm.envio_calculado
WHERE valor_cobrado <> valor_calculado;

\echo '--- DESPUÉS: cambiar la tarifa de una zona es UN solo UPDATE de UNA fila (se deshace) ---'
BEGIN;
UPDATE envios_norm.zona SET tarifa_kg = 7000 WHERE zona = 2;

\echo '--- Pregunta propia: los envíos de octubre conservan su valor cobrado ---'
SELECT num_guia, fecha, valor_cobrado AS cobrado_en_octubre, valor_calculado AS con_tarifa_nueva
FROM envios_norm.envio_calculado
WHERE zona = 2
ORDER BY num_guia;
ROLLBACK;

-- =====================================================================
-- RESUMEN ANTES vs DESPUÉS
-- =====================================================================
\echo
\echo '#####################################################################'
\echo '# RESUMEN: ANTES (original) vs DESPUÉS (normalizado)'
\echo '#####################################################################'
SELECT 'Valor del envío G07 (Bogotá)' AS indicador,
        (SELECT valor FROM envios.envio WHERE num_guia = 'G07')::bigint       AS antes_original,
        (SELECT valor FROM envios_norm.envio WHERE num_guia = 'G07')::bigint  AS despues_normalizado
UNION ALL
SELECT 'Envíos con valor distinto de peso × tarifa',
       (SELECT count(*) FROM envios.envio WHERE valor <> peso_kg * tarifa_kg),
        (SELECT count(*) FROM envios_norm.envio_calculado WHERE valor_cobrado <> valor_calculado)
UNION ALL
SELECT 'Veces que se guarda la tarifa de la zona 2',
        (SELECT count(*) FROM envios.envio WHERE zona = 2),
        (SELECT count(*) FROM envios_norm.zona WHERE zona = 2)
UNION ALL
SELECT 'Veces que se guarda el departamento de Bogotá',
        (SELECT count(*) FROM envios.envio WHERE ciudad_destino = 'Bogotá'),
        (SELECT count(*) FROM envios_norm.ciudad WHERE ciudad = 'Bogotá');

-- =====================================================================
-- (f) RETIRAR LO VIEJO: solo después de verificar (conteos, ASSERT y EXCEPT
-- en 0 filas, queja resuelta). La evidencia del ANTES ya quedó en la salida.
-- =====================================================================
\echo '--- CASO 4: se elimina la tabla original envios.envio (ya verificada) ---'
BEGIN;
DROP TABLE envios.envio;
COMMIT;

\echo '--- Comprobación: la tabla original ya no existe (debe dar t) ---'
SELECT to_regclass('envios.envio') IS NULL AS tabla_original_eliminada;

-- =====================================================================
-- PREGUNTA PROPIA (caso 4)
-- La transportadora sube las tarifas en enero. Con el esquema corregido,
-- ¿qué pasa con el valor de los envíos de octubre cuando se cambie la
-- tarifa de la zona?
--   Si `valor` solo se calculara (vista con la tarifa ACTUAL de zona), el
--   valor de octubre cambiaría solo en enero: se reescribiría el pasado y
--   la contabilidad dejaría de cuadrar. Por eso `envio` guarda `valor`
--   (lo cobrado en su fecha) y la tarifa vive una sola vez en `zona`.
--   Como se vio arriba, al subir la tarifa de la zona 2 a 7 000, los
--   envíos de octubre siguen con su valor cobrado (6 000, 18 000...) y la
--   vista muestra aparte lo que daría la tarifa nueva.
--
-- ¿Qué cambiarían en el diseño para que eso no pase?
--   Guardar el valor cobrado en el envío (lo hecho aquí). Alternativa más
--   completa: una tabla tarifa_zona (zona, vigente_desde, tarifa_kg) y
--   calcular con la tarifa vigente en la fecha del envío; solo vale la
--   pena si hay que recalcular valores del pasado.
--
-- ¿Eso es redundancia?
--   NO. Un dato redundante se puede deducir SIEMPRE de otros y debe
--   cambiar cuando ellos cambian. El valor cobrado es un dato HISTÓRICO:
--   registra lo que pasó ese día y NO debe cambiar cuando cambia la
--   tarifa. Parece derivado, pero depende de la tarifa que regía en la
--   fecha del envío, y esa información ya no está en `zona`. Lo que sí
--   era redundancia era repetir la tarifa vigente en cada fila de envío.
-- =====================================================================
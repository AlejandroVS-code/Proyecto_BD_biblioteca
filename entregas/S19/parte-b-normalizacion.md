# S19, Parte B: el esquema del proyecto (biblioteca)

**Grupo 2 · Bases de Datos (750006C)**

Alcance: solo análisis. No se modifica el esquema ni los datos. Los cambios propuestos quedan en papel para S20 (aplicados en `entregas/S20/hito3-normalizacion.md`).

## 0. Qué esquema se analizó

Se analizó `postgres/init/01_esquema.sql` **tal como estaba en el Hito 2 (tag `hito2`)**, que es el que corría en ese momento, antes de las correcciones del Hito 3. La versión actual del archivo ya incluye esos cambios. Difiere del export de dbdiagram del Hito 1 (carpeta `docs/`) en esto:

| Punto | Hito 1 (export) | Esquema del Hito 2 (`01_esquema.sql`) |
|---|---|---|
| `notificacion_demora` | existe | **no existe** (README: "Notificación sin tabla") |
| `devolucion` | `id_devolucion` PK + `id_prestamo UNIQUE` | `id_prestamo` es PK y FK a la vez |
| `cuenta.correo`, `cuenta.telefono` | opcionales | `NOT NULL` + `CHECK` de formato |
| `ejemplar.estado` | texto libre | `CHECK IN ('disponible','prestado','dañado','perdido')` |
| `libro` | sin checks | `CHECK` de ISBN (13 dígitos), título y autor no vacíos, año 1450-2100 |

Son 7 tablas: `rol`, `cuenta`, `categoria`, `libro`, `ejemplar`, `prestamo`, `devolucion`.

## 1. Fuentes de las dependencias

Ninguna dependencia está deducida solo del nombre de una columna. Cada una cita su fuente. Si no hay fuente, queda marcada **SIN RESPALDO**.

| Clave | Fuente |
|---|---|
| F1 | `README.md`, "Mapeo CSV → esquema" |
| F2 | `README.md`, "Reglas del grupo" (S16) |
| F3 | `README.md`, "Decisiones de diseño" |
| F4 | `postgres/init/01_esquema.sql` del Hito 2 (UNIQUE, PK, CHECK) |
| F5 | `postgres/init/02_roles.sql` |
| F6 | `postgres/scripts/datos-prueba.sql` del Hito 2 (encabezado) |
| F7 | `README.md`, "Criterios por tipo de error" |
| F8 | Decisión confirmada por el grupo (no está escrita en el README ni en el esquema) |

## 2. Dependencias funcionales con su regla

| # | Dependencia | Regla de negocio | Fuente |
|---|---|---|---|
| D1 | `id_rol → nombre, descripcion` y `nombre → id_rol` | Los 4 perfiles son fijos: lector, bibliotecario, administrador, auditor | F4, F5 |
| D2 | `id_usuario → todos los atributos de cuenta` | Identidad de la cuenta | F4 |
| D3 | `usuario → id_usuario` y `documento → id_usuario` | Ambos son `UNIQUE`; en la carga `usuario = documento` | F1, F4 |
| D4 | `correo → id_usuario` | "Cada lector debe tener su correo": se rechaza `correo ya registrado`. **Era regla del script, no restricción del esquema** | F7, README |
| D5 | `id_categoria → nombre, descripcion` y `nombre → id_categoria` | Las categorías se crean por nombre con `ON CONFLICT (nombre)` | F1, F4 |
| D6 | `id_libro → todos los atributos de libro` y `isbn → id_libro` | El ISBN es "la clave de negocio del libro" | F7, F4 |
| D7 | `id_ejemplar → id_libro, codigo, estado` y `codigo → id_ejemplar` | Una fila por copia física; `codigo = isbn-n` | F1, F4 |
| D8 | `id_prestamo → id_usuario_lector, id_usuario_registra, id_ejemplar, fecha_prestamo, fecha_limite, estado` | Un préstamo es de un ejemplar, para un lector, registrado por un bibliotecario | F4, F6 |
| D9 | El plazo inicial es de 14 días, pero el préstamo se puede renovar | "Plazo de préstamo: 14 días" (README) y renovación. **`fecha_prestamo → fecha_limite` no se cumple en general**: una renovación mueve `fecha_limite`. Los datos de prueba no traen renovaciones (E6 da 14 días en todos los préstamos porque `datos-prueba.sql` genera `fecha_limite = fecha_prestamo + 14`) | F2 (plazo de 14 días); F8 (renovación) |
| D10 | `id_prestamo → id_usuario_registra, fecha_devolucion, estado_ejemplar` (en `devolucion`) | Como máximo una devolución por préstamo; `id_prestamo` es PK y FK | F3, F4 |
| D11 | Préstamo abierto ⇔ no tiene fila en `devolucion` | Regla; no se usa `prestamo.estado` | F2 |
| D12 | `isbn → autor` (un solo autor por libro) | Regla confirmada por el grupo; los datos la cumplen (E2) | F8 |

Dependencias que **no** tienen respaldo y no se asumen:

- (`id_ejemplar`, `fecha_prestamo`) como clave candidata de `prestamo`: nadie la escribió.
- "Un ejemplar no puede tener dos préstamos abiertos": no está escrito como regla.

## 3. Tabla de la Parte B

| Tabla | Claves candidatas | Dependencias (regla) | Forma normal más alta | Problema encontrado | Evidencia (consulta) | Cambio propuesto |
|---|---|---|---|---|---|---|
| `rol` | `id_rol`, `nombre` | D1 | BCNF | Ninguno | n/a | Ninguno |
| `cuenta` | `id_usuario`, `usuario`, `documento` (+ `correo`, **no declarada**) | D2, D3, D4 | BCNF | `correo` identifica a una persona por regla del script, pero el esquema no tiene `UNIQUE (correo)`: es una clave candidata sin proteger (mismo patrón del caso 3) | E1: 0 filas hoy, porque el script de carga rechaza correos repetidos. La base no lo impide: un `INSERT` directo sí podría duplicar un correo | Declarar `UNIQUE (correo)` (propuesta para S20; no cambia la forma normal) |
| `categoria` | `id_categoria`, `nombre` | D5 | BCNF | Ninguno | n/a | Ninguno |
| `libro` | `id_libro`, `isbn` | D6, D12 | BCNF | Ninguno. `autor` guarda un solo valor por regla confirmada (E2 lo comprueba). `editorial` no se llena en la carga (queda `NULL`) | E2, E3 | Ninguno |
| `ejemplar` | `id_ejemplar`, `codigo` | D7 | BCNF | `estado` mezcla dos cosas: `'disponible'` y `'prestado'` se pueden calcular (D11); `'dañado'` y `'perdido'` no | E4: sin contradicciones hoy (86 `disponible`/FALSE y 8 `prestado`/TRUE), pero solo porque `datos-prueba.sql` hace el `UPDATE` a mano. Nada en la base mantiene sincronizado el estado | Dejar solo la condición física en `ejemplar.estado` y ofrecer la disponibilidad con una vista; o conservarla y justificar la desnormalización (S20) |
| `prestamo` | `id_prestamo` | D8, D9, D11 | BCNF | `estado` (`'en_uso'`/`'devuelto'`) es derivado de la existencia de `devolucion`. `fecha_limite` parece derivada (+14 días), pero no lo es: las renovaciones la cambian | E5: coincide (`devuelto` con devolución 21, `en_uso` sin devolución 8). E6: 14 días en los 29 préstamos; `datos-prueba.sql` genera `fecha_limite = fecha_prestamo + 14`, así que no hay renovaciones en los datos y E6 da 14 por construcción. Que `fecha_limite` no se pueda calcular se apoya en la regla confirmada por el grupo (D9), no en estos datos | Quitar `estado` y calcularlo en una vista. **Conservar** `fecha_limite` |
| `devolucion` | `id_prestamo` | D10 | BCNF | Ninguno. `estado_ejemplar` es histórico, no redundante | E7 | Ninguno |

## 4. Justificación por tabla

### `rol`, `categoria`
Cada determinante es clave candidata. Ningún atributo describe a otra entidad. BCNF.

### `cuenta`
- No hay datos de otra entidad copiados: el rol y el creador se referencian por FK (`id_rol`, `id_usuario_creador`).
- `usuario` y `documento` son claves candidatas declaradas. `usuario = documento` es una convención de la carga, no una dependencia del esquema.
- `telefono` tiene `CHECK '^[0-9]{7,10}$'`: un solo valor, sin listas. Está en 1FN.
- **Problema real:** la regla `correo → id_usuario` existe en el script de carga (`correo ya registrado`), pero la base no la hace cumplir. Cualquier `INSERT` fuera del script puede duplicar correos. El README del Hito 2 lo decía: "no es una restricción `UNIQUE` del esquema".
- **Qué muestra E1:** hoy no hay correos repetidos (0 filas) porque la carga los rechaza. La evidencia confirma que los datos actuales están bien, no que el esquema los proteja; el riesgo es de cualquier inserción que no pase por el script.

### `libro`
- `isbn` es clave candidata; todos los atributos dependen de la clave y de nada más. Cumple BCNF.
- `titulo`, `autor` y `anio_publicacion` describen la edición identificada por ISBN.
- **Autor:** Cada libro tiene un solo autor, y los 32 libros de la semilla lo cumplen. `autor` es atómico, así que la tabla está en 1FN y no hace falta `libro_autor`. El texto del autor se repite entre libros (por ejemplo García Márquez en 3), pero no hay ningún atributo que dependa del autor, así que no viola 3FN.
- **Editorial:** no hay texto repetido que normalizar mientras la columna siga en `NULL`. Si se empieza a llenar, aplicaría la misma revisión que a `autor`.

### `ejemplar`
- `codigo` embebe el ISBN (`isbn-n`), así que repite información de `libro.isbn`. No viola ninguna forma normal (`codigo` es clave), pero conviene mencionarlo: si el ISBN de un libro cambiara, el código no se actualizaría.
- `estado`: el `CHECK` admite cuatro valores. Dos son derivables de los préstamos abiertos; dos son hechos propios del ejemplar. El `datos-prueba.sql` los mantiene sincronizados a mano con `UPDATE ejemplar SET estado = 'prestado'`, lo que muestra el riesgo de desincronización.
- **Qué muestra E4:** hoy no hay contradicciones (86 `disponible` sin préstamo abierto y 8 `prestado` con préstamo abierto), pero solo porque el script de prueba hace el `UPDATE` a mano. Nada en la base mantiene sincronizado el estado.

### `prestamo`
- Solo guarda FKs y fechas: no hay datos del lector ni del libro copiados. BCNF.
- `estado`: el README del Hito 2 ya lo reconocía ("sin el trigger del Hito 4 no se actualiza sola"). Es un dato derivado de D11. E5 muestra que hoy coincide con la existencia de `devolucion` (21 y 8).
- `fecha_limite`: el plazo inicial es fijo (14 días), pero el préstamo se puede renovar. Entonces `fecha_limite` **no se puede calcular** a partir de `fecha_prestamo`: depende de cuántas renovaciones hubo. Es un dato propio del préstamo, no redundante. Se conserva.
- **Qué muestra E6:** 14 días en los 29 préstamos. Como `datos-prueba.sql` genera `fecha_limite = fecha_prestamo + 14`, el resultado es 14 por construcción y no hay renovaciones en los datos.
- Observación: el esquema vigente no tiene dónde guardar las renovaciones, así que al renovar se sobrescribe `fecha_limite` y se pierde la fecha original. No es un problema de forma normal ni se corrige ahora (no se toca el esquema), pero queda anotado como límite del diseño.

### `devolucion`
- `id_prestamo` es PK y FK: relación 1 a 1 y opcional con `prestamo`. Separarla evita columnas `NULL` en `prestamo`.
- `estado_ejemplar` es el estado del ejemplar al devolverlo. No es `ejemplar.estado` (el actual). Es historia, no redundancia.

## 5. Consultas de evidencia

Esquema `biblioteca`. Ejecutadas con la semilla y `datos-prueba.sql` sobre el esquema del Hito 2. Los resultados de E1, E4 y E5 están guardados en `docs/salidas/07-migracion-hito3.txt` (sección a, corrida justo antes de migrar); los de E2, E3, E6 y E7 se resumen en la tabla de abajo. Los 7 resultados coinciden con lo esperado.

```sql
SET search_path TO biblioteca, public;

-- E1. ¿Hay correos repetidos? (clave candidata sin UNIQUE)
SELECT lower(correo) AS correo, count(*)
FROM cuenta GROUP BY lower(correo) HAVING count(*) > 1;

-- E2. ¿Hay listas en la celda autor? (debe dar 0 filas: un autor por libro)
SELECT isbn, autor FROM libro
WHERE autor ~ '[,;/]' OR autor ~* '\s(y|and|&)\s';

-- E3. ¿Cuánto se llena editorial?
SELECT count(*) AS libros, count(editorial) AS con_editorial FROM libro;

-- E4. ¿El estado del ejemplar coincide con sus préstamos abiertos?
SELECT e.estado,
       EXISTS (SELECT 1 FROM prestamo p
               WHERE p.id_ejemplar = e.id_ejemplar
                 AND NOT EXISTS (SELECT 1 FROM devolucion d
                                 WHERE d.id_prestamo = p.id_prestamo)) AS con_prestamo_abierto,
       count(*)
FROM ejemplar e GROUP BY 1, 2 ORDER BY 1, 2;
-- Contradicción: 'disponible' con TRUE, o 'prestado' con FALSE.

-- E5. ¿El estado del préstamo coincide con la existencia de devolución?
SELECT p.estado, (d.id_prestamo IS NOT NULL) AS tiene_devolucion, count(*)
FROM prestamo p LEFT JOIN devolucion d USING (id_prestamo)
GROUP BY 1, 2 ORDER BY 1, 2;

-- E6. ¿El plazo es siempre 14 días?
SELECT fecha_limite - fecha_prestamo AS dias, count(*)
FROM prestamo GROUP BY 1 ORDER BY 2 DESC;

-- E7. ¿Hay ejemplares con dos préstamos abiertos? (regla sin respaldo; evidencia)
SELECT p.id_ejemplar, count(*)
FROM prestamo p
WHERE NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id_prestamo)
GROUP BY p.id_ejemplar HAVING count(*) > 1;
```

Resultados esperados (escritos antes de correr) y obtenidos:

| Consulta | Esperado | Obtenido |
|---|---|---|
| E1 | 0 filas (la carga rechaza correos repetidos) | 0 filas |
| E2 | 0 filas (la semilla trae un autor por libro) | 0 filas |
| E3 | 32 libros, 0 con editorial | 32 libros, 0 con editorial |
| E4 | `disponible`/FALSE y `prestado`/TRUE, sin contradicciones | `disponible`/FALSE: 86; `prestado`/TRUE: 8 |
| E5 | `devuelto`/TRUE: 21 y `en_uso`/FALSE: 8 | `devuelto`/TRUE: 21; `en_uso`/FALSE: 8 |
| E6 | 14 días en los 29 préstamos si los datos de prueba no incluyen renovaciones | 14 días en los 29 préstamos |
| E7 | 0 filas | 0 filas |

Cómo leer estos resultados:

- **E1 y E4** muestran que hoy los datos están bien, no que la base los proteja. El riesgo es el de cualquier inserción o actualización que no pase por el script de carga o por `datos-prueba.sql`.
- **E6** da 14 por construcción: `datos-prueba.sql` genera `fecha_limite = fecha_prestamo + 14`. No hay renovaciones en los datos, así que la conclusión sobre `fecha_limite` (D9) se apoya en la regla, no en este resultado.

## 6. Qué decidir antes de S20

1. **¿Se declara `UNIQUE (correo)`?** La regla ya existe en el script de carga.
2. **`estado` de `prestamo` y de `ejemplar`:** ¿se quitan y se calculan en una vista, o se conservan por el trigger del Hito 4 y se justifica como desnormalización a propósito?

Ambas decisiones se tomaron en S20: se declaró el índice único sobre `lower(correo)` y se quitaron los dos estados derivados (ver `entregas/S20/hito3-normalizacion.md`).

## 7. Conclusión

Con las reglas respaldadas, el esquema del Hito 2 está en BCNF en las 7 tablas. Los hallazgos no son violaciones de forma normal, sino:

- una clave candidata sin proteger (`cuenta.correo`);
- dos datos derivados guardados (`prestamo.estado`, `ejemplar.estado` parcial);
- y dos datos que se parecen a redundantes pero no lo son (`prestamo.fecha_limite`, que las renovaciones cambian, y `devolucion.estado_ejemplar`, que es histórico).

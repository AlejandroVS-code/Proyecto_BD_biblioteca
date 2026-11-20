# Hito 3: documento de normalización

**Grupo 2 · Bases de Datos (750006C)** · Esquema `biblioteca` · Parte de S19 (`parte-b-normalizacion.md`) y S20, parte B

**Resumen.** El esquema de 7 tablas ya estaba en BCNF. Se encontraron tres hallazgos, ninguno es una violación de forma normal: una clave candidata sin proteger (`cuenta.correo`) y dos datos derivados guardados (`prestamo.estado` y la parte `prestado`/`disponible` de `ejemplar.estado`). Se corrigieron los tres y **no se desnormalizó nada**: medido con `EXPLAIN ANALYZE`, el catálogo tarda menos de 1 ms.

## 1. Esquema antes

| Tabla | Columnas (PK con `*`, FK con `→`) |
|---|---|
| `rol` | `id_rol*`, `nombre` (único), `descripcion` |
| `cuenta` | `id_usuario*`, `id_rol→rol`, `id_usuario_creador→cuenta`, `usuario` (único), `documento` (único), `contrasena`, `nombres`, `apellidos`, `correo`, `telefono`, `fecha_creacion`, `activa` |
| `categoria` | `id_categoria*`, `nombre` (único), `descripcion` |
| `libro` | `id_libro*`, `id_categoria→categoria`, `isbn` (único), `titulo`, `autor`, `editorial`, `anio_publicacion`, `activo` |
| `ejemplar` | `id_ejemplar*`, `id_libro→libro`, `codigo` (único), `estado` ∈ {disponible, prestado, dañado, perdido} |
| `prestamo` | `id_prestamo*`, `id_usuario_lector→cuenta`, `id_usuario_registra→cuenta`, `id_ejemplar→ejemplar`, `fecha_prestamo`, `fecha_limite`, `estado` |
| `devolucion` | `id_prestamo*→prestamo`, `id_usuario_registra→cuenta`, `fecha_devolucion`, `estado_ejemplar` |

Datos al migrar (semilla + `datos-prueba.sql`): 32 libros, 94 ejemplares, 29 préstamos, 21 devoluciones.

## 2. Dependencias funcionales y claves candidatas

Cada dependencia cita su regla (D1 a D12 de `parte-b-normalizacion.md`, S19).

| Tabla | Claves candidatas | Dependencias y regla que las justifica |
|---|---|---|
| `rol` | `id_rol`, `nombre` | `id_rol → nombre, descripcion` y `nombre → id_rol`: los 4 perfiles son fijos (D1). |
| `cuenta` | `id_usuario`, `usuario`, `documento`, **`correo`** | `id_usuario →` todo (D2). `usuario → id_usuario` y `documento → id_usuario`: `UNIQUE` del esquema (D3). `correo → id_usuario`: la carga rechaza `correo ya registrado` (D4); era solo regla del script y ahora la respalda un índice único. |
| `categoria` | `id_categoria`, `nombre` | `id_categoria → nombre, descripcion` y `nombre → id_categoria`: se crean por nombre (D5). |
| `libro` | `id_libro`, `isbn` | `isbn → titulo, autor, anio_publicacion, …`: el ISBN es la clave de negocio (D6). `autor` es un solo valor por libro, regla del grupo (D12). |
| `ejemplar` | `id_ejemplar`, `codigo` | `id_ejemplar → id_libro, codigo, estado`: una fila por copia física (D7). |
| `prestamo` | `id_prestamo` | `id_prestamo →` lector, registrador, ejemplar, fechas (D8). **No se cumple** `fecha_prestamo → fecha_limite`: por regla del grupo se permiten renovaciones, que mueven `fecha_limite` (D9). El estado depende de si existe fila en `devolucion` (D11). |
| `devolucion` | `id_prestamo` | `id_prestamo → id_usuario_registra, fecha_devolucion, estado_ejemplar`: como máximo una devolución por préstamo (D10). |

## 3. Forma normal de cada tabla y problemas encontrados

Las siete tablas están en **BCNF**: todo determinante es clave candidata. Los hallazgos no violan una forma normal: son redundancia **entre tablas** (el dato se calcula desde otra tabla) o una clave sin declarar.

| Tabla | Problema | Evidencia (`normalizacion.sql`, sección a) | Resultado |
|---|---|---|---|
| `cuenta` | `correo` identifica a una cuenta, pero nada en la base lo impide | E1: correos repetidos con `lower(correo)` | 0 filas: bien solo porque la carga lo revisa |
| `ejemplar` | `estado` mezcla condición física con algo calculable (`prestado`/`disponible`) | E4: `estado` frente a los préstamos abiertos | `disponible` sin préstamo: 86; `prestado` con préstamo: 8. Coincide solo porque `datos-prueba.sql` hacía el `UPDATE` a mano |
| `prestamo` | `estado` se deduce de si existe `devolucion` | E5: `estado` frente a la devolución | `devuelto` con devolución: 21; `en_uso` sin devolución: 8. Coincide, pero nada lo mantiene |

Tres datos que **parecen** redundantes y no lo son:

- `prestamo.fecha_limite`: las renovaciones la cambian, no es siempre `fecha_prestamo + 14`.
- `devolucion.estado_ejemplar`: cómo estaba la copia al devolverla (historia).
- `ejemplar.codigo`: lleva el ISBN incrustado (`isbn-n`), pero es la etiqueta de la copia física, armada una vez al cargar. No es una dependencia entre columnas, así que no viola BCNF; se acepta el riesgo de que un ISBN corregido deje el código viejo.

## 4. Cambios aplicados y migración

| # | Cambio | Cómo |
|---|---|---|
| 1 | `cuenta.correo` único | `CREATE UNIQUE INDEX … ON cuenta (lower(correo))`, igual que la carga |
| 2 | Quitar `prestamo.estado` | Vista `prestamo_con_estado`: `en_uso` sin fila en `devolucion`, `devuelto` con ella |
| 3 | `ejemplar.estado` = condición física | Valores `bueno`, `dañado`, `perdido`. Vistas `ejemplar_con_disponibilidad` y `libro_disponibilidad` (catálogo) |
| 4 | Mismo vocabulario en `devolucion.estado_ejemplar` | `disponible` pasa a `bueno` y se agrega el `CHECK` |
| 5 | Índices en las FK | `ejemplar(id_libro)`, `prestamo(id_ejemplar)`, `prestamo(id_usuario_lector)` |

**Migración** (`postgres/scripts/normalizacion.sql`): una sola transacción con la receta de S19: evidencia, `BEGIN`, copia en tablas temporales, cambios, **verificación** (lo que calculan las vistas contra lo guardado, con `EXCEPT` en los dos sentidos) y solo entonces se borra `prestamo.estado` y se hace `COMMIT`. Si algo difiere, el script se detiene sin guardar nada. Salida en `docs/salidas/07-migracion-hito3.txt`.

| Dato | Antes | Después |
|---|---|---|
| Libros / ejemplares / préstamos / devoluciones | 32 / 94 / 29 / 21 | 32 / 94 / 29 / 21 |
| Estado del préstamo | 21 `devuelto`, 8 `en_uso` (guardados) | 21 y 8 (calculados) |
| Ejemplares | 86 `disponible`, 8 `prestado` (guardados) | 94 con `estado = 'bueno'`: 86 disponibles y 8 prestados (calculados) |

**Reportes de S16.** `reportes.sql` no cambió: ya definía "abierto" con `NOT EXISTS` sobre `devolucion`. Solo se ajustaron las escrituras (`datos-prueba.sql` y las cargas de libros, que insertan `'bueno'`). Dan 22, 2, 3 y 4 filas tanto en una base creada desde el init nuevo (`06-reportes-parte-b.txt`) como en la base migrada (`08-reportes-hito3.txt`).

## 5. Desnormalizaciones deliberadas: ninguna

| Dato | ¿Se calcula o se guarda? | Justificación |
|---|---|---|
| Disponibilidad del ejemplar y del libro | **Se calcula** (vistas) | `devolucion` es la única fuente de verdad: no hay copia que se desincronice. Medición abajo |
| `prestamo.estado` | **Se calcula** | Sale de `devolucion`; ningún reporte lo usaba |
| `prestamo.fecha_limite` | Se guarda | Dato propio del préstamo (renovaciones) |
| `devolucion.estado_ejemplar` | Se guarda | Histórico, no redundante |

**Medición.** `EXPLAIN ANALYZE SELECT * FROM libro_disponibilidad` sobre los datos migrados (32 libros, 94 ejemplares, 29 préstamos): 0,729, 0,462 y 0,285 ms en tres corridas, típico por debajo de 0,5 ms. A esta escala no hay nada que optimizar. En el ejemplo del taller el problema aparece con más de 300 000 préstamos (unos 20 ms sin índices); además los índices en las FK ya están.

**Si algún día se midiera lento**, se guardaría `libro.disponibles` mantenido por un trigger (Hito 4), con una vista `descuadre` como consulta de verificación. **Pendiente para el Hito 4:** la regla "un ejemplar no puede tener dos préstamos abiertos" no tiene respaldo en la base; la consulta E7 de S19 queda como verificación hasta que exista el trigger.

## 6. Esquema después

Todas las tablas quedan en **BCNF** (ninguna en 3FN y no en BCNF). Cambios: `cuenta` con `UNIQUE (lower(correo))`; `ejemplar.estado` ∈ {bueno, dañado, perdido} con índice en `id_libro`; `prestamo` sin `estado` y con índices en `id_ejemplar` e `id_usuario_lector`; `devolucion.estado_ejemplar` con `CHECK`. `rol`, `categoria` y `libro` no cambian. Vistas nuevas: `prestamo_con_estado`, `ejemplar_con_disponibilidad`, `libro_disponibilidad`. El esquema está en `postgres/init/01_esquema.sql` y corre limpio sobre una base vacía (comandos de prueba en el README).

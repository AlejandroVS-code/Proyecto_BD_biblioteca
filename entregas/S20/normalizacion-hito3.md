# Hito 3: Análisis de Normalización y Desnormalización

**Asignatura:** Bases de Datos (750006C) · Universidad del Valle  
**Sesión:** S20 · **Grupo 2:** Alejandro Valencia, Nicolas Velasco, Daniel Toro, María Alejandra Pizarro

---

## 1. Esquema antes (Hito 2)

El esquema `biblioteca` (`postgres/init/01_esquema.sql`) tiene 7 tablas:

- **`rol`** (`id_rol` PK, `nombre` UNIQUE, `descripcion`)
- **`cuenta`** (`id_usuario` PK, `id_rol` FK, `id_usuario_creador` FK, `usuario` UNIQUE, `documento` UNIQUE, `contrasena`, `nombres`, `apellidos`, `correo`, `telefono`, `fecha_creacion`, `activa`)
- **`categoria`** (`id_categoria` PK, `nombre` UNIQUE, `descripcion`)
- **`libro`** (`id_libro` PK, `id_categoria` FK, `isbn` UNIQUE, `titulo`, `autor`, `editorial`, `anio_publicacion`, `activo`)
- **`ejemplar`** (`id_ejemplar` PK, `id_libro` FK, `codigo` UNIQUE, `estado`)
- **`prestamo`** (`id_prestamo` PK, `id_usuario_lector` FK, `id_usuario_registra` FK, `id_ejemplar` FK, `fecha_prestamo`, `fecha_limite`, `estado`)
- **`devolucion`** (`id_prestamo` PK/FK, `id_usuario_registra` FK, `fecha_devolucion`, `estado_ejemplar`)

---

## 2. Dependencias funcionales por tabla y claves candidatas

| Tabla | Claves candidatas | Dependencias funcionales y regla de negocio que las justifica |
|---|---|---|
| **`rol`** | `{id_rol}`, `{nombre}` | `id_rol -> nombre, descripcion` y `nombre -> id_rol, descripcion`. Cada perfil tiene un ID y un nombre único que determinan su descripción. |
| **`cuenta`** | `{id_usuario}`, `{usuario}`, `{documento}` | `id_usuario -> id_rol, id_usuario_creador, usuario, documento, contrasena, nombres, apellidos, correo, telefono, fecha_creacion, activa` (igual desde `usuario` y `documento`). Cada persona tiene documento y usuario únicos que determinan sus datos y rol. |
| **`categoria`** | `{id_categoria}`, `{nombre}` | `id_categoria -> nombre, descripcion` y `nombre -> id_categoria, descripcion`. Cada categoría es única y determina su descripción. |
| **`libro`** | `{id_libro}`, `{isbn}` | `id_libro -> id_categoria, isbn, titulo, autor, editorial, anio_publicacion, activo` (igual desde `isbn`). El ISBN único de 13 dígitos identifica cada obra y determina sus datos bibliográficos y categoría. |
| **`ejemplar`** | `{id_ejemplar}`, `{codigo}` | `id_ejemplar -> id_libro, codigo, estado` y `codigo -> id_ejemplar, id_libro, estado`. Cada copia física tiene un código único (`isbn-copia`) que determina a qué libro pertenece y su estado actual. |
| **`prestamo`** | `{id_prestamo}` | `id_prestamo -> id_usuario_lector, id_usuario_registra, id_ejemplar, fecha_prestamo, fecha_limite, estado`. Cada préstamo único determina lector, bibliotecario, ejemplar, fechas y estado. |
| **`devolucion`** | `{id_prestamo}` | `id_prestamo -> id_usuario_registra, fecha_devolucion, estado_ejemplar`. Cada préstamo se devuelve máximo una vez; su ID determina quién recibió, fecha y estado del ejemplar. |

---

## 3. Forma normal de cada tabla y evidencia

- **1FN:** Todos los atributos almacenan valores atómicos (no hay grupos repetitivos ni columnas multivaluadas; las copias físicas se separan en `ejemplar`).
- **2FN:** Todas las tablas tienen clave primaria simple de un solo atributo (`INTEGER`), por lo que no existen dependencias parciales.
- **3FN y FNBC:** No hay dependencias transitivas (la categoría reside en `categoria` y los datos del lector en `cuenta`). En las 7 tablas, todo determinante de una dependencia funcional no trivial es clave candidata, por lo que **todas cumplen 3FN y FNBC**.
- **`prestamo.fecha_limite` (hecho histórico vs. derivado):** Aunque el plazo base es de 14 días, la biblioteca puede modificar el plazo general o dar plazos especiales. Por eso `fecha_limite` guarda el compromiso pactado en cada préstamo: depende de `id_prestamo` y es un **hecho histórico válido en 3FN**.

**Consulta de evidencia (verificación de integridad de estados):**

```sql
SELECT count(*) AS descuadres_prestamo
FROM biblioteca.prestamo p
LEFT JOIN biblioteca.devolucion d ON d.id_prestamo = p.id_prestamo
WHERE (d.id_prestamo IS NOT NULL AND p.estado <> 'devuelto')
   OR (d.id_prestamo IS NULL AND p.estado = 'devuelto');
-- Resultado: 0 filas con descuadre sobre los 29 préstamos de prueba.
```

---

## 4. Cambios aplicados y migración de datos

Como el esquema del Hito 2 (`postgres/init/01_esquema.sql`) ya cumple **3FN y FNBC** sin anomalías, **no fue necesario modificar tablas ni crear `postgres/scripts/normalizacion.sql`**.

1. **Arranque limpio:** Se probó `01_esquema.sql` en una base temporal vacía (`prueba_init`) y ejecutó sin errores.
2. **Conteos verificados:** `rol` (4), `cuenta` (21), `categoria` (9), `libro` (32), `ejemplar` (94), `prestamo` (29) y `devolucion` (21).
3. **Reportes (S16):** Se ejecutaron `datos-prueba.sql` y `reportes.sql` sobre el esquema verificado, obteniendo los resultados esperados (Reporte 1: 22 filas; Reporte 2: 2 filas; Reporte 3: 3 filas; Reporte 4: 4 filas).

---

## 5. Desnormalizaciones deliberadas y decisiones de consistencia

| Elemento evaluado | Decisión | Justificación, mecanismo de consistencia y consulta de verificación |
|---|---|---|
| **`libro.ejemplares_disponibles`** | **No se desnormaliza** (se calcula al consultar) | No se agrega columna de conteo en `libro`. El catálogo maneja un volumen moderado donde contar ejemplares con `estado = 'disponible'` (con índice en `id_libro`) es rápido y evita desincronización. |
| **`prestamo.estado`** | **Se conserva** (redundancia controlada) | Facilita filtrar préstamos activos (`estado = 'en_uso'`), aunque la presencia de fila en `devolucion` es la regla autoritativa de cierre. **Mecanismo:** actualización transaccional y **trigger `AFTER INSERT ON devolucion` pendiente para Hito 4 (M6)**. |
| **`ejemplar.estado`** | **Se conserva** (estado operativo) | Registra `'disponible'`, `'prestado'`, `'dañado'` o `'perdido'`. Los estados físicos no se deducen de `prestamo`, y `'prestado'` refleja préstamos abiertos. **Mecanismo:** actualización transaccional y **trigger pendiente en Hito 4 (M6)**. |

**Consultas de verificación de consistencia:**

```sql
-- 1. Descuadres entre prestamo.estado y devolucion
SELECT p.id_prestamo, p.estado, d.fecha_devolucion
FROM biblioteca.prestamo p
LEFT JOIN biblioteca.devolucion d ON d.id_prestamo = p.id_prestamo
WHERE (d.id_prestamo IS NOT NULL AND p.estado <> 'devuelto')
   OR (d.id_prestamo IS NULL AND p.estado = 'devuelto');

-- 2. Descuadres entre ejemplar.estado y préstamos abiertos
SELECT e.id_ejemplar, e.codigo, e.estado
FROM biblioteca.ejemplar e
WHERE (e.estado = 'prestado' AND NOT EXISTS (
         SELECT 1 FROM biblioteca.prestamo p
         LEFT JOIN biblioteca.devolucion d ON d.id_prestamo = p.id_prestamo
         WHERE p.id_ejemplar = e.id_ejemplar AND d.id_prestamo IS NULL))
   OR (e.estado = 'disponible' AND EXISTS (
         SELECT 1 FROM biblioteca.prestamo p
         LEFT JOIN biblioteca.devolucion d ON d.id_prestamo = p.id_prestamo
         WHERE p.id_ejemplar = e.id_ejemplar AND d.id_prestamo IS NULL));
```

---

## 6. Esquema después

El esquema final en `postgres/init/01_esquema.sql` mantiene las 7 tablas (`rol`, `cuenta`, `categoria`, `libro`, `ejemplar`, `prestamo`, `devolucion`) en **FNBC (y 3FN)**, con sus restricciones `PRIMARY KEY`, `UNIQUE`, `FOREIGN KEY` y `CHECK` activas, y con las consultas de verificación documentadas para los triggers del Hito 4.

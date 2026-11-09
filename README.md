# S14 y S16 / Hito 2: Esquema, carga desde CSV y reportes

**Asignatura:** Bases de Datos (750006C), Universidad del Valle
**Módulo 4, Sesiones 14 y 16** · Grupo 2

## Integrantes del equipo

| Nombre del estudiante | Código |
|---|---|
| Alejandro Valencia | 2515411-2724 |
| Nicolas Velasco | 2521994-2724 |
| Daniel Toro | 2521005-2724 |
| María Alejandra Pizarro | 2519474-2724 |

## Qué contiene este repositorio

El esquema de la biblioteca como script de arranque del entorno Docker y la carga de los CSV semilla (libros y lectores), incluidos los archivos con errores intencionales. La carga sigue el patrón **tabla de paso → validación → tabla final → bitácora de rechazos**, todo dentro de una transacción. Para S16 incluye además los datos de prueba y los cuatro reportes de préstamos (más prestados, lectores que más leen, morosos y préstamos en mora), con su tabla de verificación.

## Estructura

```
.
├── README.md
├── docker-compose.yml
├── postgres/
│   ├── init/
│   │   ├── 01_esquema.sql              # esquema (corre solo con la base vacía)
│   │   └── 02_roles.sql                # los 4 perfiles: lector, bibliotecario, administrador, auditor
│   └── scripts/
│       ├── carga-libros.sql
│       ├── carga-lectores.sql
│       ├── prueba-sin-regla-titulo.sql # copia de carga-libros.sql con una regla comentada
│       ├── datos-prueba.sql            # préstamos de prueba para los 8 casos (parte B)
│       ├── reportes.sql                # los cuatro reportes con sus decisiones (parte B)
│       └── datos/                      # CSV semilla, CSV propio y CSV de la prueba
├── entregas/
│   └── S16/
│       ├── consultas.sql               # las 11 consultas de la parte A (esquema tienda)
│       └── verificacion-parte-b.md     # tabla de verificación de la parte B
└── docs/
    └── salidas/                        # salida de psql de cada carga
        └── 06-reportes-parte-b.txt     # salida de psql de los cuatro reportes (S16)
```

## Guía de ejecución

### 1. Inicialización del entorno (Docker)

El esquema y los roles se ejecutan automáticamente al levantar PostgreSQL con la carpeta de datos vacía.

```bash
# Reiniciar contenedores y limpiar datos antiguos
docker compose down
rm -rf postgres/data/*        # en PowerShell: Remove-Item -Recurse -Force postgres\data\*

# Levantar PostgreSQL
docker compose up -d postgres

# Confirmar las tablas del esquema y los 4 roles
docker compose exec postgres psql -U curso -d curso -c '\dt biblioteca.*'
docker compose exec postgres psql -U curso -d curso -c 'SELECT nombre FROM biblioteca.rol;'
```

### 2. Ejecución de las cargas desde psql

Los scripts se corren a mano dentro del contenedor. Sin `-v archivo=...` cargan el CSV limpio por defecto.

```bash
# 1. Libros limpio
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql

# 2. Libros con errores a propósito
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
  -f /scripts/carga-libros.sql

# 3. Lectores limpio (debe ir antes del de errores: este repite un documento ya cargado)
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql

# 4. Lectores con errores
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
  -f /scripts/carga-lectores.sql

# 5. Nuestro CSV propio
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_propio.csv \
  -f /scripts/carga-libros.sql

# 6. Ver la bitácora de rechazos
docker compose exec postgres psql -U curso -d curso \
  -c 'SELECT archivo, linea, motivo FROM carga.rechazo_carga ORDER BY id_rechazo;'
```

### 3. Datos de prueba y reportes (S16)

Requiere haber corrido antes las cargas limpias de libros y lectores (pasos 1 y 3 de la sección anterior). `datos-prueba.sql` se puede repetir: borra lo que insertó antes y lo vuelve a crear.

```bash
# 1. Datos de prueba (29 préstamos que cubren los 8 casos)
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql

# 2. Los cuatro reportes (-P pager=off evita que psql abra el paginador y corte la salida)
docker compose exec postgres psql -U curso -d curso -P pager=off -f /scripts/reportes.sql

# 3. Guardar la salida como evidencia (en PowerShell; cmd /c conserva las tildes)
cmd /c "docker compose exec -T postgres psql -U curso -d curso -f /scripts/reportes.sql > docs\salidas\06-reportes-parte-b.txt"
```

## Mapeo CSV → esquema propio

Todas las tablas están en el esquema `biblioteca`; la bitácora está en `carga.rechazo_carga`.

### Libros (`isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles`)

| Columna del CSV | Destino | Transformación | Regla de validación (motivo en bitácora) |
|---|---|---|---|
| `isbn` | `libro.isbn` | `trim`; se quitan los guiones | no vacío (`isbn vacío`); 13 dígitos (`isbn no tiene 13 dígitos`); no existe en `libro` (`isbn ya existe en el catálogo`); no repetido en el archivo (`isbn repetido en el archivo`) |
| `titulo` | `libro.titulo` | `trim` | no vacío (`título vacío`) |
| `autor` | `libro.autor` | `trim` | no vacío (`autor vacío`) |
| `categoria` | `categoria.nombre` → `libro.id_categoria` | alta con `ON CONFLICT (nombre) DO NOTHING` y búsqueda de la clave por nombre | no vacía (`categoría vacía`) |
| `anio_publicacion` | `libro.anio_publicacion` | `::integer` | solo dígitos (`año no numérico`); entre 1450 y 2100 (`año fuera de rango`) |
| `ejemplares_disponibles` | `ejemplar` (una fila por copia) | `generate_series(1, n)`; `codigo = isbn-n`; `estado = 'disponible'` | entero de hasta 4 dígitos (`ejemplares no numérico`); mayor o igual a 0 (`ejemplares negativo`) |
| *(estructura)* | todo el archivo | n/a | exactamente 6 columnas (`tiene N columnas, se esperaban 6`) |

### Lectores (`documento, nombres, apellidos, correo, telefono`): todos van a `cuenta`

| Columna del CSV | Destino | Transformación | Regla de validación (motivo en bitácora) |
|---|---|---|---|
| `documento` | `cuenta.documento` y `cuenta.usuario` | `trim` | no vacío (`documento vacío`); 6 a 15 dígitos (`documento no numérico o de longitud inválida`); no existe en `cuenta` (`documento ya existe`); no repetido en el archivo |
| `nombres` | `cuenta.nombres` | `trim` | no vacío (`nombres vacíos`) |
| `apellidos` | `cuenta.apellidos` | `trim` | no vacío (`apellidos vacíos`) |
| `correo` | `cuenta.correo` | `lower(trim(...))` | no vacío (`correo vacío`); formato válido (`correo inválido`); no registrado (`correo ya registrado`); no repetido en el archivo |
| `telefono` | `cuenta.telefono` | `trim` | 7 a 10 dígitos (`teléfono inválido`); coincide con el `CHECK` del esquema |
| *(no viene en el CSV)* | `cuenta.id_rol` | id del rol `lector` (creado en `02_roles.sql`) | si el rol no existe, la carga se detiene con un mensaje claro |
| *(no viene en el CSV)* | `cuenta.contrasena` | `crypt(documento, gen_salt('bf'))` (bcrypt con sal) | nunca en texto plano |
| *(estructura)* | todo el archivo | n/a | exactamente 5 columnas |

## Criterios por tipo de error

Principio: **normalizar sí, adivinar no.** Se corrige lo que se puede arreglar de forma mecánica; lo demás se rechaza y queda en la bitácora con archivo, línea, contenido y motivo.

### Los 14 errores de los archivos del curso

| # | Archivo, línea | Error | Decisión | Justificación |
|---|---|---|---|---|
| 1 | libros, 2 | ISBN `…001` ya existe en el catálogo | Rechazar | El título dice "edición duplicada": no se sabe si es otra edición o un error. |
| 2 | libros, 3 | título vacío | Rechazar | Dato obligatorio que no se puede inventar. |
| 3 | libros, 4 | año = `dos` | Rechazar | No hay conversión mecánica de una palabra a un año. |
| 4 | libros, 5 | año = `MCMXLIX` | Rechazar | Convertir números romanos no es una corrección segura. |
| 5 | libros, 6 | 7 columnas en vez de 6 | Rechazar | No se sabe cuál columna sobra. |
| 6 | libros, 7 | autor vacío | Rechazar | Obligatorio. |
| 7 | libros, 8 | ISBN vacío | Rechazar | Es la clave de negocio del libro. |
| 8 | libros, 9 | ejemplares = `-3` | Rechazar | No existen copias negativas. |
| 9 | lectores, 2 | documento `…001` ya existe | Rechazar | Identificador único (`UNIQUE` en `cuenta`). |
| 10 | lectores, 3 | correo vacío | Rechazar | La notificación de mora necesita el correo; el esquema lo exige. |
| 11 | lectores, 4 | correo sin `@` | Rechazar | No se puede adivinar el correo correcto. |
| 12 | lectores, 5 | teléfono `tres-cero-cero` | Rechazar | Dato inválido; el esquema también lo exige (`CHECK`). |
| 13 | lectores, 6 | documento vacío | Rechazar | Identificador obligatorio. |
| 14 | lectores, 7 | nombres vacíos | Rechazar | Obligatorio. |

### Correcciones automáticas y reglas adicionales

| Caso | Acción | Justificación |
|---|---|---|
| Espacios al inicio o al final | Corregir (`trim`) | No descartar datos válidos por formato. |
| Correo con mayúsculas | Corregir (`lower`) | Normalizar para comparar duplicados y buscar. |
| ISBN con guiones (`978-0000000103`) | Corregir (quitar guiones) | Es el mismo ISBN escrito de otra forma. |
| Categoría que no existe todavía | Crearla y usar su clave | La categoría es un dato válido del catálogo. |
| ISBN repetido dentro del mismo archivo | Conservar el primero, rechazar el resto | La copia va a la bitácora. |
| Documento o correo repetido dentro del archivo | Conservar el primero, rechazar el resto | Un documento identifica a una sola persona. |
| Correo ya usado por otra cuenta | Rechazar (`correo ya registrado`) | Cada lector debe tener su correo para las notificaciones. Regla del script; no es una restricción `UNIQUE` del esquema. |

## Preguntas del laboratorio y resultados

### 1. ¿Por qué un `COPY` directo a la tabla final no sirve para un archivo con errores?

Se probó cargando `libros_semilla_con_errores.csv` directamente en una tabla con las mismas restricciones que la tabla final:

```
ERROR:  null value in column "titulo" of relation "libro_directo" violates not-null constraint
DETAIL:  Failing row contains (9780000000033, null, Julio Cortázar, Novela, 1963, 3).
CONTEXT:  COPY libro_directo, line 3: "9780000000033,,Julio Cortázar,Novela,1963,3"
```

1. **Es todo o nada.** `COPY` es una sola sentencia: al fallar la línea 3 también se deshace la línea 2, que estaba bien.
2. **Solo se ve el primer error.** El archivo trae 8 filas malas por motivos distintos y habría que corregir y repetir 8 veces.
3. **El mensaje es del motor, no del negocio.** Además, varios errores ni llegan a la restricción: un texto en una columna `integer` falla al convertir el tipo, y una fila con una columna de más falla al partir la línea.

### 2. ¿Qué pasa si se vuelve a correr la carga limpia?

- **Libros:** las 32 filas salen rechazadas con el motivo `isbn ya existe en el catálogo`.
- **Lectores:** las 20 filas salen rechazadas con el motivo `documento ya existe`.

No se duplica nada: con solo la semilla quedan 32 libros, 94 ejemplares, 9 categorías y 20 cuentas. La carga se puede repetir sin riesgo, y cada intento queda en la bitácora.

### 3. Prueba de la última línea de defensa

**Qué se hizo.** Se copió `carga-libros.sql` a `prueba-sin-regla-titulo.sql` y se comentó la regla `WHEN titulo = '' THEN 'título vacío'` del `CASE` (el original no se tocó). Se cargó `datos/prueba_titulo_vacio.csv`, que trae 2 filas válidas, 1 con título vacío y 1 sin autor.

**Qué pasó en la base de datos.**

1. Sin la regla, la fila de título vacío pasó la validación y llegó al `INSERT` en `libro`.
2. La frenó el `CHECK` del esquema (`libro_check`, que exige título y autor no vacíos):

```
ERROR:  new row for relation "libro" violates check constraint "libro_check"
DETAIL:  Failing row contains (40, 7, 9780000000203, , Autor Tres, null, 2003, t).
```

3. El error abortó la transacción (`BEGIN ... COMMIT`) y PostgreSQL la revirtió completa.

**Resultado en los datos.**

- Ninguna fila del archivo entró a `libro`, ni siquiera las dos válidas.
- La bitácora quedó sin registros de esa carga: la fila del autor vacío, que sí tenía su regla activa, tampoco quedó registrada, porque el error ocurrió antes del paso que escribe en `carga.rechazo_carga`.
- Con la regla activa (script normal, mismo archivo) el resultado fue 2 cargadas y 2 rechazadas, con los motivos `título vacío` y `autor vacío`.

**Conclusión.** Los `CHECK` evitan que entre un dato inválido, pero no sirven como sistema de carga masiva: un solo error cancela toda la carga y se pierde la información de diagnóstico. Por eso hay que validar antes, en la tabla de paso, con motivos legibles.

## CSV propio

`postgres/scripts/datos/libros_propio.csv`: 5 libros válidos que no están en la semilla (uno con el ISBN escrito con guion, que se corrige, y una categoría nueva, `Autoayuda`) y 3 errores que no aparecen en los archivos del curso.

| Línea | Error | Motivo registrado |
|---|---|---|
| 7 | Mismo ISBN dos veces en el archivo | isbn repetido en el archivo |
| 8 | Año 2101 | año fuera de rango |
| 9 | ISBN de 12 dígitos | isbn no tiene 13 dígitos |

Resultado: 5 cargadas y 3 rechazadas.

## S16: los cuatro reportes

Los reportes están en `postgres/scripts/reportes.sql`; cada consulta lleva encima un comentario con qué devuelve, las decisiones tomadas y el resultado esperado con los datos de prueba.

### Reglas del grupo

- Un préstamo está **abierto** si no tiene fila en `devolucion` (no se usa `prestamo.estado`, que sin el trigger del Hito 4 no se actualiza sola).
- **Mora:** préstamo abierto con `fecha_limite < CURRENT_DATE`. El préstamo que vence hoy **no** está en mora.
- Un préstamo devuelto después de su `fecha_limite` ya no es mora: ya se devolvió.
- **"Libros leídos"** son los préstamos devueltos.
- Plazo de préstamo: 14 días (`fecha_limite = fecha_prestamo + 14`).

### Decisiones por reporte

| Reporte | La unidad es… | Qué devuelve y decisiones |
|---|---|---|
| 1. Los 20 libros más prestados | el libro | Título y número de préstamos de todas las copias juntas. Empates en el puesto 20: `FETCH FIRST 20 ROWS WITH TIES` incluye a todos los empatados. Los libros sin préstamos salen con 0 solo si el top 20 no se completa con libros prestados. |
| 2. El o los lectores que más han leído | el lector | Solo cuentan los préstamos con devolución. Empates: `= max(...)` devuelve a todos los empatados (`LIMIT 1` dejaría uno por fuera). |
| 3. Lectores morosos | el lector, una vez | `EXISTS` evita repetir al lector que tiene varios préstamos en mora. |
| 4. Préstamos en mora | el préstamo | Nombre, correo y teléfono del lector, libro, fecha límite y días de mora, de mayor a menor mora. Es la lista del botón "Enviar notificación". |

### Cómo cambia respecto al demo del profesor

- **El préstamo apunta a un ejemplar**, no al libro: cada reporte lleva un join más (`prestamo → ejemplar → libro`) y el reporte 1 agrupa por libro, no por copia.
- **Los datos del lector** (nombre, correo, teléfono) están en `cuenta`, no en una tabla `lector`.
- **La fecha esperada de devolución** es `prestamo.fecha_limite`.
- **Un préstamo abierto** es el que no tiene fila en `devolucion`; se resuelve con `NOT EXISTS`.

## Datos de prueba

`postgres/scripts/datos-prueba.sql` inserta 29 préstamos (21 devueltos y 8 abiertos) sobre la semilla de 32 libros y 20 lectores. Los préstamos abiertos usan `prestamo.estado = 'en_uso'` y los devueltos `'devuelto'`; los ejemplares con préstamo abierto quedan en `'prestado'`. Las fechas son relativas a `CURRENT_DATE`, así que la mora da lo mismo el día de la sustentación. El resultado esperado de cada caso está escrito en el encabezado del script, antes de las consultas.

| # | Caso | Reporte | Qué debe pasar |
|---|---|---|---|
| 1 | Libro que nadie ha prestado | 1 | No aparece: ya hay 22 libros con préstamos |
| 2 | Empate en el último puesto del top | 1 | Salen los 18 libros empatados con 1 préstamo (22 filas en total) |
| 3 | Dos lectores empatados en el primer lugar | 2 | Salen Mariana y Santiago, con 4 devueltos cada uno |
| 4 | Lector con préstamos abiertos y ninguno devuelto | 2 | Juan David no sale, aunque tiene 5 préstamos |
| 5 | Préstamo devuelto después de la fecha límite | 3 y 4 | No cuenta como mora |
| 6 | Préstamo abierto que vence hoy | 3 y 4 | No está en mora (regla `<`) |
| 7 | Lector con dos préstamos en mora | 3 y 4 | Una vez en el reporte 3 y dos veces en el 4 |
| 8 | Lector sin ningún préstamo | Todos | No aparece en ningún reporte |

Resultado con los datos de prueba: el reporte 1 devuelve 22 filas, el 2 devuelve 2, el 3 devuelve 3 y el 4 devuelve 4. Los 8 casos coincidieron con lo esperado en la primera corrida. La tabla de verificación completa, con la salida de `psql`, está en [`entregas/S16/verificacion-parte-b.md`](entregas/S16/verificacion-parte-b.md).

## Checkpoint del Hito 2

| Pieza | Dónde quedó | Sesión |
|---|---|---|
| Esquema que corre limpio desde `postgres/init/` con la base vacía | `postgres/init/01_esquema.sql` | S14 |
| Carga de libros y lectores desde CSV, con el semilla y con un CSV propio | `postgres/scripts/carga-*.sql` y `postgres/scripts/datos/` | S14 |
| Validación de filas mal formadas y duplicados, con bitácora | Los mismos scripts de carga y las tablas de criterios de este README | S14 |
| Las consultas de los 4 reportes, documentadas | `postgres/scripts/reportes.sql` (y `datos-prueba.sql`) | S16 |

## Decisiones de diseño

- **Bitácora fuera del modelo.** `carga.rechazo_carga` vive en un esquema aparte (`carga`) para no alterar el modelo de la biblioteca. Las tablas de paso son temporales y se borran al terminar cada carga.
- **Correo y teléfono obligatorios** en `cuenta`, con `CHECK` de formato, porque la notificación de mora debe mostrar nombre, correo y teléfono del lector.
- **Ejemplares.** El CSV trae una cantidad; el esquema guarda una fila por copia, con `codigo = isbn-número de copia` y `estado = 'disponible'`.
- **Lectores.** Se cargan en `cuenta` con el rol `lector`. El `usuario` es el documento y la contraseña inicial es el documento con hash bcrypt, nunca en texto plano.
- **Devolución.** `devolucion` usa `id_prestamo` como llave primaria y a la vez foránea hacia `prestamo`: hay como máximo una devolución por préstamo y no tiene id propio.
- **Notificación sin tabla.** La notificación es una funcionalidad del sistema y no necesita tabla; el reporte de préstamos en mora es una consulta.
- **Esquemas en los scripts de carga.** Trabajan con `search_path` en `carga, public` (`public` para que `crypt` y `gen_salt` de `pgcrypto` sigan disponibles) y escriben `biblioteca.` delante de cada tabla del modelo; solo la bitácora vive en `carga`.
- **Datos de prueba repetibles.** Los préstamos de prueba los registra una cuenta de bibliotecario `bib_prueba`; al volver a correr `datos-prueba.sql`, primero se borra todo lo que esa cuenta registró y se vuelve a crear.

## Archivos de salida

Los registros de consola de `psql` están en `docs/salidas/`:

| Archivo | Contenido |
|---|---|
| `01-libros-limpio.txt` | Carga limpia inicial de libros |
| `02-libros-con-errores.txt` | Detección de los 8 errores en libros |
| `03-lectores-con-errores.txt` | Detección de los 6 errores en lectores |
| `04-csv-propio.txt` | CSV propio: 5 cargadas y 3 rechazadas |
| `05-prueba-ultima-linea-defensa.txt` | Evidencia del `ROLLBACK` al comentar una regla del `CASE` |
| `06-reportes-parte-b.txt` | Salida de los cuatro reportes con los datos de prueba (S16) |

La tabla de verificación de la parte B está en `entregas/S16/verificacion-parte-b.md` (fuera de `docs/`).

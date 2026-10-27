𝐒𝟏𝟒 / 𝐇𝐢𝐭𝐨 𝟐: 𝐄𝐬𝐪𝐮𝐞𝐦𝐚 𝐝𝐞𝐥 𝐏𝐫𝐨𝐲𝐞𝐜𝐭𝐨 𝐞𝐧 𝐏𝐨𝐬𝐭𝐠𝐫𝐞𝐒𝐐𝐋 𝐲 𝐂𝐚𝐫𝐠𝐚 𝐝𝐞𝐬𝐝𝐞 𝐂𝐒𝐕

Asignatura: Bases de Datos (750006C) - Universidad del Valle
Módulo 4, Sesión 14

--------------------------------------------------------------------------------

 𝐈𝐧𝐭𝐞𝐠𝐫𝐚𝐧𝐭𝐞𝐬 𝐝𝐞𝐥 𝐄𝐪𝐮𝐢𝐩𝐨

| Nombre del Estudiante | Código |
|---|---|
| Alejandro Valencia | 2515411-2724 |
| Nicolas Velasco | 2521994-2724 |
| Daniel Toro | 2521005-2724 |
| María Alejandra Pizarro | 2519474-2724 |

--------------------------------------------------------------------------------

 𝐆𝐮𝐢́𝐚 𝐝𝐞 𝐄𝐣𝐞𝐜𝐮𝐜𝐢𝐨́𝐧

▶ 1. Inicialización del Entorno (Docker)
El esquema de la base de datos se ejecuta automáticamente al levantar el contenedor de PostgreSQL con los datos limpios.

# Reiniciar contenedores y limpiar datos antiguos
docker compose down
rm -rf postgres/data/*

# Levantar PostgreSQL
docker compose up -d postgres

# Confirmar la creación de las tablas del esquema
docker compose exec postgres psql -U curso -d curso -c '\dt biblioteca.*'

▶ 2. Ejecución de Cargas desde psql
Los scripts de carga se corren de forma manual dentro del contenedor de la siguiente manera:

# 1. Carga inicial limpia de libros
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql

# 2. Carga de libros con errores a propósito
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
  -f /scripts/carga-libros.sql

# 3. Carga limpia de lectores
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql

# 4. Carga de lectores con errores
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
  -f /scripts/carga-lectores.sql

# 5. Carga de nuestro CSV propio
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_propio.csv \
  -f /scripts/carga-libros.sql

--------------------------------------------------------------------------------

 𝐌𝐚𝐩𝐞𝐨 𝐂𝐒𝐕 → 𝐄𝐬𝐪𝐮𝐞𝐦𝐚 𝐏𝐫𝐨𝐩𝐢𝐨

Mapeo de los datos del CSV a la estructura real de nuestra base de datos (biblioteca):

| Columna del CSV | Tabla / Columna Destino | Transformación Aplicada | Regla de Validación (Motivo en Bitácora) |
|---|---|---|---|
| `isbn` | `libro.isbn` | `trim(isbn)` | Validación Regex: exactamente 13 dígitos numéricos (`'^[0-9]{13}$'`). |
| `titulo` | `libro.titulo` | `trim(titulo)` | No vacíos ni nulos. |
| `autor` | `autor.nombre` / `libro_autor` | Normalización e inserción en tabla asociativa. | Campo requerido. |
| `categoria` | `categoria.nombre` / `libro.id_categoria` | Inserción/búsqueda con `ON CONFLICT DO NOTHING`. | Campo requerido. |
| `anio_publicacion` | `libro.anio_publicacion` | Conversión a `smallint` | Numérico entre 1 y 4 dígitos, rango de 1450 al año actual. |
| `ejemplares_disponibles` | `ejemplar` | Se generan n filas individuales usando `generate_series(1, n)`. | Entero mayor o igual a 0. |
| `documento` | `usuario.documento` | `trim(documento)` | Numérico entre 6 y 15 dígitos. |
| `nombres` | `usuario.nombres` | `trim(nombres)` | No vacíos. |
| `apellidos` | `usuario.apellidos` | `trim(apellidos)` | No vacíos. |
| `correo` | `usuario.correo` | `lower(trim(correo))` | Validación Regex de estructura de email válida. |
| `telefono` | `lector.telefono` | `trim(telefono)` | Numérico entre 7 y 15 dígitos. |

--------------------------------------------------------------------------------

 𝐂𝐫𝐢𝐭𝐞𝐫𝐢𝐨𝐬 𝐩𝐨𝐫 𝐓𝐢𝐩𝐨 𝐝𝐞 𝐄𝐫𝐫𝐨𝐫

Criterios aplicados al procesar las filas con errores en las cargas:

| Tipo de Error Encontrado | Acción | Justificación |
|---|---|---|
| **ISBN duplicado en catálogo** | Rechazar | Evita violar la Primary Key y duplicar registros en el catálogo real. |
| **ISBN repetido dentro del mismo CSV** | Dejar el primero, rechazar el resto | Mantiene la primera aparición válida y manda la copia a la bitácora. |
| **Falta título, autor o categoría** | Rechazar | Atributos obligatorios para la coherencia del catálogo. |
| **Año no numérico o fuera de rango** | Rechazar | Datos inconsistentes (números romanos o años futuros). |
| **Ejemplares negativos o texto** | Rechazar | No se pueden crear inventarios o copias físicas negativas. |
| **Filas con columnas de más o de menos** | Rechazar | Estructura de línea rota por delimitadores o mal formato. |
| **Documento o correo duplicado** | Rechazar | Violación de las restricciones `UNIQUE` en la tabla de usuarios. |
| **Espacios extra a los lados** | Corregir (`trim`) | Limpieza simple para no descartar datos válidos por formato. |
| **Correos con mayúsculas** | Corregir (`lower`) | Normalización para búsquedas e inicios de sesión. |
| **Errores de CSV propio** | Rechazar | Casos de prueba propios para validar las expresiones regulares. |

--------------------------------------------------------------------------------

 𝐏𝐫𝐮𝐞𝐛𝐚 𝐝𝐞 𝐥𝐚 𝐔́𝐥𝐭𝐢𝐦𝐚 𝐋𝐢́𝐧𝐞𝐚 𝐝𝐞 𝐃𝐞𝐟𝐞𝐧𝐬𝐚

▶ Lo que se hizo:
Comentamos a propósito la regla del CASE que valida los ejemplares negativos en carga-libros.sql y volvimos a correr la carga con el archivo de errores.

▶ Lo que pasó en la base de datos:
1. Al quitar la validación del script, la fila defectuosa logró pasar la tabla de paso (stg_libro) e intentó insertarse en la tabla final libro.
2. Ahí la frenó directamente la restricción de la tabla: CHECK (ejemplares_disponibles >= 0).
3. Esto lanzó una excepción SQL que provocó un ROLLBACK automático de toda la transacción.

▶ Resultado en los datos:
* Ninguna fila del archivo entró a la tabla libro (ni siquiera las filas buenas).
* La bitácora de rechazos quedó vacía para esa carga porque el error abortó el bloque completo (BEGIN ... COMMIT).

▶ Conclusión:
Queda demostrado que los CHECK de las tablas son solo un respaldo final para la integridad del esquema, pero no sirven como sistema de carga masiva. Si dependemos de los CHECK, un solo error en una fila cancela toda la transacción y deja a los usuarios sin registros de bitácora. Por eso es necesario validar previamente en la tabla de paso.

--------------------------------------------------------------------------------

 𝐀𝐫𝐜𝐡𝐢𝐯𝐨𝐬 𝐝𝐞 𝐒𝐚𝐥𝐢𝐝𝐚

Las capturas y registros de consola de psql están guardados en /docs/salidas/:

* 01-libros-limpio.txt (Carga limpia inicial de libros)
* 02-libros-con-errores.txt (Detección de los 8 errores en libros)
* 03-lectores-con-errores.txt (Detección de errores en lectores)
* 04-csv-propio.txt (Ejecución del CSV propio con 3 errores)
* 05-prueba-ultima-linea.txt (Evidencia del ROLLBACK de la transacción al remover el CASE)

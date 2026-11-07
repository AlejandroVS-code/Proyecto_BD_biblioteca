# S16, parte B: tabla de verificación de los cuatro reportes

**Grupo 2 · Bases de Datos (750006C) · Universidad del Valle**
Corrida: 2026-11-07, con `datos-prueba.sql` (29 préstamos: 21 devueltos y 8 abiertos) sobre la semilla de 32 libros y 20 lectores.

## Reglas del grupo

- Un préstamo está abierto si no tiene fila en `devolucion` (no se usa `prestamo.estado`).
- Mora: préstamo abierto con `fecha_limite < CURRENT_DATE`. El que vence hoy no está en mora.
- Un préstamo devuelto después de su `fecha_limite` ya no es mora.
- "Libros leídos" son los préstamos devueltos.
- Plazo de préstamo: 14 días. Las fechas de prueba son relativas a `CURRENT_DATE`.

## Verificación por caso

| # | Caso | Reporte | Resultado esperado (escrito antes de correr) | Resultado obtenido | ¿Coincidió? |
|---|---|---|---|---|---|
| 1 | Libro que nadie ha prestado (`…023` a `…032`) | 1 | No aparece: ya hay 22 libros con préstamos y el reporte solo muestra el top 20 con sus empatados | Ninguno de los 10 libros sin préstamos aparece | Sí |
| 2 | Empate en el último puesto del top | 1 | 18 libros con 1 préstamo empatados en el puesto 20: salen los 18, 22 filas en total | 22 filas: 4 libros con 4, 3, 2 y 2 préstamos y 18 con 1 | Sí |
| 3 | Dos lectores empatados en el primer lugar | 2 | Mariana y Santiago, con 4 devueltos cada uno | Mariana Gómez Rojas 4 y Santiago Rodríguez Pérez 4 | Sí |
| 4 | Lector con préstamos abiertos y ninguno devuelto | 2 | Juan David (5 préstamos, 0 devueltos) no sale | No aparece | Sí |
| 5 | Devuelto después de la fecha límite | 3 y 4 | El Quijote de Santiago (devuelto 6 días tarde) no cuenta como mora | Santiago no está en el reporte 3 y el Quijote no está en el reporte 4 | Sí |
| 6 | Préstamo abierto que vence hoy | 3 y 4 | Rayuela de Juan David (`fecha_limite = CURRENT_DATE`) no está en mora | No aparece en el reporte 4 | Sí |
| 7 | Lector con dos préstamos en mora | 3 y 4 | Juan David: 1 vez en el reporte 3 y 2 veces en el reporte 4 | 1 fila en el reporte 3 y 2 filas en el reporte 4 (Ficciones, 26 días, y Cien años de soledad, 6 días) | Sí |
| 8 | Lectores sin ningún préstamo (Sebastián y `1000000011` a `1000000020`) | Todos | No aparecen en ningún reporte | No aparecen en ninguno de los cuatro | Sí |

**Correcciones:** ninguna. Los cuatro reportes coincidieron con lo esperado en la primera corrida, tanto en consultas como en expectativas.

**Resultados completos esperados y obtenidos**

| Reporte | Esperado | Obtenido |
|---|---|---|
| 1 | 22 filas | 22 filas |
| 2 | 2 filas | 2 filas |
| 3 | 3 filas (Camila, Valentina, Juan David) | 3 filas, las mismas |
| 4 | 4 filas (Juan David ×2, Valentina, Camila) | 4 filas, las mismas y en el mismo orden |

## Salida de `psql` (2026-11-07)

### Reporte 1. Los 20 libros más prestados

```
               titulo                | prestamos
-------------------------------------+-----------
 Cien años de soledad                |         4
 Rayuela                             |         3
 Don Quijote de la Mancha            |         2
 Ficciones                           |         2
 1984                                |         1
 Alicia en el país de las maravillas |         1
 Breve historia del tiempo           |         1
 Como agua para chocolate            |         1
 Cosmos                              |         1
 Crónica de una muerte anunciada     |         1
 El Aleph                            |         1
 El amor en los tiempos del cólera   |         1
 El principito                       |         1
 El túnel                            |         1
 Fahrenheit 451                      |         1
 La casa de los espíritus            |         1
 La sombra del viento                |         1
 Los detectives salvajes             |         1
 Matilda                             |         1
 Pedro Páramo                        |         1
 Sapiens: de animales a dioses       |         1
 Un mundo feliz                      |         1
(22 rows)
```

### Reporte 2. El o los lectores que más libros han leído

```
 nombres  |    apellidos    | devueltos
----------+-----------------+-----------
 Mariana  | Gómez Rojas     |         4
 Santiago | Rodríguez Pérez |         4
(2 rows)
```

### Reporte 3. Lectores morosos

```
 documento  |  nombres   |    apellidos
------------+------------+------------------
 1000000005 | Camila     | Hernández Torres
 1000000003 | Valentina  | López Díaz
 1000000004 | Juan David | Martínez Ruiz
(3 rows)
```

### Reporte 4. Préstamos en mora

```
          lector          |                 correo                 |  telefono  |         titulo          | fecha_limite | dias_mora
--------------------------+----------------------------------------+------------+-------------------------+--------------+-----------
 Juan David Martínez Ruiz | juan.martinez@correo-ejemplo.edu.co    | 3001000004 | Ficciones               | 2026-10-12   |        26
 Valentina López Díaz     | valentina.lopez@correo-ejemplo.edu.co  | 3001000003 | La sombra del viento    | 2026-10-22   |        16
 Juan David Martínez Ruiz | juan.martinez@correo-ejemplo.edu.co    | 3001000004 | Cien años de soledad    | 2026-11-01   |         6
 Camila Hernández Torres  | camila.hernandez@correo-ejemplo.edu.co | 3001000005 | Los detectives salvajes | 2026-11-05   |         2
(4 rows)
```

Las columnas de fecha y de días de mora dependen del día en que se corre el script; con otra fecha cambian los números, pero no los casos.

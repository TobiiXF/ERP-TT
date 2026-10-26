# TiendaTeresa - Sistema web local (ferretería / pernería)

Stack: Vue 3 + Vite + Tailwind (frontend) · Node.js + Express (API) · PostgreSQL · ApexCharts.
Usuario inicial: **admin** / **1234** (cámbiala en "Cambiar contraseña" antes de usarlo en serio).

**Instalación paso a paso en Windows: ver `GUIA_INSTALACION.md` (doble clic en `instalar.bat` y luego en `iniciar.bat`).**

## Puesta en marcha manual
Requisitos: Node.js 20 LTS y PostgreSQL 14+.
1. Base de datos: crea la base e instala el script (ver "Base de datos" abajo).
2. Backend:
   ```
   cd backend
   copy .env.example .env      (Linux/Mac: cp .env.example .env)
   ```
   Edita `.env`: `DB_USER`, `DB_PASSWORD` y cambia `JWT_SECRET` por un texto largo y aleatorio.
   ```
   npm install
   ```
3. Frontend (compilar una sola vez o tras cada cambio):
   ```
   cd frontend
   npm install
   npm run build
   ```
4. Iniciar: `cd backend` y `npm start`. Abre http://localhost:3000.
   Desde otras PCs de la red local: `http://IP-DE-ESTA-PC:3000` (abre el puerto 3000 en el firewall de Windows).

Modo desarrollo: `npm run dev` en `backend` y `npm run dev` en `frontend` (http://localhost:5173, con proxy a la API).

## Módulos (menú agrupado en el orden del documento; nombres y orden en la tabla `modulos`)
1. **Administrador**: Usuarios, Tasas y precios, Bitácora.
2. **Activos Fijos**: en construcción (fase 2).
3. **Contabilidad**: Libro diario (asientos automáticos) y Caja (submódulo).
4. **Inventario**: Productos y stock.
5. **Proveedor**: Proveedores y Compras.
6. **Venta**: administración de ventas (consultar, anular, auditoría).
7. **VENTA**: Punto de venta y Mis ventas (cajero).
8. **Reportes**: Dashboard y Arqueo de mi turno (cajero).

Bases instaladas antes del catálogo de módulos: ejecutar una vez `migraciones/001_modulos_tiendateresa.sql`.

### Detalle
- **Dashboard** (ApexCharts): ventas de hoy y del mes, ventas de 14 días, top 10 más y menos vendidos, stock bajo.
- **Punto de venta (VENTA)**: búsqueda, variantes, unidades (CAJA, PAQUETE...), descuento, cliente, cobro en efectivo y ticket.
  El precio siempre sale de la base de datos: el cajero no puede cambiarlo.
- **Ventas (venta)**: consulta con filtros, detalle, historial de la bitácora y anulación con motivo (devuelve stock y revierte caja y asiento).
- **Inventario**: productos simples y matriciales, matriz de variantes (medida × largo), unidades de conversión, imágenes, ajustes, mermas y kardex.
- **Compras y proveedores**: compra atómica (stock + kardex + caja + asiento contable) y anulación.
- **Caja / Arqueo**: el cajero ve solo su turno; el admin y el contador ven todo.
- **Tasas y precios**: registro BCB/paralelo, recálculo masivo y configuración (redondeo, intentos de login...).
- **Usuarios**: alta con contraseña temporal (cambio obligatorio en el primer ingreso), reseteo, bloqueo y desbloqueo.
- **Bitácora**: auditoría de logins, cambios y anulaciones.

Seguridad: JWT, contraseñas bcrypt, bloqueo tras N intentos fallidos y permisos validados en el servidor (no solo se ocultan en pantalla).
Imágenes: `backend/public/uploads/productos/`; la base guarda solo la ruta relativa (`/uploads/productos/archivo.jpg`).

Pendiente para la fase 2: módulos de contabilidad (libro diario y mayor), activos fijos e importación desde Excel.
Los asientos de compras y ventas ya se generan solos.

---

# Base de datos (PostgreSQL)

24 tablas: las 23 del documento + `modulos` (catálogo de los 8 módulos; `permisos.modulo` es una FK a `modulos.codigo`). El permiso de caja es `contabilidad.caja_*`.

Usuario inicial del sistema: **admin** / **1234** (rol Administrador, hash bcrypt en `usuarios.password_hash`).

## Opción A: PostgreSQL instalado en la PC (pgAdmin / DBeaver)
1. Crear la base: `CREATE DATABASE tiendateresa;`
2. Ejecutar `tiendateresa_completo.sql` sobre esa base (Query Tool de pgAdmin o "Ejecutar script" en DBeaver), o:
   `psql -U postgres -d tiendateresa -f tiendateresa_completo.sql`

## Opción B: Docker Compose
Copia `.env.example` a `.env` y cambia la contraseña. Luego ejecuta `docker compose up -d`; los scripts de `database/` corren solos la primera vez.

## Pruebas
`psql -U postgres -d tiendateresa -f pruebas/pruebas.sql`
Prueba reglas, precios, stock y flujos de compra y venta dentro de una transacción que se revierte, así que no deja datos.
Debe terminar con `=== TODAS LAS PRUEBAS PASARON ===`. Conviene correrlas después de cada cambio al esquema.

## Notas
- El script se ejecuta **una sola vez** sobre una base vacía. Si lo vuelves a correr falla al inicio y no cambia nada.
- Los costos en USD usan 4 decimales (`DECIMAL(12,4)`) para soportar piezas que cuestan fracciones de centavo.
- La zona horaria de la base queda en `America/La_Paz`.
- Las tablas nuevas que se agreguen después no quedan protegidas contra DELETE automáticamente: hay que crearles el trigger `fn_prohibir_delete`.

## Contenido
- `database/01_schema.sql`  24 tablas (23 + modulos), ENUMs, FKs, CHECK stock >= 0, índices.
- `database/02_reglas.sql`  Bloqueo de DELETE físico, bitácora inmutable, `actualizado_en` automático,
  rol/usuario Superusuario intocable, stock matricial = suma de variantes, motor de precios
  (`fn_tasa_activa`, `fn_calcular_precio`, `fn_redondear_precio`, `fn_recalcular_precios`) y vistas de reportes
  (`v_stock_actual`, `v_stock_bajo`, `v_valorizacion_inventario`, `v_productos_vendidos`, `v_arqueo_caja`, `v_permisos_usuario`).
- `database/03_seed.sql`  Sucursal "Casa Matriz", 5 roles + permisos, usuario admin, configuración,
  tasa BCB 6.96, cliente "Público General", categoría "General", plan de cuentas básico.

## Verificar login desde Node (bcrypt / bcryptjs)
```js
const ok = await bcrypt.compare('1234', usuario.password_hash);
```

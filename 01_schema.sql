-- =====================================================================
-- TiendaTeresa (Ferretería / Pernería) - Esquema PostgreSQL
-- Generado a partir de "notas, avance.docx" (sección 8: Modelo de datos)
-- =====================================================================
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Zona horaria de Bolivia (CURRENT_DATE / NOW() correctos para tasas y caja del día)
DO $$ BEGIN
  EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'America/La_Paz');
END $$;
SET timezone TO 'America/La_Paz';

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
CREATE TYPE estado_usuario        AS ENUM ('ACTIVO','INACTIVO','BLOQUEADO');
CREATE TYPE estado_sucursal       AS ENUM ('ACTIVA','INACTIVA');
CREATE TYPE accion_auditoria      AS ENUM ('CREAR','EDITAR','ANULAR','ELIMINAR','LOGIN','LOGOUT','LOGIN_FALLIDO','RESET_PASSWORD');
CREATE TYPE tipo_tasa             AS ENUM ('BCB','PARALELO');
CREATE TYPE fuente_tasa           AS ENUM ('API','MANUAL');
CREATE TYPE tipo_cambio_pref      AS ENUM ('BCB','PARALELO','DEFECTO_SISTEMA');
CREATE TYPE estado_activo_fijo    AS ENUM ('ACTIVO','DADO_BAJA','EN_REPARACION');
CREATE TYPE tipo_cuenta           AS ENUM ('ACTIVO','PASIVO','PATRIMONIO','INGRESO','GASTO');
CREATE TYPE estado_asiento        AS ENUM ('REGISTRADO','ANULADO');
CREATE TYPE tipo_mov_caja         AS ENUM ('ENTRADA_VENTA','SALIDA_COMPRA','AJUSTE');
CREATE TYPE tipo_mov_kardex       AS ENUM ('ENTRADA_COMPRA','SALIDA_VENTA','AJUSTE','MERMA','DEVOLUCION');
CREATE TYPE estado_proveedor      AS ENUM ('ACTIVO','INACTIVO');
CREATE TYPE tipo_doc_compra       AS ENUM ('FACTURA','RECIBO','NOTA');
CREATE TYPE metodo_pago_compra    AS ENUM ('EFECTIVO','TRANSFERENCIA');
CREATE TYPE estado_compra         AS ENUM ('PENDIENTE','PAGADA','ANULADA');
CREATE TYPE tipo_doc_venta        AS ENUM ('NOTA_VENTA','FACTURA_PENDIENTE','TICKET');
CREATE TYPE metodo_pago_venta     AS ENUM ('EFECTIVO');
CREATE TYPE estado_venta          AS ENUM ('COMPLETADA','ANULADA');

-- ---------------------------------------------------------------------
-- 2.1 MÓDULO ADMINISTRADOR
-- ---------------------------------------------------------------------
CREATE TABLE sucursales (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL,
    direccion       TEXT,
    telefono        VARCHAR(30),
    nit             VARCHAR(30),
    estado          estado_sucursal NOT NULL DEFAULT 'ACTIVA',
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL
);

CREATE TABLE roles (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(80) NOT NULL UNIQUE,
    descripcion     TEXT,
    es_sistema      BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE = rol intocable
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL,
    eliminado_en    TIMESTAMP NULL,
    eliminado_por   INT NULL
);

CREATE TABLE usuarios (
    id                    SERIAL PRIMARY KEY,
    username              VARCHAR(50) NOT NULL UNIQUE,
    nombre_completo       VARCHAR(150) NOT NULL,
    password_hash         VARCHAR(255) NOT NULL,          -- bcrypt
    email                 VARCHAR(150) NULL,              -- [V2]
    rol_id                INT NOT NULL REFERENCES roles(id),
    sucursal_id           INT NOT NULL REFERENCES sucursales(id),
    estado                estado_usuario NOT NULL DEFAULT 'ACTIVO',
    ultimo_acceso         TIMESTAMP NULL,
    debe_cambiar_password BOOLEAN NOT NULL DEFAULT TRUE,
    intentos_fallidos     INTEGER NOT NULL DEFAULT 0,
    fecha_bloqueo         TIMESTAMP NULL,
    foto_url              VARCHAR(255) NULL,              -- [V2]
    telefono              VARCHAR(30) NULL,               -- [V2]
    creado_por            INT NOT NULL,
    creado_en             TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por       INT NULL,
    actualizado_en        TIMESTAMP NULL,
    eliminado_en          TIMESTAMP NULL,
    eliminado_por         INT NULL
);

-- Catálogo de los 8 módulos del sistema (nombre visible y orden del menú)
CREATE TABLE modulos (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(50) NOT NULL UNIQUE,   -- clave usada en permisos.modulo
    nombre          VARCHAR(60) NOT NULL,          -- nombre visible en el ERP
    orden           SMALLINT NOT NULL UNIQUE,
    descripcion     TEXT,
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL,
    eliminado_en    TIMESTAMP NULL,
    eliminado_por   INT NULL
);

CREATE TABLE permisos (
    id              SERIAL PRIMARY KEY,
    rol_id          INT NOT NULL REFERENCES roles(id),
    modulo          VARCHAR(50) NOT NULL REFERENCES modulos(codigo) ON UPDATE CASCADE,
    accion          VARCHAR(50) NOT NULL,   -- 'ver','crear','editar','anular',...
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL,
    eliminado_en    TIMESTAMP NULL,
    eliminado_por   INT NULL,
    UNIQUE (rol_id, modulo, accion)
);

CREATE TABLE bitacora_auditoria (
    id                SERIAL PRIMARY KEY,
    usuario_id        INT NULL REFERENCES usuarios(id),   -- NULL si login fallido con usuario inexistente
    tabla_afectada    VARCHAR(80),
    registro_id       INTEGER,
    accion            accion_auditoria NOT NULL,
    datos_anteriores  JSONB,
    datos_nuevos      JSONB,
    fecha_hora        TIMESTAMP NOT NULL DEFAULT NOW(),
    ip_origen         VARCHAR(45)
);

CREATE TABLE tasas_de_cambio (
    id              SERIAL PRIMARY KEY,
    fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
    hora            TIME NOT NULL DEFAULT LOCALTIME,
    tipo            tipo_tasa NOT NULL,
    valor           DECIMAL(10,4) NOT NULL CHECK (valor > 0),
    fuente          fuente_tasa NOT NULL,
    usuario_id      INT NULL REFERENCES usuarios(id),  -- NULL si fue API
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL
);

CREATE TABLE configuracion_sistema (
    id              SERIAL PRIMARY KEY,
    clave           VARCHAR(80) NOT NULL UNIQUE,
    valor           TEXT,
    descripcion     TEXT,
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL
);

-- ---------------------------------------------------------------------
-- 2.5 MÓDULO PROVEEDOR (antes que activos_fijos por la FK)
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id                    SERIAL PRIMARY KEY,
    nombre                VARCHAR(150) NOT NULL,
    nit                   VARCHAR(30) NULL,
    contacto              VARCHAR(150),
    telefono              VARCHAR(30),
    email                 VARCHAR(150),
    direccion             TEXT,
    tipo_cambio_preferido tipo_cambio_pref NOT NULL DEFAULT 'DEFECTO_SISTEMA',
    condiciones_pago      TEXT,
    tiempo_entrega_dias   INT NULL,                                    -- [V2]
    calificacion          INT NULL CHECK (calificacion BETWEEN 1 AND 5), -- [V2]
    estado                estado_proveedor NOT NULL DEFAULT 'ACTIVO',
    creado_por            INT NOT NULL,
    creado_en             TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por       INT NULL,
    actualizado_en        TIMESTAMP NULL,
    eliminado_en          TIMESTAMP NULL,
    eliminado_por         INT NULL
);

-- ---------------------------------------------------------------------
-- 2.2 MÓDULO ACTIVOS FIJOS
-- ---------------------------------------------------------------------
CREATE TABLE activos_fijos (
    id                     SERIAL PRIMARY KEY,
    codigo                 VARCHAR(50) NOT NULL UNIQUE,
    descripcion            VARCHAR(255) NOT NULL,
    categoria              VARCHAR(80),             -- 'Computadora','Mobiliario','Vehículo'
    fecha_adquisicion      DATE NOT NULL,
    costo_adquisicion_bob  DECIMAL(10,2) NOT NULL CHECK (costo_adquisicion_bob >= 0),
    vida_util_anios        INTEGER NOT NULL CHECK (vida_util_anios > 0),
    depreciacion_anual_bob DECIMAL(10,2) GENERATED ALWAYS AS (ROUND(costo_adquisicion_bob / vida_util_anios, 2)) STORED,
    ubicacion              VARCHAR(150),
    numero_serie           VARCHAR(100) NULL,                     -- [V2]
    proveedor_id           INT NULL REFERENCES proveedores(id),   -- [V2]
    estado                 estado_activo_fijo NOT NULL DEFAULT 'ACTIVO',
    sucursal_id            INT NOT NULL REFERENCES sucursales(id),
    creado_por             INT NOT NULL,
    creado_en              TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por        INT NULL,
    actualizado_en         TIMESTAMP NULL,
    eliminado_en           TIMESTAMP NULL,
    eliminado_por          INT NULL
);

-- ---------------------------------------------------------------------
-- 2.4 MÓDULO INVENTARIO
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id                 SERIAL PRIMARY KEY,
    nombre             VARCHAR(120) NOT NULL,
    descripcion        TEXT,
    categoria_padre_id INT NULL REFERENCES categorias(id),
    creado_por         INT NOT NULL,
    creado_en          TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por    INT NULL,
    actualizado_en     TIMESTAMP NULL,
    eliminado_en       TIMESTAMP NULL,
    eliminado_por      INT NULL
);

CREATE TABLE productos (
    id                    SERIAL PRIMARY KEY,
    codigo                VARCHAR(50) NOT NULL UNIQUE,
    nombre                VARCHAR(200) NOT NULL,
    descripcion           TEXT,
    categoria_id          INT NOT NULL REFERENCES categorias(id),
    es_matricial          BOOLEAN NOT NULL DEFAULT FALSE,
    unidad_base           VARCHAR(30) NOT NULL DEFAULT 'UNIDAD',
    costo_base_usd        DECIMAL(12,4) NOT NULL DEFAULT 0 CHECK (costo_base_usd >= 0),
    margen_ganancia       DECIMAL(5,2) NOT NULL DEFAULT 0,    -- porcentaje, ej 30.00 = 30%
    tipo_cambio_preferido tipo_cambio_pref NOT NULL DEFAULT 'DEFECTO_SISTEMA',
    precio_venta_bob      DECIMAL(10,2) NOT NULL DEFAULT 0,   -- calculado por motor de precios
    stock_actual          DECIMAL(10,2) NOT NULL DEFAULT 0,   -- solo lectura si es_matricial
    stock_minimo          DECIMAL(10,2) NOT NULL DEFAULT 0,
    imagen_url            VARCHAR(255) NULL,                  -- [V2] ruta relativa /uploads/productos/...
    peso_kg               DECIMAL(10,3) NULL,                 -- [V2]
    ubicacion_almacen     VARCHAR(100) NULL,                  -- [V2]
    sucursal_id           INT NOT NULL REFERENCES sucursales(id),
    creado_por            INT NOT NULL,
    creado_en             TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por       INT NULL,
    actualizado_en        TIMESTAMP NULL,
    eliminado_en          TIMESTAMP NULL,
    eliminado_por         INT NULL,
    CONSTRAINT chk_productos_stock_no_negativo CHECK (stock_actual >= 0)
);

CREATE TABLE variantes_productos (
    id               SERIAL PRIMARY KEY,
    producto_id      INT NOT NULL REFERENCES productos(id),
    codigo_variante  VARCHAR(60) NOT NULL UNIQUE,
    eje_x_valor      VARCHAR(50) NOT NULL,   -- ej: Diámetro
    eje_y_valor      VARCHAR(50) NOT NULL,   -- ej: Largo
    costo_usd        DECIMAL(12,4) NOT NULL DEFAULT 0 CHECK (costo_usd >= 0),
    precio_venta_bob DECIMAL(10,2) NOT NULL DEFAULT 0,
    stock_actual     DECIMAL(10,2) NOT NULL DEFAULT 0,
    creado_por       INT NOT NULL,
    creado_en        TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por  INT NULL,
    actualizado_en   TIMESTAMP NULL,
    eliminado_en     TIMESTAMP NULL,
    eliminado_por    INT NULL,
    CONSTRAINT chk_variantes_stock_no_negativo CHECK (stock_actual >= 0),
    UNIQUE (producto_id, eje_x_valor, eje_y_valor)
);

CREATE TABLE unidades_conversion (
    id                SERIAL PRIMARY KEY,
    producto_id       INT NOT NULL REFERENCES productos(id),
    nombre_unidad     VARCHAR(30) NOT NULL,   -- CAJA, PAQUETE, KILO, UNIDAD
    factor_conversion DECIMAL(10,2) NOT NULL CHECK (factor_conversion > 0),
    precio_venta_bob  DECIMAL(10,2) NOT NULL DEFAULT 0,
    creado_por        INT NOT NULL,
    creado_en         TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por   INT NULL,
    actualizado_en    TIMESTAMP NULL,
    UNIQUE (producto_id, nombre_unidad)
);

-- ---------------------------------------------------------------------
-- 2.5 MÓDULO PROVEEDOR - Compras
-- ---------------------------------------------------------------------
CREATE TABLE compras (
    id                   SERIAL PRIMARY KEY,
    numero_compra        VARCHAR(30) NOT NULL UNIQUE,
    proveedor_id         INT NOT NULL REFERENCES proveedores(id),
    fecha_compra         DATE NOT NULL DEFAULT CURRENT_DATE,
    tipo_documento       tipo_doc_compra NOT NULL,
    numero_documento     VARCHAR(50),
    nit_proveedor        VARCHAR(30) NULL,
    subtotal_usd         DECIMAL(12,4) NOT NULL DEFAULT 0 CHECK (subtotal_usd >= 0),
    tasa_cambio_aplicada DECIMAL(10,4) NOT NULL CHECK (tasa_cambio_aplicada > 0),
    total_bob            DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_bob >= 0),
    metodo_pago          metodo_pago_compra NOT NULL DEFAULT 'EFECTIVO',
    flete_bob            DECIMAL(10,2) NULL,   -- [V2]
    impuestos_bob        DECIMAL(10,2) NULL,   -- [V2]
    estado               estado_compra NOT NULL DEFAULT 'PENDIENTE',
    observaciones        TEXT,
    usuario_id           INT NOT NULL REFERENCES usuarios(id),
    sucursal_id          INT NOT NULL REFERENCES sucursales(id),
    creado_por           INT NOT NULL,
    creado_en            TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por      INT NULL,
    actualizado_en       TIMESTAMP NULL,
    eliminado_en         TIMESTAMP NULL,
    eliminado_por        INT NULL
);

CREATE TABLE detalle_compras (
    id                 SERIAL PRIMARY KEY,
    compra_id          INT NOT NULL REFERENCES compras(id),
    producto_id        INT NOT NULL REFERENCES productos(id),
    variante_id        INT NULL REFERENCES variantes_productos(id),
    cantidad           DECIMAL(10,2) NOT NULL CHECK (cantidad > 0),
    unidad             VARCHAR(30) NOT NULL DEFAULT 'UNIDAD',
    costo_unitario_usd DECIMAL(12,4) NOT NULL CHECK (costo_unitario_usd >= 0),
    subtotal_usd       DECIMAL(12,4) NOT NULL CHECK (subtotal_usd >= 0),
    creado_por         INT NOT NULL,
    creado_en          TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por    INT NULL,
    actualizado_en     TIMESTAMP NULL
);

-- ---------------------------------------------------------------------
-- 2.6 / 2.7 MÓDULO VENTA / venta
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id                 SERIAL PRIMARY KEY,
    nombre             VARCHAR(150) NOT NULL,
    nit                VARCHAR(30) NULL,
    telefono           VARCHAR(30),
    email              VARCHAR(150),
    direccion          TEXT,
    es_generico        BOOLEAN NOT NULL DEFAULT FALSE,
    limite_credito_bob DECIMAL(10,2) NULL,   -- [V2]
    saldo_actual_bob   DECIMAL(10,2) NULL,   -- [V2]
    creado_por         INT NOT NULL,
    creado_en          TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por    INT NULL,
    actualizado_en     TIMESTAMP NULL,
    eliminado_en       TIMESTAMP NULL,
    eliminado_por      INT NULL
);

CREATE TABLE ventas (
    id                     SERIAL PRIMARY KEY,
    numero_venta           VARCHAR(30) NOT NULL UNIQUE,
    cliente_id             INT NOT NULL REFERENCES clientes(id),
    fecha_venta            TIMESTAMP NOT NULL DEFAULT NOW(),
    tipo_documento         tipo_doc_venta NOT NULL DEFAULT 'NOTA_VENTA',
    datos_facturacion      JSONB NULL,
    numero_factura_fiscal  VARCHAR(50) NULL,    -- [V2]
    codigo_control_fiscal  VARCHAR(100) NULL,   -- [V2]
    subtotal_bob           DECIMAL(10,2) NOT NULL DEFAULT 0,
    descuento_bob          DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_bob              DECIMAL(10,2) NOT NULL DEFAULT 0,
    metodo_pago            metodo_pago_venta NOT NULL DEFAULT 'EFECTIVO',
    monto_recibido         DECIMAL(10,2) NOT NULL DEFAULT 0,
    cambio_devuelto        DECIMAL(10,2) NOT NULL DEFAULT 0,
    estado                 estado_venta NOT NULL DEFAULT 'COMPLETADA',
    observaciones          TEXT,
    cajero_id              INT NOT NULL REFERENCES usuarios(id),
    sucursal_id            INT NOT NULL REFERENCES sucursales(id),
    creado_por             INT NOT NULL,
    creado_en              TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por        INT NULL,
    actualizado_en         TIMESTAMP NULL,
    eliminado_en           TIMESTAMP NULL,
    eliminado_por          INT NULL,
    CONSTRAINT chk_ventas_montos CHECK (subtotal_bob >= 0 AND descuento_bob >= 0 AND total_bob >= 0
                                        AND monto_recibido >= 0 AND cambio_devuelto >= 0)
);

CREATE TABLE detalle_ventas (
    id                  SERIAL PRIMARY KEY,
    venta_id            INT NOT NULL REFERENCES ventas(id),
    producto_id         INT NOT NULL REFERENCES productos(id),
    variante_id         INT NULL REFERENCES variantes_productos(id),
    cantidad            DECIMAL(10,2) NOT NULL CHECK (cantidad > 0),
    unidad              VARCHAR(30) NOT NULL DEFAULT 'UNIDAD',
    precio_unitario_bob DECIMAL(10,2) NOT NULL CHECK (precio_unitario_bob >= 0),
    descuento_bob       DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (descuento_bob >= 0),
    subtotal_bob        DECIMAL(10,2) NOT NULL CHECK (subtotal_bob >= 0),
    creado_por          INT NOT NULL,
    creado_en           TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por     INT NULL,
    actualizado_en      TIMESTAMP NULL
);

-- ---------------------------------------------------------------------
-- 2.3 MÓDULO CONTABILIDAD (+ CAJA)
-- ---------------------------------------------------------------------
CREATE TABLE plan_cuentas (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) NOT NULL UNIQUE,
    nombre          VARCHAR(150) NOT NULL,
    tipo            tipo_cuenta NOT NULL,
    cuenta_padre_id INT NULL REFERENCES plan_cuentas(id),
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL,
    eliminado_en    TIMESTAMP NULL,
    eliminado_por   INT NULL
);

CREATE TABLE asientos_contables (
    id               SERIAL PRIMARY KEY,
    fecha            DATE NOT NULL DEFAULT CURRENT_DATE,
    descripcion      TEXT,
    documento_origen VARCHAR(50),                           -- 'VENTA-123','COMPRA-456'
    venta_id         INT NULL REFERENCES ventas(id),        -- [V2]
    compra_id        INT NULL REFERENCES compras(id),       -- [V2]
    activo_fijo_id   INT NULL REFERENCES activos_fijos(id), -- [V2]
    total_debe       DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_haber      DECIMAL(10,2) NOT NULL DEFAULT 0,
    estado           estado_asiento NOT NULL DEFAULT 'REGISTRADO',
    usuario_id       INT NOT NULL REFERENCES usuarios(id),
    creado_por       INT NOT NULL,
    creado_en        TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por  INT NULL,
    actualizado_en   TIMESTAMP NULL,
    eliminado_en     TIMESTAMP NULL,
    eliminado_por    INT NULL
);

CREATE TABLE detalle_asientos (
    id              SERIAL PRIMARY KEY,
    asiento_id      INT NOT NULL REFERENCES asientos_contables(id),
    cuenta_id       INT NOT NULL REFERENCES plan_cuentas(id),
    debe            DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (debe >= 0),
    haber           DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (haber >= 0),
    descripcion     TEXT,
    creado_por      INT NOT NULL,
    creado_en       TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por INT NULL,
    actualizado_en  TIMESTAMP NULL,
    eliminado_en    TIMESTAMP NULL,
    eliminado_por   INT NULL
);

CREATE TABLE caja (
    id                   SERIAL PRIMARY KEY,
    tipo_movimiento      tipo_mov_caja NOT NULL,
    monto_bob            DECIMAL(10,2) NOT NULL,
    descripcion          TEXT,
    documento_referencia VARCHAR(50),
    venta_id             INT NULL REFERENCES ventas(id),
    compra_id            INT NULL REFERENCES compras(id),
    saldo_anterior_bob   DECIMAL(10,2) NULL,   -- [V2]
    saldo_actual_bob     DECIMAL(10,2) NULL,   -- [V2]
    usuario_id           INT NOT NULL REFERENCES usuarios(id),
    sucursal_id          INT NOT NULL REFERENCES sucursales(id),
    fecha_hora           TIMESTAMP NOT NULL DEFAULT NOW(),
    creado_por           INT NOT NULL,
    creado_en            TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por      INT NULL,
    actualizado_en       TIMESTAMP NULL
);

CREATE TABLE kardex_inventario (
    id                   SERIAL PRIMARY KEY,
    producto_id          INT NOT NULL REFERENCES productos(id),
    variante_id          INT NULL REFERENCES variantes_productos(id),
    tipo_movimiento      tipo_mov_kardex NOT NULL,
    cantidad             DECIMAL(10,2) NOT NULL,
    stock_anterior       DECIMAL(10,2) NOT NULL,
    stock_nuevo          DECIMAL(10,2) NOT NULL CHECK (stock_nuevo >= 0),
    costo_unitario_usd   DECIMAL(12,4),
    documento_referencia VARCHAR(50),
    venta_id             INT NULL REFERENCES ventas(id),
    compra_id            INT NULL REFERENCES compras(id),
    caja_id              INT NULL REFERENCES caja(id),   -- [V2]
    usuario_id           INT NOT NULL REFERENCES usuarios(id),
    sucursal_id          INT NOT NULL REFERENCES sucursales(id),
    fecha_hora           TIMESTAMP NOT NULL DEFAULT NOW(),
    creado_por           INT NOT NULL,
    creado_en            TIMESTAMP NOT NULL DEFAULT NOW(),
    actualizado_por      INT NULL,
    actualizado_en       TIMESTAMP NULL,
    eliminado_en         TIMESTAMP NULL,
    eliminado_por        INT NULL
);

-- ---------------------------------------------------------------------
-- FKs de auditoría (creado_por / actualizado_por / eliminado_por -> usuarios)
-- DEFERRABLE para poder sembrar el primer usuario dentro de una transacción.
-- ---------------------------------------------------------------------
DO $$
DECLARE t TEXT; c TEXT;
BEGIN
  FOR t, c IN
    SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name IN ('creado_por','actualizado_por','eliminado_por')
  LOOP
    EXECUTE format(
      'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES usuarios(id) DEFERRABLE INITIALLY DEFERRED',
      t, 'fk_' || t || '_' || c, c);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- ÍNDICES
-- ---------------------------------------------------------------------
CREATE INDEX idx_usuarios_rol            ON usuarios(rol_id);
CREATE INDEX idx_permisos_rol            ON permisos(rol_id);
CREATE INDEX idx_bitacora_tabla_registro ON bitacora_auditoria(tabla_afectada, registro_id);
CREATE INDEX idx_bitacora_usuario_fecha  ON bitacora_auditoria(usuario_id, fecha_hora);
CREATE INDEX idx_tasas_tipo_fecha        ON tasas_de_cambio(tipo, fecha DESC, hora DESC);
CREATE INDEX idx_productos_categoria     ON productos(categoria_id);
CREATE INDEX idx_productos_nombre        ON productos(nombre);
CREATE INDEX idx_variantes_producto      ON variantes_productos(producto_id);
CREATE INDEX idx_unidades_producto       ON unidades_conversion(producto_id);
CREATE INDEX idx_kardex_producto_fecha   ON kardex_inventario(producto_id, fecha_hora);
CREATE INDEX idx_compras_proveedor       ON compras(proveedor_id);
CREATE INDEX idx_detalle_compras_compra  ON detalle_compras(compra_id);
CREATE INDEX idx_ventas_cliente          ON ventas(cliente_id);
CREATE INDEX idx_ventas_cajero_fecha     ON ventas(cajero_id, fecha_venta);
CREATE INDEX idx_detalle_ventas_venta    ON detalle_ventas(venta_id);
CREATE INDEX idx_detalle_ventas_producto ON detalle_ventas(producto_id);
CREATE INDEX idx_caja_fecha              ON caja(sucursal_id, fecha_hora);
CREATE INDEX idx_detalle_asientos_asiento ON detalle_asientos(asiento_id);

COMMIT;

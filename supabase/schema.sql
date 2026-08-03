-- =========================================================
-- REFUGIO DE CARACOLES — ESQUEMA DE SUPABASE
--
-- Reemplaza al backend de Google Apps Script (Code.gs).
-- Pégalo entero en el SQL Editor del proyecto de Supabase
-- (https://supabase.com/dashboard/project/_/sql/new) y
-- ejecútalo una sola vez.
--
-- Diseño: las tablas NO son accesibles directamente desde el
-- frontend (RLS activado, sin políticas). Todo el acceso pasa
-- por funciones "security definer" que validan usuario y
-- contraseña ellas mismas — el mismo rol que cumplía doPost
-- en Code.gs. La anon key es pública a propósito (así está
-- pensado Supabase); la seguridad real la dan estas funciones.
-- =========================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------

create table if not exists app_users (
  username      text primary key,
  password_hash text not null,
  created_at    timestamptz not null default now()
);

create table if not exists app_progress (
  username   text primary key references app_users(username) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

alter table app_users enable row level security;
alter table app_progress enable row level security;
-- Sin "create policy": el anon key no puede leer/escribir estas
-- tablas directamente vía REST, solo a través de las funciones.

-- ---------------------------------------------------------
-- FUNCIONES AUXILIARES
-- ---------------------------------------------------------

create or replace function default_game_state()
returns jsonb
language sql
immutable
as $$
  select '{
    "coins": 300,
    "snails": [],
    "eggs": [],
    "envelopes": [],
    "nursery": [],
    "discovered": [],
    "foods": [],
    "night": false,
    "seconds": 0,
    "feed": 0,
    "pet": 0,
    "daily": false,
    "highScores": {"food": 0, "star": 0, "snake": 0}
  }'::jsonb
$$;

create or replace function normalize_username(p_username text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_username, '')))
$$;

create or replace function is_valid_username(p_username text)
returns boolean
language sql
immutable
as $$
  select p_username ~ '^[a-z0-9_]{3,24}$'
$$;

create or replace function check_password(p_username text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
begin
  select password_hash into v_hash
    from app_users
   where username = p_username;

  if v_hash is null then
    return false;
  end if;

  return v_hash = crypt(coalesce(p_password, ''), v_hash);
end;
$$;

-- ---------------------------------------------------------
-- API PÚBLICA (equivalente a los "action" de doPost)
-- ---------------------------------------------------------

create or replace function register_user(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
begin
  if not is_valid_username(v_username) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Usuario inválido (3 a 24 letras, números o _).'
    );
  end if;

  if p_password is null or length(p_password) < 4 then
    return jsonb_build_object(
      'ok', false,
      'error', 'La contraseña debe tener al menos 4 caracteres.'
    );
  end if;

  if exists (select 1 from app_users where username = v_username) then
    return jsonb_build_object('ok', false, 'error', 'Ese usuario ya existe.');
  end if;

  insert into app_users(username, password_hash)
  values (v_username, crypt(p_password, gen_salt('bf')));

  insert into app_progress(username, data)
  values (v_username, default_game_state());

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function login_user(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
  v_data jsonb;
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  select data into v_data from app_progress where username = v_username;

  return jsonb_build_object('ok', true, 'data', coalesce(v_data, default_game_state()));
end;
$$;

create or replace function load_progress(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
  v_data jsonb;
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  select data into v_data from app_progress where username = v_username;

  return jsonb_build_object('ok', true, 'data', coalesce(v_data, default_game_state()));
end;
$$;

create or replace function save_progress(p_username text, p_password text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  insert into app_progress(username, data, updated_at)
  values (v_username, p_data, now())
  on conflict (username)
  do update set data = excluded.data, updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------
-- PERMISOS: exponer solo estas funciones vía RPC (PostgREST)
-- ---------------------------------------------------------

grant execute on function register_user(text, text)         to anon, authenticated;
grant execute on function login_user(text, text)             to anon, authenticated;
grant execute on function load_progress(text, text)          to anon, authenticated;
grant execute on function save_progress(text, text, jsonb)   to anon, authenticated;

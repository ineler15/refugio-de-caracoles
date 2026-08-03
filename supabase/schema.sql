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

-- Tablero de intercambio: "doy mi caracol snail_id (de la especie
-- give_species), quiero un caracol de la especie want_species".
-- En cuanto exista la oferta complementaria de otro usuario, el
-- intercambio se ejecuta solo (ver create_trade_offer más abajo).
create table if not exists trade_offers (
  id           uuid primary key default gen_random_uuid(),
  username     text not null references app_users(username) on delete cascade,
  snail_id     text not null,
  give_species text not null,
  want_species text not null,
  status       text not null default 'open',
  matched_with text,
  created_at   timestamptz not null default now()
);

alter table app_users enable row level security;
alter table app_progress enable row level security;
alter table trade_offers enable row level security;
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
-- INTERCAMBIOS: publicar una oferta ("doy X, quiero especie Y");
-- si ya existe (o se publica después) la oferta complementaria de
-- otro usuario, el intercambio se ejecuta solo, sin aceptar/rechazar.
-- ---------------------------------------------------------

create or replace function create_trade_offer(
  p_username text,
  p_password text,
  p_snail_id text,
  p_want_species text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
  v_my_data jsonb;
  v_my_snail jsonb;
  v_my_idx int;
  v_give_species text;
  v_match_id uuid;
  v_match_username text;
  v_match_snail_id text;
  v_other_data jsonb;
  v_other_snail jsonb;
  v_other_idx int;
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  if p_want_species is null or length(trim(p_want_species)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Elegí qué especie querés a cambio.');
  end if;

  select data into v_my_data
    from app_progress
   where username = v_username
     for update;

  select value, ordinality - 1
    into v_my_snail, v_my_idx
    from jsonb_array_elements(coalesce(v_my_data->'snails', '[]'::jsonb)) with ordinality as t(value, ordinality)
   where value->>'id' = p_snail_id
   limit 1;

  if v_my_snail is null then
    return jsonb_build_object('ok', false, 'error', 'No tenés ese caracol.');
  end if;

  v_give_species := v_my_snail->>'type';

  if v_give_species = p_want_species then
    return jsonb_build_object('ok', false, 'error', 'No podés pedir la misma especie que ofrecés.');
  end if;

  -- Buscar la oferta complementaria más vieja de OTRO usuario
  select id, username, snail_id
    into v_match_id, v_match_username, v_match_snail_id
    from trade_offers
   where status = 'open'
     and username <> v_username
     and give_species = p_want_species
     and want_species = v_give_species
   order by created_at asc
   limit 1
   for update skip locked;

  if v_match_id is not null then

    select data into v_other_data
      from app_progress
     where username = v_match_username
       for update;

    select value, ordinality - 1
      into v_other_snail, v_other_idx
      from jsonb_array_elements(coalesce(v_other_data->'snails', '[]'::jsonb)) with ordinality as t(value, ordinality)
     where value->>'id' = v_match_snail_id
     limit 1;

    if v_other_snail is null then

      -- La oferta ya no es válida (ese caracol salió por otro
      -- camino mientras tanto): la cerramos y seguimos como si
      -- no hubiera match, publicando la oferta propia más abajo.
      update trade_offers
         set status = 'cancelled'
       where id = v_match_id;

    else

      update app_progress
         set data = jsonb_set(
               v_my_data,
               '{snails}',
               ((v_my_data->'snails') - v_my_idx) || jsonb_build_array(v_other_snail)
             ),
             updated_at = now()
       where username = v_username;

      update app_progress
         set data = jsonb_set(
               v_other_data,
               '{snails}',
               ((v_other_data->'snails') - v_other_idx) || jsonb_build_array(v_my_snail)
             ),
             updated_at = now()
       where username = v_match_username;

      update trade_offers
         set status = 'matched', matched_with = v_username
       where id = v_match_id;

      return jsonb_build_object(
        'ok', true,
        'matched', true,
        'receivedSnail', v_other_snail,
        'removedSnailId', p_snail_id,
        'partner', v_match_username
      );

    end if;

  end if;

  insert into trade_offers(username, snail_id, give_species, want_species)
  values (v_username, p_snail_id, v_give_species, p_want_species);

  return jsonb_build_object('ok', true, 'matched', false);
end;
$$;

create or replace function list_trade_board(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
  v_list jsonb;
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'username', username,
        'giveSpecies', give_species,
        'wantSpecies', want_species,
        'createdAt', created_at
      )
      order by created_at asc
    ),
    '[]'::jsonb
  )
    into v_list
    from trade_offers
   where status = 'open'
     and username <> v_username;

  return jsonb_build_object('ok', true, 'data', v_list);
end;
$$;

create or replace function list_my_trade_offers(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := normalize_username(p_username);
  v_list jsonb;
begin
  if not check_password(v_username, p_password) then
    return jsonb_build_object('ok', false, 'error', 'Usuario o contraseña incorrectos.');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'giveSpecies', give_species,
        'wantSpecies', want_species,
        'createdAt', created_at
      )
      order by created_at asc
    ),
    '[]'::jsonb
  )
    into v_list
    from trade_offers
   where status = 'open'
     and username = v_username;

  return jsonb_build_object('ok', true, 'data', v_list);
end;
$$;

create or replace function cancel_trade_offer(p_username text, p_password text, p_offer_id uuid)
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

  update trade_offers
     set status = 'cancelled'
   where id = p_offer_id
     and username = v_username
     and status = 'open';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'No se pudo cancelar esa oferta.');
  end if;

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
grant execute on function create_trade_offer(text, text, text, text) to anon, authenticated;
grant execute on function list_trade_board(text, text)               to anon, authenticated;
grant execute on function list_my_trade_offers(text, text)           to anon, authenticated;
grant execute on function cancel_trade_offer(text, text, uuid)       to anon, authenticated;

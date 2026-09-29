-- Handover jobs, stored in the shared Austruss project (vrhapkrtbxcccmbnjkco).
--
-- The app has no user accounts: the drafting team shares one passcode. The
-- tables are therefore closed to the anon key entirely (RLS on, no policies,
-- privileges revoked) and every read/write goes through the handover_*
-- functions below, which check the passcode before touching anything.
--
-- Set or change the passcode from the Supabase SQL editor:
--   select private.handover_set_passcode('the new passcode');

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.handovers (
  id           uuid primary key default gen_random_uuid(),
  job_number   text,
  project_name text,
  client_name  text,
  -- The app's whole `state` object, images replaced by R2 URLs.
  data         jsonb not null,
  version      integer not null default 1,
  source       text not null default 'app' check (source in ('app', 'import')),
  -- SHA-256 of an imported session file, so importing it twice is a no-op.
  import_hash  text unique,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text,
  deleted_at   timestamptz
);
create index handovers_job_number_idx on public.handovers (job_number);

alter table public.handovers enable row level security;
revoke all on public.handovers from anon, authenticated;

create table private.handover_settings (
  id            boolean primary key default true check (id),
  passcode_hash text not null
);

create function private.handover_set_passcode(p_passcode text)
returns void language sql security definer set search_path = '' as $$
  insert into private.handover_settings (id, passcode_hash)
  values (true, extensions.crypt(p_passcode, extensions.gen_salt('bf', 10)))
  on conflict (id) do update set passcode_hash = excluded.passcode_hash;
$$;
revoke all on function private.handover_set_passcode(text) from public, anon, authenticated;

-- Raises PT401 (PostgREST turns it into HTTP 401) unless the passcode matches.
create function private.handover_require(p_passcode text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_passcode is null or not exists (
    select 1 from private.handover_settings
    where passcode_hash = extensions.crypt(p_passcode, passcode_hash)
  ) then
    perform pg_sleep(1);  -- slows down guessing
    raise exception 'Wrong passcode' using errcode = 'PT401';
  end if;
end $$;
revoke all on function private.handover_require(text) from public, anon, authenticated;

create function public.handover_check(p_passcode text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform private.handover_require(p_passcode);
  return true;
end $$;

create function public.handover_list(p_passcode text)
returns table (id uuid, job_number text, project_name text, client_name text,
               updated_at timestamptz, updated_by text, source text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.handover_require(p_passcode);
  return query
    select h.id, h.job_number, h.project_name, h.client_name, h.updated_at, h.updated_by, h.source
    from public.handovers h
    where h.deleted_at is null
    order by h.updated_at desc;
end $$;

create function public.handover_get(p_passcode text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.handovers;
begin
  perform private.handover_require(p_passcode);
  select * into r from public.handovers where id = p_id and deleted_at is null;
  if not found then raise exception 'Handover not found' using errcode = 'PT404'; end if;
  return jsonb_build_object('id', r.id, 'version', r.version, 'data', r.data,
                            'updated_at', r.updated_at, 'updated_by', r.updated_by);
end $$;

-- Creates (p_id null) or updates a handover. p_version is the version the
-- editor loaded; if someone else saved since, raises PT409 instead of
-- overwriting their work.
create function public.handover_save(p_passcode text, p_id uuid, p_version integer,
                                     p_data jsonb, p_editor text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.handovers;
begin
  perform private.handover_require(p_passcode);
  if p_id is null then
    insert into public.handovers (job_number, project_name, client_name, data, updated_by)
    values (nullif(p_data->>'jobNumber', ''), nullif(p_data->>'projectName', ''),
            nullif(p_data->>'clientName', ''), p_data, nullif(p_editor, ''))
    returning * into r;
  else
    update public.handovers set
      job_number   = nullif(p_data->>'jobNumber', ''),
      project_name = nullif(p_data->>'projectName', ''),
      client_name  = nullif(p_data->>'clientName', ''),
      data = p_data, version = version + 1,
      updated_at = now(), updated_by = nullif(p_editor, '')
    where id = p_id and deleted_at is null and version = p_version
    returning * into r;
    if not found then
      if exists (select 1 from public.handovers where id = p_id and deleted_at is null) then
        raise exception 'Someone else saved this handover since you opened it' using errcode = 'PT409';
      end if;
      raise exception 'Handover not found' using errcode = 'PT404';
    end if;
  end if;
  return jsonb_build_object('id', r.id, 'version', r.version, 'updated_at', r.updated_at);
end $$;

-- Adds an old session file. Returns created=false if that exact file was
-- imported before.
create function public.handover_import(p_passcode text, p_hash text, p_data jsonb,
                                       p_saved_at timestamptz, p_editor text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform private.handover_require(p_passcode);
  insert into public.handovers (job_number, project_name, client_name, data, source,
                                import_hash, created_at, updated_at, updated_by)
  values (nullif(p_data->>'jobNumber', ''), nullif(p_data->>'projectName', ''),
          nullif(p_data->>'clientName', ''), p_data, 'import', p_hash,
          coalesce(p_saved_at, now()), coalesce(p_saved_at, now()), nullif(p_editor, ''))
  on conflict (import_hash) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.handovers where import_hash = p_hash;
    return jsonb_build_object('id', v_id, 'created', false);
  end if;
  return jsonb_build_object('id', v_id, 'created', true);
end $$;

-- Soft delete, so a mistaken delete can be undone from the SQL editor.
create function public.handover_delete(p_passcode text, p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.handover_require(p_passcode);
  update public.handovers set deleted_at = now() where id = p_id;
end $$;

revoke all on function public.handover_check(text),
                       public.handover_list(text),
                       public.handover_get(text, uuid),
                       public.handover_save(text, uuid, integer, jsonb, text),
                       public.handover_import(text, text, jsonb, timestamptz, text),
                       public.handover_delete(text, uuid)
  from public;
grant execute on function public.handover_check(text),
                          public.handover_list(text),
                          public.handover_get(text, uuid),
                          public.handover_save(text, uuid, integer, jsonb, text),
                          public.handover_import(text, text, jsonb, timestamptz, text),
                          public.handover_delete(text, uuid)
  to anon, authenticated;

-- A&T TaskDesk database. Run this whole file once in Supabase: SQL Editor -> New query -> Run.
do $$ begin create type public.app_role as enum ('admin','management','manager','member'); exception when duplicate_object then null; end $$;

create table if not exists public.departments(
  id uuid primary key default gen_random_uuid(), name text not null unique, sort int not null default 0);

create table if not exists public.allowed_emails(
  email text primary key check (email = lower(email) and email like '%@aeontrisl.com'),
  full_name text not null default '', department_id uuid references public.departments on delete set null,
  role public.app_role not null default 'member', social boolean not null default false,
  added_by uuid, added_at timestamptz not null default now());

create table if not exists public.profiles(
  id uuid primary key references auth.users on delete cascade, email text not null unique,
  full_name text not null default '', job_title text not null default '', phone text not null default '',
  department_id uuid references public.departments on delete set null,
  role public.app_role not null default 'member', social boolean not null default false,
  active boolean not null default true, created_at timestamptz not null default now());

-- everything the desk stores (boards, tasks, requests, chat, social posts, docs, workflows and so on)
create table if not exists public.docs(
  coll text not null, id text not null, data jsonb not null default '{}',
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid(),
  primary key (coll, id));

insert into public.departments(name,sort) values
 ('HR',1),('Listings',2),('IT Support',3),('Media',4),('Marketing',5),('CRM & Website',6),('Accounts',7),('Reception',8),('Property Management',9),('Designers',10)
on conflict (name) do nothing;

-- ---------- who am I ----------
create or replace function public.my_role() returns public.app_role language sql stable security definer set search_path=public as
$$ select role from profiles where id = auth.uid() and active $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select coalesce((select role = 'admin' from profiles where id = auth.uid() and active), false) $$;

-- ---------- sign-in gate: company email AND on the access list (the first ever user becomes Admin) ----------
create or replace function public.can_sign_in(p_email text) returns boolean language sql stable security definer set search_path=public as
$$ select lower(p_email) like '%@aeontrisl.com'
     and (exists(select 1 from allowed_emails where email = lower(p_email)) or not exists(select 1 from profiles)) $$;
grant execute on function public.can_sign_in(text) to anon, authenticated;

create or replace function public.hook_before_user_created(event jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.can_sign_in(event->'user'->>'email') then return '{}'::jsonb; end if;
  return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'This email does not have access to TaskDesk. Ask your admin to add you.'));
end $$;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_before_user_created(jsonb) from authenticated, anon, public;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare a allowed_emails%rowtype; first_user boolean;
begin
  select not exists(select 1 from profiles) into first_user;
  select * into a from allowed_emails where email = lower(new.email);
  if first_user then
    insert into allowed_emails(email, role) values (lower(new.email), 'admin') on conflict (email) do update set role = 'admin';
    insert into profiles(id, email, role) values (new.id, lower(new.email), 'admin');
  elsif a.email is not null then
    insert into profiles(id, email, full_name, department_id, role, social) values (new.id, a.email, a.full_name, a.department_id, a.role, a.social);
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- the access list drives each profile; removing someone from the list switches their access off
create or replace function public.sync_allowed() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op = 'DELETE' then update profiles set active = false where email = old.email; return old; end if;
  update profiles set active = true, role = new.role, department_id = new.department_id, social = new.social,
    full_name = case when full_name = '' then new.full_name else full_name end where email = new.email;
  return new;
end $$;
drop trigger if exists allowed_sync on public.allowed_emails;
create trigger allowed_sync after insert or update or delete on public.allowed_emails for each row execute function public.sync_allowed();

-- people may edit their own name, job title and phone, nothing else
create or replace function public.guard_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.role := old.role; new.department_id := old.department_id; new.active := old.active; new.email := old.email; new.social := old.social;
  end if;
  return new;
end $$;
drop trigger if exists profile_guard on public.profiles;
create trigger profile_guard before update on public.profiles for each row execute function public.guard_profile();

create or replace function public.touch_doc() returns trigger language plpgsql as $$
begin new.updated_at := now(); new.updated_by := coalesce(auth.uid(), new.updated_by); return new; end $$;
drop trigger if exists doc_touch on public.docs;
create trigger doc_touch before insert or update on public.docs for each row execute function public.touch_doc();

-- ---------- what each role may read and change ----------
create or replace function public.doc_ok(p_coll text, d jsonb, p_write boolean) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare r public.app_role; dep text; soc boolean; mg boolean; u text := auth.uid()::text;
begin
  select role, department_id::text, social into r, dep, soc from profiles where id = auth.uid() and active;
  if r is null then return false; end if;
  mg := r in ('admin','management'); soc := coalesce(soc, false) or mg;
  if p_coll = 'tasks' then
    return mg or (r = 'manager' and d->>'dept' = dep) or d->>'ownerUid' = u or (not p_write and d->>'byUid' = u);
  elsif p_coll = 'boards' then
    return (not p_write) or mg or (r = 'manager' and d->>'dept' = dep);
  elsif p_coll = 'requests' then
    return mg or d->>'byUid' = u or d->>'assigneeUid' = u or (r = 'manager' and dep in (d->>'to', d->>'from'));
  elsif p_coll = 'msgs' then
    if p_write and d->>'byUid' is distinct from u then return false; end if;
    return d->>'conv' = 'g:general' or (coalesce(d->>'dept','') <> '' and (mg or d->>'dept' = dep)) or coalesce(d->'uids' ? u, false);
  elsif p_coll in ('branches','posts') then return soc;
  elsif p_coll = 'meta' then return (not p_write) or mg or (soc and d ? 'use');
  elsif p_coll in ('rules','agents') then return (not p_write) or mg or r = 'manager';
  elsif p_coll in ('docs','meetings') then return true;
  end if;
  return false;
end $$;

alter table public.departments enable row level security;
alter table public.allowed_emails enable row level security;
alter table public.profiles enable row level security;
alter table public.docs enable row level security;

do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' and tablename in ('departments','allowed_emails','profiles','docs')
  loop execute format('drop policy %I on public.%I', p.policyname, p.tablename); end loop; end $$;

create policy dept_read on public.departments for select to authenticated using (public.my_role() is not null);
create policy dept_admin on public.departments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy allowed_admin on public.allowed_emails for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy prof_read on public.profiles for select to authenticated using (id = auth.uid() or public.my_role() is not null);
create policy prof_edit on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
create policy doc_read on public.docs for select to authenticated using (public.doc_ok(coll, data, false));
create policy doc_add on public.docs for insert to authenticated with check (public.doc_ok(coll, data, true));
create policy doc_edit on public.docs for update to authenticated using (public.doc_ok(coll, data, true)) with check (public.doc_ok(coll, data, true));
create policy doc_del on public.docs for delete to authenticated using (public.doc_ok(coll, data, true));

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.departments, public.allowed_emails, public.profiles, public.docs to authenticated;
revoke all on public.departments, public.allowed_emails, public.profiles, public.docs from anon;

-- live updates
do $$ declare t text; begin
  foreach t in array array['docs','profiles'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t); exception when others then null; end;
  end loop; end $$;

-- artwork for social posts (public links, upload by signed-in staff only)
insert into storage.buckets(id, name, public) values ('artwork','artwork',true) on conflict (id) do nothing;
do $$ begin
  create policy artwork_upload on storage.objects for insert to authenticated with check (bucket_id = 'artwork' and public.my_role() is not null);
exception when duplicate_object then null; end $$;

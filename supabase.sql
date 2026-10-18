-- E aí? Você conhece a nossa história? — banco da dinâmica (Supabase)
-- Este arquivo documenta o que está aplicado no projeto. É seguro rodar de novo: não sobrescreve a ordem.
--
-- Regras:
--  * a ordem correta fica SÓ em secret_order (sem leitura pública) e nunca sai do banco;
--  * o anon só enxerga a view `ranking` e a coluna `name` de `guests`;
--  * só a função submit_guess grava em guesses; um palpite por nome; o palpite tem de ser uma permutação válida.

create extension if not exists unaccent with schema extensions;

create table if not exists secret_order (id int primary key default 1 check (id = 1), letters text[] not null);
alter table secret_order enable row level security;
-- Definir/trocar a ordem (as 15 letras, da foto mais antiga para a mais recente):
--   insert into secret_order (id, letters) values (1, array['...']) on conflict (id) do update set letters = excluded.letters;

create table if not exists guests (name text primary key, name_key text not null unique, created_at timestamptz not null default now());
alter table guests enable row level security;
create policy "lista publica" on guests for select to anon, authenticated using (true);
-- Adicionar convidado:  insert into guests (name, name_key) values ('Nome', lower(extensions.unaccent('Nome')));

create table if not exists app_settings (key text primary key, value text not null);
alter table app_settings enable row level security;
insert into app_settings (key, value) values ('admin_pin', '2104') on conflict (key) do nothing;
-- Trocar o PIN da área dos noivos:  update app_settings set value = '0000' where key = 'admin_pin';

create table if not exists guesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text not null unique,
  guess text[] not null,
  score int not null,
  total int not null,
  duration_ms int,
  created_at timestamptz not null default now(),
  listed boolean not null default true,
  voided boolean not null default false
);
alter table guesses enable row level security;

create or replace view ranking with (security_invoker = false) as
  select name, score, total, duration_ms, created_at, listed
  from guesses where not voided
  order by score desc, duration_ms asc nulls last, created_at asc;

revoke all on table secret_order, guesses, app_settings, guests from anon, authenticated;
grant select (name) on guests to anon, authenticated;
grant select on ranking to anon, authenticated;

create or replace function submit_guess(p_name text, p_guess text[], p_duration_ms int)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_key text := lower(unaccent(regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g')));
  v_name text := regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g');
  v_correct text[]; v_score int := 0; v_total int; v_row guesses%rowtype; v_rank int;
  v_existing boolean := false; v_listed boolean; v_listed_name text; i int;
begin
  if length(v_key) < 2 then raise exception 'nome muito curto'; end if;
  if length(v_name) > 40 then raise exception 'nome muito longo'; end if;
  if v_key !~ '[[:alnum:]]' then raise exception 'nome invalido'; end if;
  perform pg_advisory_xact_lock(hashtext(v_key));
  select letters into v_correct from secret_order where id = 1;
  if v_correct is null then raise exception 'ordem correta nao cadastrada'; end if;
  v_total := array_length(v_correct, 1);
  select * into v_row from guesses where name_key = v_key and not voided;
  if found then
    v_existing := true;
  else
    -- só nomes da tabela guests podem jogar
    select name into v_listed_name from guests g where g.name_key = v_key;
    v_listed := v_listed_name is not null;
    if not v_listed then raise exception 'nome fora da lista'; end if;
    v_name := v_listed_name;
    if (select array_agg(x order by x) from unnest(p_guess) x) is distinct from (select array_agg(x order by x) from unnest(v_correct) x)
    then raise exception 'palpite invalido'; end if;
    if (select count(*) from guesses where not voided) >= 400 then raise exception 'placar cheio'; end if;
    if p_duration_ms is null or p_duration_ms < 3000 then p_duration_ms := null; end if;
    for i in 1..v_total loop if p_guess[i] = v_correct[i] then v_score := v_score + 1; end if; end loop;
    insert into guesses (name, name_key, guess, score, total, duration_ms, listed)
    values (v_name, v_key, p_guess, v_score, v_total, p_duration_ms, v_listed) returning * into v_row;
  end if;
  select count(*) + 1 into v_rank from guesses g
  where not g.voided and (g.score > v_row.score
     or (g.score = v_row.score and coalesce(g.duration_ms, 2147483647) < coalesce(v_row.duration_ms, 2147483647))
     or (g.score = v_row.score and coalesce(g.duration_ms, 2147483647) = coalesce(v_row.duration_ms, 2147483647) and g.created_at < v_row.created_at));
  return json_build_object('score', v_row.score, 'total', v_row.total, 'rank', v_rank, 'existing', v_existing,
    'duration_ms', v_row.duration_ms, 'name', v_row.name, 'listed', v_row.listed);
end; $$;
revoke all on function submit_guess(text, text[], int) from public;
grant execute on function submit_guess(text, text[], int) to anon, authenticated;

-- Área dos noivos (5 toques no monograma A|J + PIN): libera um nome ou zera o placar (os registros ficam marcados como anulados)
create or replace function anular_palpite(p_pin text, p_name text)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare v_key text := lower(unaccent(regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g'))); n int;
begin
  if p_pin is null or p_pin <> (select value from app_settings where key = 'admin_pin') then raise exception 'PIN incorreto'; end if;
  update guesses set voided = true, name_key = name_key || '#' || id where name_key = v_key and not voided;
  get diagnostics n = row_count; return n;
end; $$;
revoke all on function anular_palpite(text, text) from public;
grant execute on function anular_palpite(text, text) to anon, authenticated;

create or replace function anular_todos(p_pin text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin is null or p_pin <> (select value from app_settings where key = 'admin_pin') then raise exception 'PIN incorreto'; end if;
  update guesses set voided = true, name_key = name_key || '#' || id where not voided;
  get diagnostics n = row_count; return n;
end; $$;
revoke all on function anular_todos(text) from public;
grant execute on function anular_todos(text) to anon, authenticated;

-- Úteis no dia:
--   select * from ranking;                           -- placar
--   select anular_todos('2104');                      -- zerar o placar
--   select anular_palpite('2104', 'Nome');            -- liberar uma pessoa para jogar de novo

-- Revelação (os noivos liberam pela área dos noivos; antes disso my_review devolve só {reveal:false})
create table if not exists photo_info (letter text primary key, legenda text not null, quando text not null);
alter table photo_info enable row level security;
revoke all on table photo_info from anon, authenticated;
-- insert into photo_info (letter, legenda, quando) values ('A', 'Legenda', '12/06/2024') on conflict (letter) do update set legenda = excluded.legenda, quando = excluded.quando;
insert into app_settings (key, value) values ('reveal', 'false') on conflict (key) do nothing;

create or replace function set_reveal(p_pin text, p_on boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_pin is null or p_pin <> (select value from app_settings where key = 'admin_pin') then raise exception 'PIN incorreto'; end if;
  update app_settings set value = case when p_on then 'true' else 'false' end where key = 'reveal';
  return p_on;
end; $$;
revoke all on function set_reveal(text, boolean) from public;
grant execute on function set_reveal(text, boolean) to anon, authenticated;

create or replace function my_review(p_name text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_on boolean := coalesce((select value = 'true' from app_settings where key = 'reveal'), false);
  v_key text := lower(unaccent(regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g')));
  v_guess text[]; v_correct text[]; v_items json;
begin
  if not v_on then return json_build_object('reveal', false); end if;
  select letters into v_correct from secret_order where id = 1;
  select guess into v_guess from guesses where name_key = v_key and not voided;
  select json_agg(json_build_object('pos', i, 'letra', v_correct[i], 'legenda', p.legenda, 'quando', p.quando,
           'minha', array_position(v_guess, v_correct[i]), 'acertou', v_guess is not null and v_guess[i] = v_correct[i]) order by i)
    into v_items from generate_subscripts(v_correct, 1) i left join photo_info p on p.letter = v_correct[i];
  return json_build_object('reveal', true, 'jogou', v_guess is not null, 'items', coalesce(v_items, '[]'::json));
end; $$;
revoke all on function my_review(text) from public;
grant execute on function my_review(text) to anon, authenticated;
--   select set_reveal('2104', true);   -- revelar / select set_reveal('2104', false); -- esconder

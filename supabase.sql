-- Pesquisa do Pastel: rode este arquivo inteiro uma vez no Supabase (SQL Editor > New query > Run).
-- A tabela fica fechada para o público: o site só consegue votar e ler a contagem
-- pelas duas funções abaixo. Os emails ficam visíveis só para você no Table Editor.

create table if not exists public.votos (
  id bigint generated always as identity primary key,
  email text not null,
  pastel text[] not null default '{}',
  refri text,
  suco text,
  criado_em timestamptz not null default now()
);

-- Um voto por email (sem diferenciar maiúsculas e minúsculas).
create unique index if not exists votos_email_unico on public.votos (lower(email));

alter table public.votos enable row level security;
revoke all on public.votos from anon, authenticated;

-- Registra um voto, conferindo email, opções válidas e limites (2 pastéis, 1 refri, 1 suco).
create or replace function public.votar(p_email text, p_pastel text[], p_refri text, p_suco text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  e text := lower(trim(p_email));
  pasteis text[] := coalesce(p_pastel, '{}');
begin
  if e is null or e !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    raise exception 'email_invalido';
  end if;
  if cardinality(pasteis) > 2 then
    raise exception 'limite_pastel';
  end if;
  if (select count(distinct x) from unnest(pasteis) x) <> cardinality(pasteis) then
    raise exception 'opcao_invalida';
  end if;
  if exists (
    select 1 from unnest(pasteis) x
    where x not in ('Carne', 'Queijo', 'Pizza', 'Frango com catupiry', 'Calabresa com queijo', 'Bauru', 'Palmito', 'Chocolate')
  ) then
    raise exception 'opcao_invalida';
  end if;
  if p_refri is not null and p_refri not in ('Coca-Cola', 'Guaraná', 'Fanta Laranja', 'Sprite') then
    raise exception 'opcao_invalida';
  end if;
  if p_suco is not null and p_suco not in ('Goiaba', 'Laranja', 'Uva', 'Manga') then
    raise exception 'opcao_invalida';
  end if;
  if cardinality(pasteis) = 0 and p_refri is null and p_suco is null then
    raise exception 'voto_vazio';
  end if;

  insert into public.votos (email, pastel, refri, suco) values (e, pasteis, p_refri, p_suco);
exception
  when unique_violation then
    raise exception 'email_ja_votou';
end;
$$;

-- Devolve só a contagem de votos por opção, nunca os emails.
create or replace function public.resultados()
returns table (grupo text, opcao text, votos bigint)
language sql
stable
security definer
set search_path = public
as $$
  select 'pastel', p, count(*) from public.votos, unnest(pastel) p group by p
  union all
  select 'refri', refri, count(*) from public.votos where refri is not null group by refri
  union all
  select 'suco', suco, count(*) from public.votos where suco is not null group by suco
  union all
  select 'total', 'total', count(*) from public.votos
$$;

revoke all on function public.votar(text, text[], text, text) from public;
revoke all on function public.resultados() from public;
grant execute on function public.votar(text, text[], text, text) to anon, authenticated;
grant execute on function public.resultados() to anon, authenticated;

-- Forja de Fichas: banco de dados do login
-- Cole tudo isto no SQL Editor do Supabase e clique em Run.

-- Tabela onde ficam as fichas. Cada ficha pertence a um usuário.
create table if not exists public.fichas (
  id        text primary key,
  user_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  data      jsonb not null,
  saved_at  timestamptz not null default now()
);

create index if not exists fichas_user_saved_idx on public.fichas (user_id, saved_at desc);

-- Libera a tabela para a API do site apenas para quem está logado
-- (necessário quando "Automatically expose new tables" está desmarcado).
revoke all on public.fichas from anon;
grant select, insert, update, delete on public.fichas to authenticated;

-- Segurança: cada pessoa só enxerga e altera as próprias fichas.
alter table public.fichas enable row level security;

drop policy if exists "ver as próprias fichas" on public.fichas;
create policy "ver as próprias fichas" on public.fichas
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "criar as próprias fichas" on public.fichas;
create policy "criar as próprias fichas" on public.fichas
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "editar as próprias fichas" on public.fichas;
create policy "editar as próprias fichas" on public.fichas
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "apagar as próprias fichas" on public.fichas;
create policy "apagar as próprias fichas" on public.fichas
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Compartilhar ficha por link e modo mestre
-- Código secreto do link. Fica vazio enquanto a ficha não é compartilhada.
alter table public.fichas add column if not exists share_id uuid unique;

-- Função pública que entrega UMA ficha compartilhada, só para quem tem o código.
-- Não existe forma de listar todas as fichas compartilhadas.
create or replace function public.ficha_compartilhada(p_share uuid)
returns table (data jsonb, saved_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select f.data, f.saved_at
  from public.fichas f
  where p_share is not null and f.share_id = p_share
  limit 1;
$$;

revoke all on function public.ficha_compartilhada(uuid) from public;
grant execute on function public.ficha_compartilhada(uuid) to anon, authenticated;

-- Campanhas na Mesa (mesmo conteúdo de supabase-campanhas.sql)

-- 1) Campanhas. O código de convite é o que o mestre passa para os jogadores.
create table if not exists public.campanhas (
  id         uuid primary key default gen_random_uuid(),
  dono       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome       text not null check (char_length(nome) between 1 and 80),
  descricao  text not null default '' check (char_length(descricao) <= 2000),
  mestre     text not null default '' check (char_length(mestre) <= 40),
  codigo     text not null unique check (codigo ~ '^[A-Z0-9]{10,16}$'),
  criada_em  timestamptz not null default now()
);

-- 2) Quem joga em cada campanha e com qual ficha.
create table if not exists public.campanha_membros (
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  ficha_id    text references public.fichas (id) on delete set null,
  apelido     text not null default '' check (char_length(apelido) <= 40),
  entrou_em   timestamptz not null default now(),
  primary key (campanha_id, user_id)
);
create index if not exists campanha_membros_user_idx on public.campanha_membros (user_id);
create index if not exists campanha_membros_ficha_idx on public.campanha_membros (ficha_id);

-- 3) Anotações do mestre (combate, criaturas próprias). Só o mestre vê.
create table if not exists public.campanha_mestre (
  campanha_id   uuid primary key references public.campanhas (id) on delete cascade,
  dados         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- 4) Itens e moedas que o mestre entrega. O jogador aceita ou recusa.
create table if not exists public.campanha_entregas (
  id           uuid primary key default gen_random_uuid(),
  campanha_id  uuid not null references public.campanhas (id) on delete cascade,
  para_user    uuid not null references auth.users (id) on delete cascade,
  item         jsonb not null,
  status       text not null default 'pendente' check (status in ('pendente','aceito','recusado')),
  criada_em    timestamptz not null default now(),
  respondida_em timestamptz
);
create index if not exists campanha_entregas_para_idx on public.campanha_entregas (para_user, status);

-- Funções de apoio. Rodam com permissão própria para as regras abaixo não
-- consultarem umas às outras em círculo.
create or replace function public.cf_dono(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.campanhas where id = c and dono = auth.uid());
$$;
create or replace function public.cf_membro(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.campanha_membros where campanha_id = c and user_id = auth.uid());
$$;
create or replace function public.cf_mestre_da_ficha(f text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.campanha_membros m join public.campanhas c on c.id = m.campanha_id
    where m.ficha_id = f and c.dono = auth.uid()
  );
$$;

-- Entrar numa campanha pelo código, escolhendo uma ficha própria.
create or replace function public.entrar_campanha(p_codigo text, p_ficha text, p_apelido text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  if auth.uid() is null then raise exception 'login necessario'; end if;
  select id into c from public.campanhas
    where codigo = upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if c is null then raise exception 'codigo invalido'; end if;
  if p_ficha is not null and not exists (select 1 from public.fichas where id = p_ficha and user_id = auth.uid()) then
    raise exception 'ficha invalida';
  end if;
  insert into public.campanha_membros (campanha_id, user_id, ficha_id, apelido)
    values (c, auth.uid(), p_ficha, left(coalesce(p_apelido, ''), 40))
    on conflict (campanha_id, user_id) do update set ficha_id = excluded.ficha_id, apelido = excluded.apelido;
  return c;
end;
$$;

revoke all on function public.cf_dono(uuid) from public;
revoke all on function public.cf_membro(uuid) from public;
revoke all on function public.cf_mestre_da_ficha(text) from public;
revoke all on function public.entrar_campanha(text, text, text) from public;
grant execute on function public.cf_dono(uuid) to authenticated;
grant execute on function public.cf_membro(uuid) to authenticated;
grant execute on function public.cf_mestre_da_ficha(text) to authenticated;
grant execute on function public.entrar_campanha(text, text, text) to authenticated;

-- Acesso pela API só para quem está logado.
revoke all on public.campanhas, public.campanha_membros, public.campanha_mestre, public.campanha_entregas from anon, authenticated;
grant select, insert, update, delete on public.campanhas to authenticated;
grant select, delete on public.campanha_membros to authenticated;
-- o jogador só troca a ficha e o apelido, nunca a campanha da linha
grant update (ficha_id, apelido) on public.campanha_membros to authenticated;
grant select, insert, update, delete on public.campanha_mestre to authenticated;
grant select, insert, delete on public.campanha_entregas to authenticated;
grant update (status, respondida_em) on public.campanha_entregas to authenticated;

alter table public.campanhas enable row level security;
alter table public.campanha_membros enable row level security;
alter table public.campanha_mestre enable row level security;
alter table public.campanha_entregas enable row level security;

-- campanhas: o mestre faz tudo; os membros só leem.
drop policy if exists "ver campanhas" on public.campanhas;
create policy "ver campanhas" on public.campanhas for select to authenticated
  using (dono = (select auth.uid()) or public.cf_membro(id));
drop policy if exists "criar campanhas" on public.campanhas;
create policy "criar campanhas" on public.campanhas for insert to authenticated
  with check (dono = (select auth.uid()));
drop policy if exists "editar campanhas" on public.campanhas;
create policy "editar campanhas" on public.campanhas for update to authenticated
  using (dono = (select auth.uid())) with check (dono = (select auth.uid()));
drop policy if exists "apagar campanhas" on public.campanhas;
create policy "apagar campanhas" on public.campanhas for delete to authenticated
  using (dono = (select auth.uid()));

-- membros: entrar só pela função entrar_campanha. O jogador troca a própria
-- ficha (só por uma ficha dele) ou sai; o mestre pode tirar alguém.
drop policy if exists "ver membros" on public.campanha_membros;
create policy "ver membros" on public.campanha_membros for select to authenticated
  using (user_id = (select auth.uid()) or public.cf_dono(campanha_id) or public.cf_membro(campanha_id));
drop policy if exists "trocar ficha" on public.campanha_membros;
create policy "trocar ficha" on public.campanha_membros for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and (ficha_id is null or exists (
    select 1 from public.fichas f where f.id = ficha_id and f.user_id = (select auth.uid()))));
drop policy if exists "sair ou tirar" on public.campanha_membros;
create policy "sair ou tirar" on public.campanha_membros for delete to authenticated
  using (user_id = (select auth.uid()) or public.cf_dono(campanha_id));

-- anotações do mestre: só o mestre.
drop policy if exists "mestre anota" on public.campanha_mestre;
create policy "mestre anota" on public.campanha_mestre for all to authenticated
  using (public.cf_dono(campanha_id)) with check (public.cf_dono(campanha_id));

-- entregas: o mestre entrega para membros; o jogador vê as dele e responde.
drop policy if exists "ver entregas" on public.campanha_entregas;
create policy "ver entregas" on public.campanha_entregas for select to authenticated
  using (para_user = (select auth.uid()) or public.cf_dono(campanha_id));
drop policy if exists "mestre entrega" on public.campanha_entregas;
create policy "mestre entrega" on public.campanha_entregas for insert to authenticated
  with check (public.cf_dono(campanha_id) and status = 'pendente' and exists (
    select 1 from public.campanha_membros m where m.campanha_id = campanha_entregas.campanha_id and m.user_id = para_user));
drop policy if exists "jogador responde" on public.campanha_entregas;
create policy "jogador responde" on public.campanha_entregas for update to authenticated
  using (para_user = (select auth.uid()) and status = 'pendente')
  with check (para_user = (select auth.uid()) and status in ('aceito','recusado'));
drop policy if exists "mestre cancela" on public.campanha_entregas;
create policy "mestre cancela" on public.campanha_entregas for delete to authenticated
  using (public.cf_dono(campanha_id));

-- fichas: o mestre pode LER (nunca alterar) as fichas ligadas às campanhas dele.
drop policy if exists "mestre vê fichas da campanha" on public.fichas;
create policy "mestre vê fichas da campanha" on public.fichas for select to authenticated
  using (public.cf_mestre_da_ficha(id));

-- Sessão ao vivo: mapas, tokens e rolagens (mesmo conteúdo de supabase-sessao.sql)

-- 1) Mapas da campanha. Só um fica "ativo" (o que os jogadores veem).
create table if not exists public.campanha_mapas (
  id          uuid primary key default gen_random_uuid(),
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  nome        text not null default '' check (char_length(nome) <= 60),
  largura     int  not null check (largura between 50 and 4000),
  altura      int  not null check (altura between 50 and 4000),
  grade       int  not null default 70 check (grade = 0 or grade between 10 and 400),
  ativo       boolean not null default false,
  criada_em   timestamptz not null default now()
);
create index if not exists campanha_mapas_camp_idx on public.campanha_mapas (campanha_id);

-- 2) A imagem de cada mapa fica separada, para não pesar nas atualizações ao vivo.
create table if not exists public.campanha_mapa_imagens (
  mapa_id     uuid primary key references public.campanha_mapas (id) on delete cascade,
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  imagem      text not null check (char_length(imagem) <= 4000000 and imagem ~ '^data:image/(jpeg|png|webp);base64,')
);

-- 3) Tokens: personagens dos jogadores e criaturas do mestre.
create table if not exists public.campanha_tokens (
  id            uuid primary key default gen_random_uuid(),
  campanha_id   uuid not null references public.campanhas (id) on delete cascade,
  mapa_id       uuid not null references public.campanha_mapas (id) on delete cascade,
  dono          uuid references auth.users (id) on delete cascade,  -- jogador que move; vazio = só o mestre
  nome          text not null default '' check (char_length(nome) <= 40),
  imagem        text not null default '' check (char_length(imagem) <= 200000 and (imagem = '' or imagem ~ '^data:image/(jpeg|png|webp);base64,')),
  cor           text not null default '#c1121f' check (cor ~ '^#[0-9a-fA-F]{6}$'),
  tamanho       real not null default 1 check (tamanho between 0.5 and 4),
  x             real not null default 0 check (x between -1000 and 5000),
  y             real not null default 0 check (y between -1000 and 5000),
  oculto        boolean not null default false,
  atualizado_em timestamptz not null default now()
);
create index if not exists campanha_tokens_camp_idx on public.campanha_tokens (campanha_id);
-- cada jogador tem um token por mapa
create unique index if not exists campanha_tokens_um_por_jogador on public.campanha_tokens (mapa_id, dono) where dono is not null;

-- 4) Rolagens da mesa (o feed que todo mundo vê).
create table if not exists public.campanha_rolagens (
  id          bigint generated always as identity primary key,
  campanha_id uuid not null references public.campanhas (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  autor       text not null check (char_length(autor) between 1 and 60),
  rotulo      text not null check (char_length(rotulo) <= 120),
  total       int  not null check (total between -100 and 100000),
  nat         int  check (nat between 1 and 20),
  detalhe     text not null default '' check (char_length(detalhe) <= 300),
  tipo        text not null default 'd20' check (tipo in ('d20','dano')),
  secreta     boolean not null default false,
  criada_em   timestamptz not null default now()
);
create index if not exists campanha_rolagens_camp_idx on public.campanha_rolagens (campanha_id, id desc);

-- guarda só as 200 rolagens mais recentes de cada campanha
create or replace function public.cf_limpa_rolagens() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.campanha_rolagens
   where campanha_id = new.campanha_id
     and id < (select id from public.campanha_rolagens where campanha_id = new.campanha_id order by id desc offset 199 limit 1);
  return null;
end;
$$;
revoke all on function public.cf_limpa_rolagens() from public;
drop trigger if exists limpa_rolagens on public.campanha_rolagens;
create trigger limpa_rolagens after insert on public.campanha_rolagens
  for each row execute function public.cf_limpa_rolagens();

-- mapa ativo visível para um membro
create or replace function public.cf_mapa_visivel(m uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.campanha_mapas p
    join public.campanha_membros b on b.campanha_id = p.campanha_id and b.user_id = auth.uid()
    where p.id = m and p.ativo
  );
$$;
revoke all on function public.cf_mapa_visivel(uuid) from public;
grant execute on function public.cf_mapa_visivel(uuid) to authenticated;

-- Acesso pela API só para quem está logado, com as colunas certas.
revoke all on public.campanha_mapas, public.campanha_mapa_imagens, public.campanha_tokens, public.campanha_rolagens from anon, authenticated;
grant select, insert, update, delete on public.campanha_mapas to authenticated;
grant select, insert, update, delete on public.campanha_mapa_imagens to authenticated;
grant select, insert, delete on public.campanha_tokens to authenticated;
grant update (nome, imagem, cor, tamanho, x, y, oculto, atualizado_em) on public.campanha_tokens to authenticated;
grant select, insert, delete on public.campanha_rolagens to authenticated;

alter table public.campanha_mapas enable row level security;
alter table public.campanha_mapa_imagens enable row level security;
alter table public.campanha_tokens enable row level security;
alter table public.campanha_rolagens enable row level security;

-- mapas: o mestre faz tudo; os jogadores só veem o mapa ativo.
drop policy if exists "ver mapas" on public.campanha_mapas;
create policy "ver mapas" on public.campanha_mapas for select to authenticated
  using (public.cf_dono(campanha_id) or (ativo and public.cf_membro(campanha_id)));
drop policy if exists "mestre mexe nos mapas" on public.campanha_mapas;
create policy "mestre mexe nos mapas" on public.campanha_mapas for all to authenticated
  using (public.cf_dono(campanha_id)) with check (public.cf_dono(campanha_id));

drop policy if exists "ver imagem do mapa" on public.campanha_mapa_imagens;
create policy "ver imagem do mapa" on public.campanha_mapa_imagens for select to authenticated
  using (public.cf_dono(campanha_id) or public.cf_mapa_visivel(mapa_id));
drop policy if exists "mestre envia imagem" on public.campanha_mapa_imagens;
create policy "mestre envia imagem" on public.campanha_mapa_imagens for all to authenticated
  using (public.cf_dono(campanha_id))
  with check (public.cf_dono(campanha_id) and exists (
    select 1 from public.campanha_mapas p where p.id = mapa_id and p.campanha_id = campanha_mapa_imagens.campanha_id));

-- tokens: o jogador vê os tokens visíveis do mapa ativo e move só o dele; o mestre faz tudo.
drop policy if exists "ver tokens" on public.campanha_tokens;
create policy "ver tokens" on public.campanha_tokens for select to authenticated
  using (public.cf_dono(campanha_id) or (not oculto and public.cf_mapa_visivel(mapa_id)) or dono = (select auth.uid()));
drop policy if exists "criar tokens" on public.campanha_tokens;
create policy "criar tokens" on public.campanha_tokens for insert to authenticated
  with check (
    exists (select 1 from public.campanha_mapas p where p.id = mapa_id and p.campanha_id = campanha_tokens.campanha_id)
    and (public.cf_dono(campanha_id)
      or (dono = (select auth.uid()) and not oculto and public.cf_mapa_visivel(mapa_id))));
drop policy if exists "mover tokens" on public.campanha_tokens;
create policy "mover tokens" on public.campanha_tokens for update to authenticated
  using (public.cf_dono(campanha_id) or dono = (select auth.uid()))
  with check (public.cf_dono(campanha_id) or dono = (select auth.uid()));
drop policy if exists "tirar tokens" on public.campanha_tokens;
create policy "tirar tokens" on public.campanha_tokens for delete to authenticated
  using (public.cf_dono(campanha_id) or dono = (select auth.uid()));

-- rolagens: quem está na campanha publica e vê; as secretas só o mestre e o autor veem.
drop policy if exists "ver rolagens" on public.campanha_rolagens;
create policy "ver rolagens" on public.campanha_rolagens for select to authenticated
  using (public.cf_dono(campanha_id) or user_id = (select auth.uid()) or (not secreta and public.cf_membro(campanha_id)));
drop policy if exists "rolar" on public.campanha_rolagens;
create policy "rolar" on public.campanha_rolagens for insert to authenticated
  with check (user_id = (select auth.uid()) and (public.cf_dono(campanha_id) or public.cf_membro(campanha_id)));
drop policy if exists "limpar rolagens" on public.campanha_rolagens;
create policy "limpar rolagens" on public.campanha_rolagens for delete to authenticated
  using (public.cf_dono(campanha_id));

-- Tempo real: avisa quem está na sessão quando algo muda.
-- (A imagem do mapa não entra: ela é baixada uma vez só.)
alter table public.campanha_tokens replica identity full;
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['campanha_mapas','campanha_tokens','campanha_rolagens','campanha_entregas'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end;
$$;

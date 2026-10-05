-- ══════════════════════════════════════════════════════════════════════
-- 碎碎念 · 日记分享动态 —— Supabase 建表脚本
--
-- 用法：Supabase Dashboard → SQL Editor → 新建查询 → 整段粘贴 → Run
-- 执行完重启 App，日记模块会自动从「本机」切到「云端」。
--
-- 不执行也能用：App 启动时会探测这张表，探测失败就安静地退回本机模式，
-- 动态只存在这台手机上（发布卡片底部会写「先存在这台手机上」）。
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. 动态表 ─────────────────────────────────────────────────────────
create table if not exists public.diary_posts (
  id          bigint generated always as identity primary key,
  device_id   text        not null,               -- 设备号，充当匿名身份
  author_name text        not null default '',    -- 用户自定义昵称，可空
  anonymous   boolean     not null default false, -- 勾了匿名就不显示昵称
  content     text        not null default '',
  images      jsonb       not null default '[]'::jsonb,
  mood        text        not null default '',    -- 心情标签文案，空串表示没选
  created_at  timestamptz not null default now()
);

-- ★ 后加的字段：用 add column if not exists，这样已经建过表的直接重跑这段就行
alter table public.diary_posts
  add column if not exists title    text not null default '';
alter table public.diary_posts
  add column if not exists location text not null default '';

create index if not exists diary_posts_created_at_idx
  on public.diary_posts (created_at desc);

-- ── 1b. 评论表 ────────────────────────────────────────────────────────
-- 故意不做 comment_count 反范式计数：评论单条很小，客户端全量拉下来自己数，
-- 永远和列表一致，也不需要触发器。
create table if not exists public.diary_comments (
  id          bigint generated always as identity primary key,
  post_id     bigint      not null
              references public.diary_posts (id) on delete cascade,
  device_id   text        not null,
  author_name text        not null default '',
  anonymous   boolean     not null default false,
  content     text        not null,
  created_at  timestamptz not null default now()
);

create index if not exists diary_comments_post_idx
  on public.diary_comments (post_id, created_at);

-- ── 1c. 表情反应表 ────────────────────────────────────────────────────
-- 固定四个表情，一个人对一条动态的同一个表情只能有一条记录。
-- 靠下面的唯一约束防重复，重复点不会把计数刷上去。
-- 不加主键 id：三列本身就是唯一键。
create table if not exists public.diary_reactions (
  post_id    bigint      not null
             references public.diary_posts (id) on delete cascade,
  device_id  text        not null,
  emoji      text        not null,
  created_at timestamptz not null default now(),
  constraint diary_reactions_unique unique (post_id, device_id, emoji)
);

create index if not exists diary_reactions_post_idx
  on public.diary_reactions (post_id);

-- ── 2. RLS ────────────────────────────────────────────────────────────
-- 注意：本 App 没有登录体系（「无需注册」正是产品前提），
-- 所以这里的策略是「人人可读、人人可写、人人可删」。
-- 也就是说，拿到 anon key 的人理论上能删掉别人的动态。
-- 对一个小圈子里的公开留言板够用；要更严格的话见文件末尾的说明。
alter table public.diary_posts enable row level security;

drop policy if exists diary_posts_read   on public.diary_posts;
drop policy if exists diary_posts_insert on public.diary_posts;
drop policy if exists diary_posts_delete on public.diary_posts;

create policy diary_posts_read
  on public.diary_posts for select using (true);

create policy diary_posts_insert
  on public.diary_posts for insert with check (true);

create policy diary_posts_delete
  on public.diary_posts for delete using (true);

-- 评论同样是公开留言板：人人可读、人人可写
alter table public.diary_comments enable row level security;

drop policy if exists diary_comments_read   on public.diary_comments;
drop policy if exists diary_comments_insert on public.diary_comments;
drop policy if exists diary_comments_delete on public.diary_comments;

create policy diary_comments_read
  on public.diary_comments for select using (true);

create policy diary_comments_insert
  on public.diary_comments for insert with check (true);

create policy diary_comments_delete
  on public.diary_comments for delete using (true);

-- 反应同样是公开留言板：人人可读、人人可写、人人可删
alter table public.diary_reactions enable row level security;

drop policy if exists diary_reactions_read   on public.diary_reactions;
drop policy if exists diary_reactions_insert on public.diary_reactions;
drop policy if exists diary_reactions_delete on public.diary_reactions;

create policy diary_reactions_read
  on public.diary_reactions for select using (true);

create policy diary_reactions_insert
  on public.diary_reactions for insert with check (true);

-- upsert 需要 update 权限，否则重复点会报错
drop policy if exists diary_reactions_update on public.diary_reactions;
create policy diary_reactions_update
  on public.diary_reactions for update using (true) with check (true);

create policy diary_reactions_delete
  on public.diary_reactions for delete using (true);

-- ── 3. 实时推送（可选）───────────────────────────────────────────────
-- 加上之后别人发的新动态会立刻出现。不加也不影响使用。
do $$
begin
  alter publication supabase_realtime add table public.diary_posts;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.diary_comments;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.diary_reactions;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- ── 4. 图片存储桶 ─────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('diary_images', 'diary_images', true)
on conflict (id) do update set public = true;

drop policy if exists diary_images_read  on storage.objects;
drop policy if exists diary_images_write on storage.objects;

create policy diary_images_read
  on storage.objects for select
  using (bucket_id = 'diary_images');

create policy diary_images_write
  on storage.objects for insert
  with check (bucket_id = 'diary_images');

-- ══════════════════════════════════════════════════════════════════════
-- 自检
-- ══════════════════════════════════════════════════════════════════════
-- select count(*) from public.diary_posts;
-- select id, device_id, author_name, anonymous, mood, created_at
--   from public.diary_posts order by created_at desc limit 20;

-- ══════════════════════════════════════════════════════════════════════
-- 想把权限收紧一些？
-- ══════════════════════════════════════════════════════════════════════
-- 客户端那侧的逻辑是「只有自己的卡片长按才给删」，云端并没有强制。
-- 若要真正防住越权删除，推荐把它改成软删除 + RPC：
--
--   alter table public.diary_posts add column deleted_at timestamptz;
--
--   create or replace function public.diary_soft_delete(p_id bigint, p_device text)
--   returns void language sql security definer as $$
--     update public.diary_posts
--        set deleted_at = now()
--      where id = p_id and device_id = p_device;
--   $$;
--
--   drop policy diary_posts_delete on public.diary_posts;
--   create policy diary_posts_read on public.diary_posts
--     for select using (deleted_at is null);
--
-- 然后调用 public.diary_soft_delete(id, device_id)。
-- device_id 仍然是客户端传的、可以伪造，所以这只是提高了门槛，
-- 不是密码学意义上的鉴权 —— 要做到那一步就必须引入登录。

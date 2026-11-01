-- ============================================================
-- CampusCanteen — Supabase schema
-- Run this whole file in the Supabase SQL editor.
-- ============================================================

-- ---------- TABLES ----------

-- User profiles (one row per auth user)
-- role: student       — customer (the default for every sign-up)
--       college_staff — teacher; also a customer (picked at sign-up)
--       canteen_staff — runs the canteen; added manually in Supabase
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null default '',
  email       text not null,
  roll_number text not null default '',
  role        text not null default 'student'
    check (role in ('student', 'college_staff', 'canteen_staff')),
  created_at  timestamptz not null default now()
);

-- For databases created before this three-role split: widen the existing
-- constraint so college_staff/canteen_staff are accepted.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('student', 'college_staff', 'canteen_staff'));

-- Menu items
create table if not exists public.menu_items (
  id                       uuid primary key default gen_random_uuid(),
  name                     text not null,
  description              text not null default '',
  price                    numeric(10, 2) not null,
  category                 text not null check (category in ('breakfast', 'lunch', 'snacks', 'drinks')),
  image_url                text not null default '',
  is_available             boolean not null default true,
  preparation_time_minutes int not null default 10,
  created_at               timestamptz not null default now()
);

-- Orders
create table if not exists public.orders (
  id             uuid primary key default gen_random_uuid(),
  order_number   text not null unique,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  status         text not null default 'paidPendingApproval' check (status in ('paidPendingApproval', 'preparing', 'readyForPickup', 'completed', 'cancelled')),
  total_amount   numeric(10, 2) not null,
  pickup_start   timestamptz not null,
  pickup_end     timestamptz not null,
  transaction_id text,
  created_at     timestamptz not null default now()
);

create index if not exists orders_user_idx   on public.orders (user_id);
create index if not exists orders_status_idx on public.orders (status);
create index if not exists orders_pickup_idx on public.orders (pickup_start);

-- Order line items
create table if not exists public.order_items (
  id             bigint generated always as identity primary key,
  order_id       uuid not null references public.orders (id) on delete cascade,
  menu_item_id   uuid references public.menu_items (id),
  menu_item_name text not null,
  quantity       int not null check (quantity > 0),
  unit_price     numeric(10, 2) not null
);

create index if not exists order_items_order_idx on public.order_items (order_id);

-- Notifications
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null,
  body       text not null default '',
  type       text not null default 'general',
  order_id   uuid references public.orders (id) on delete set null,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx on public.notifications (user_id, is_read);

-- ---------- WALLET ----------

-- One wallet per user. balance can never go below 0: checkout refuses first.
create table if not exists public.wallets (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  balance    numeric(10, 2) not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

-- Immutable ledger: every balance change writes exactly one row.
-- amount > 0 = money in (topup / refund), amount < 0 = money out (order payment).
create table if not exists public.wallet_transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  amount        numeric(10, 2) not null,
  type          text not null check (type in ('topup', 'order_payment', 'refund')),
  order_id      uuid references public.orders (id) on delete set null,
  balance_after numeric(10, 2) not null,
  description   text not null default '',
  created_at    timestamptz not null default now()
);

create index if not exists wallet_transactions_user_idx on public.wallet_transactions (user_id, created_at desc);
create index if not exists wallet_transactions_order_idx on public.wallet_transactions (order_id);

-- The canteen's own balance (singleton row). Every wallet-paid order credits
-- it; cancelling an order debits it back; payouts move money to the owner's
-- real bank account. Can go negative only in the rare case where a payout was
-- already taken and the order is then cancelled (the owner ate the refund).
create table if not exists public.canteen_wallet (
  id         int primary key default 1 check (id = 1),
  balance    numeric(12, 2) not null default 0,
  updated_at timestamptz not null default now()
);

-- History of "I transferred the canteen balance to my bank" events.
create table if not exists public.canteen_payouts (
  id         uuid primary key default gen_random_uuid(),
  amount     numeric(10, 2) not null check (amount > 0),
  note       text not null default '',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists canteen_payouts_idx on public.canteen_payouts (created_at desc);

-- Backfill: accounts that existed before this schema was added still need a
-- wallet row (new signups get one from the handle_new_user trigger), and the
-- canteen singleton should exist from the start.
insert into public.wallets (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

insert into public.canteen_wallet (id) values (1)
on conflict (id) do nothing;

-- Provision the canteen staff account (auth user must already exist in
-- Supabase Auth with this UID, created via Dashboard or signup).
insert into public.profiles (id, name, email, roll_number, role)
values (
  '82a06085-ae9e-4e3c-ac55-fc95dbc7f9a5',
  'Canteen Staff',
  'canteen.staff@college.edu',
  '',
  'canteen_staff'
)
on conflict (id) do update set role = 'canteen_staff';

insert into public.wallets (user_id)
values ('82a06085-ae9e-4e3c-ac55-fc95dbc7f9a5')
on conflict (user_id) do nothing;

-- ---------- HELPER FUNCTIONS ----------

-- Whether the current user has management powers (see all orders, update
-- statuses, read balances). Teachers (college_staff) are customers and get
-- no powers, so this means canteen_staff only. Kept as a separate function
-- from is_canteen_staff() purely so existing policies keep working.
create or replace function public.is_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'canteen_staff'
  );
$$;

-- Whether the current user is canteen staff (only they can manage the menu)
create or replace function public.is_canteen_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'canteen_staff'
  );
$$;

-- Auto-create profile row when a user signs up (via Supabase Auth)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, email, roll_number, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'roll_number', ''),
    -- The client may only ever request the harmless college_staff (teacher)
    -- label, which grants no powers. 'canteen_staff' is deliberately ignored
    -- so nobody can self-register into management: canteen staff are added by
    -- an admin directly in the profiles table.
    case
      when coalesce(new.raw_user_meta_data ->> 'role', 'student') = 'college_staff'
        then 'college_staff'
      else 'student'
    end
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- ORDER DETAILS VIEW ----------

-- security_invoker = true (Postgres 15+) makes the view run its query as the
-- calling user instead of the view owner, so the RLS policies on orders and
-- order_items below decide what each user can read. Without it the view is
-- SECURITY DEFINER and the Supabase linter (security_definer_view) flags it.
create or replace view public.order_details
with (security_invoker = true)
as
select
  o.id,
  o.order_number,
  o.user_id,
  o.status,
  o.total_amount,
  o.created_at,
  o.pickup_start as pickup_start_time,
  o.pickup_end   as pickup_end_time,
  o.transaction_id,
  coalesce(jsonb_agg(
    jsonb_build_object(
      'menuItemId',   oi.menu_item_id::text,
      'menuItemName', oi.menu_item_name,
      'quantity',     oi.quantity,
      'unitPrice',    to_char(oi.unit_price, 'FM999999999.99')::numeric
    ) order by oi.id
  ) filter (where oi.id is not null), '[]'::jsonb) as items
from public.orders o
left join public.order_items oi on oi.order_id = o.id
group by o.id;

-- Re-applying this to an already-deployed database switches the existing view
-- over to security_invoker (CREATE OR REPLACE is enough, this is just explicit).
alter view public.order_details set (security_invoker = true);

-- A security_invoker view checks privileges as the caller, so the PostgREST
-- roles need SELECT on the underlying tables. RLS still filters the rows.
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;
grant select on public.order_details to authenticated;

-- ---------- RPC: place an order ----------

create or replace function public.place_order(
  p_items           jsonb,
  p_transaction_id  text,
  p_pickup_start    timestamptz,
  p_pickup_end      timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_order_id   uuid;
  v_item       jsonb;
  v_menu       record;
  v_total      numeric := 0;
  v_count      int;
  v_order_no   text;
  v_staff      record;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- ---------- Input validation ----------
  -- The client can be bypassed entirely (PostgREST + anon key), so every
  -- assumption the app makes must be re-checked here.

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Order items must be an array';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  if p_pickup_start is null or p_pickup_end is null then
    raise exception 'Pickup time slot is required';
  end if;

  -- Slots are 30 minutes; without this a caller could pair a real slot start
  -- with a custom end time and land in a different slot-capacity bucket.
  if p_pickup_end <> p_pickup_start + interval '30 minutes' then
    raise exception 'Pickup slot must be exactly 30 minutes';
  end if;

  -- Align to :00 / :30. Capacity is counted on the exact timestamp pair, so
  -- unaligned timestamps would bypass the 30-orders-per-slot limit.
  if date_trunc('hour', p_pickup_start) <> p_pickup_start
     and date_trunc('hour', p_pickup_start) + interval '30 minutes' <> p_pickup_start then
    raise exception 'Pickup slot must start on the hour or half hour';
  end if;

  -- Opening hours 08:00-20:00 (start hour 8..19, end at most 20:00).
  if extract(hour from p_pickup_start) < 8
     or extract(hour from p_pickup_start) >= 20 then
    raise exception 'Pickup slot is outside opening hours (8 AM - 8 PM)';
  end if;

  -- Bounds on the booking window. The app sends local wall-clock times with
  -- no UTC offset, so these use generous tolerances instead of a strict
  -- now() comparison (a strict check would reject valid slots for users in
  -- negative UTC offsets). Max offset is +/-14h, well inside 1 day / 7 days.
  if p_pickup_start < now() - interval '1 day' then
    raise exception 'Pickup time cannot be in the past';
  end if;
  if p_pickup_start > now() + interval '7 days' then
    raise exception 'Pickups can only be booked up to 7 days ahead';
  end if;

  -- Serialise slot booking so two concurrent bookings can't overshoot capacity
  perform pg_advisory_xact_lock(hashtext('canteen_slot:' || p_pickup_start::text || ':' || p_pickup_end::text));

  select count(*) into v_count
  from public.orders
  where pickup_start = p_pickup_start
    and pickup_end   = p_pickup_end
    and status      <> 'cancelled';

  if v_count >= 30 then
    raise exception 'This time slot is full. Please choose another.';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    if v_item ->> 'menuItemId' is null
       or v_item ->> 'menuItemId' !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Invalid menu item';
    end if;
    if v_item ->> 'quantity' is null
       or v_item ->> 'quantity' !~ '^[0-9]{1,4}$' then
      raise exception 'Invalid quantity';
    end if;
    if (v_item ->> 'quantity')::int < 1 then
      raise exception 'Quantity must be at least 1';
    end if;
    if (v_item ->> 'quantity')::int > 20 then
      raise exception 'Quantity cannot exceed 20 per item';
    end if;

    select id, name, price, is_available
      into v_menu
      from public.menu_items
      where id = (v_item ->> 'menuItemId')::uuid;

    if v_menu.id is null then
      raise exception 'Item not found on the menu';
    end if;
    if not v_menu.is_available then
      raise exception '% is no longer available', v_menu.name;
    end if;

    v_total := v_total + ((v_item ->> 'quantity')::int * v_menu.price);
  end loop;

  v_order_no := 'ORD-' || upper(substr(md5(random()::text), 1, 6));

  insert into public.orders (order_number, user_id, status, total_amount, pickup_start, pickup_end, transaction_id)
  values (v_order_no, v_user_id, 'paidPendingApproval', v_total, p_pickup_start, p_pickup_end, p_transaction_id)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select name, price into v_menu from public.menu_items where id = (v_item ->> 'menuItemId')::uuid;
    insert into public.order_items (order_id, menu_item_id, menu_item_name, quantity, unit_price)
    values (v_order_id, (v_item ->> 'menuItemId')::uuid, v_menu.name, (v_item ->> 'quantity')::int, v_menu.price);
  end loop;

  -- Notify the student
  insert into public.notifications (user_id, title, body, type, order_id)
  values (v_user_id, 'Order placed successfully',
          'Your order ' || v_order_no || ' has been placed and is awaiting approval.', 'order_placed', v_order_id);

  -- Notify the canteen team (teachers are customers, not approvers)
  for v_staff in select id from public.profiles where role = 'canteen_staff'
  loop
    insert into public.notifications (user_id, title, body, type, order_id)
    values (v_staff.id, 'New order received',
            'New order ' || v_order_no || ' is waiting for approval.', 'new_order', v_order_id);
  end loop;

  return (select to_jsonb(od) from public.order_details od where od.id = v_order_id);
end;
$$;

-- place_order on its own would let any client create an order WITHOUT paying.
-- It stays as the building block of place_order_from_wallet below, but is no
-- longer callable from PostgREST (the owner keeps its implicit EXECUTE right).
revoke execute on function public.place_order(jsonb, text, timestamptz, timestamptz)
  from public;

-- ---------- RPC: place an order, paid from the wallet ----------

-- Everything runs in ONE transaction: the order (with all of place_order's
-- validation) is created first, then the wallet debit and the canteen credit
-- are applied. Any failure — including "insufficient balance" — rolls the
-- whole thing back, so an order can never exist unpaid.
create or replace function public.place_order_from_wallet(
  p_items        jsonb,
  p_pickup_start timestamptz,
  p_pickup_end   timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id   uuid := auth.uid();
  v_order     jsonb;
  v_order_id  uuid;
  v_order_no  text;
  v_total     numeric;
  v_balance   numeric;
  v_txn_id    uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  v_order := public.place_order(p_items, null, p_pickup_start, p_pickup_end);
  v_order_id := (v_order ->> 'id')::uuid;
  v_order_no := v_order ->> 'order_number';
  v_total    := (v_order ->> 'total_amount')::numeric;

  -- Row lock serialises concurrent checkouts so two orders can't both pass
  -- on the same last rupee.
  select balance into v_balance
  from public.wallets
  where user_id = v_user_id
  for update;

  if v_balance is null or v_balance < v_total then
    raise exception 'Insufficient wallet balance. Please add money to your wallet.';
  end if;

  update public.wallets
  set balance = balance - v_total, updated_at = now()
  where user_id = v_user_id
  returning balance into v_balance;

  insert into public.wallet_transactions (user_id, amount, type, order_id, balance_after, description)
  values (v_user_id, -v_total, 'order_payment', v_order_id, v_balance,
          'Paid for order ' || v_order_no)
  returning id into v_txn_id;

  update public.orders
  set transaction_id = 'WALLET-' || v_txn_id
  where id = v_order_id;

  -- The money leaves the student's wallet and lands with the canteen.
  insert into public.canteen_wallet (id, balance)
  values (1, v_total)
  on conflict (id)
  do update set balance = public.canteen_wallet.balance + v_total, updated_at = now();

  return (select to_jsonb(od) from public.order_details od where od.id = v_order_id);
end;
$$;

-- ---------- RPC: top up the wallet ----------

-- Simulated top-up (no payment gateway is wired up yet): the amount is
-- credited instantly. Validation + a per-hour cap keep scripted clients from
-- flooding the ledger. Swap the body for a real gateway charge later without
-- touching any other code.
create or replace function public.add_wallet_funds(
  p_amount numeric,
  p_method text default 'simulated'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_new_balance numeric;
  v_recent     int;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  if p_amount is null or p_amount < 1 then
    raise exception 'Minimum top-up is ₹1';
  end if;
  if p_amount > 5000 then
    raise exception 'Maximum top-up is ₹5000 at a time';
  end if;
  if p_amount <> round(p_amount, 2) then
    raise exception 'Invalid amount';
  end if;

  select count(*) into v_recent
  from public.wallet_transactions
  where user_id = v_user
    and type = 'topup'
    and created_at > now() - interval '1 hour';

  if v_recent >= 10 then
    raise exception 'Top-up limit reached for this hour. Try again later.';
  end if;

  insert into public.wallets (user_id, balance)
  values (v_user, p_amount)
  on conflict (user_id)
  do update set balance = public.wallets.balance + p_amount, updated_at = now()
  returning balance into v_new_balance;

  insert into public.wallet_transactions (user_id, amount, type, balance_after, description)
  values (v_user, p_amount, 'topup', v_new_balance,
          'Added via ' || coalesce(p_method, 'simulated'));

  return jsonb_build_object('balance', v_new_balance);
end;
$$;

-- ---------- RPC: canteen payout ----------

-- The owner records "I moved the balance to my real bank". Only canteen
-- staff may do this, and only up to what the canteen actually holds.
create or replace function public.canteen_payout(
  p_amount numeric,
  p_note   text default ''
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance numeric;
begin
  if not public.is_canteen_staff() then
    raise exception 'Only canteen staff can record payouts';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter a valid payout amount';
  end if;
  if p_amount > 100000 then
    raise exception 'Payout amount is too large';
  end if;
  if p_amount <> round(p_amount, 2) then
    raise exception 'Invalid amount';
  end if;

  insert into public.canteen_wallet (id, balance) values (1, 0)
  on conflict (id) do nothing;

  update public.canteen_wallet
  set balance = balance - p_amount, updated_at = now()
  where id = 1 and balance >= p_amount
  returning balance into v_balance;

  if v_balance is null then
    raise exception 'Payout exceeds the available canteen balance';
  end if;

  insert into public.canteen_payouts (amount, note, created_by)
  values (p_amount, coalesce(p_note, ''), auth.uid());

  return jsonb_build_object('balance', v_balance);
end;
$$;

-- ---------- RPC: update order status ----------

create or replace function public.update_order_status(
  p_order_id  uuid,
  p_new_status text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_prev text;
  v_user_id uuid;
  v_order_no text;
  v_title text;
  v_body text;
  v_type text;
  v_refund numeric;
  v_new_balance numeric;
  v_refunded boolean := false;
begin
  if not public.is_staff() then
    raise exception 'Only staff can update order status';
  end if;

  if p_new_status not in ('paidPendingApproval', 'preparing', 'readyForPickup', 'completed', 'cancelled') then
    raise exception 'Invalid status';
  end if;

  select status, order_number, user_id into v_prev, v_order_no, v_user_id
  from public.orders where id = p_order_id;

  if v_prev is null then
    raise exception 'Order not found';
  end if;

  if v_prev = p_new_status then
    return (select to_jsonb(od) from public.order_details od where od.id = p_order_id);
  end if;

  update public.orders set status = p_new_status where id = p_order_id;

  case p_new_status
    when 'preparing' then
      v_title := 'Order accepted'; v_body := 'Your order ' || v_order_no || ' is now being prepared.'; v_type := 'order_status';
    when 'readyForPickup' then
      v_title := 'Ready for pickup'; v_body := 'Your order ' || v_order_no || ' is ready. Please collect it from the counter.'; v_type := 'order_status';
    when 'completed' then
      v_title := 'Order completed'; v_body := 'Your order ' || v_order_no || ' has been collected. Enjoy your meal!'; v_type := 'order_status';
    when 'cancelled' then
      v_title := 'Order cancelled'; v_type := 'order_status';

      -- Send the money back: student wallet +, canteen balance -.
      -- Exactly one order_payment row can exist per order, and cancelled is a
      -- terminal status, so this refund can never run twice.
      select amount into v_refund
      from public.wallet_transactions
      where order_id = p_order_id and type = 'order_payment'
      limit 1;

      if v_refund is not null then
        update public.wallets
        set balance = balance + v_refund, updated_at = now()
        where user_id = v_user_id
        returning balance into v_new_balance;

        insert into public.wallet_transactions (user_id, amount, type, order_id, balance_after, description)
        values (v_user_id, v_refund, 'refund', p_order_id, v_new_balance,
                'Refund for cancelled order ' || v_order_no);

        update public.canteen_wallet
        set balance = balance - v_refund, updated_at = now()
        where id = 1;

        v_refunded := true;
      end if;

      if v_refunded then
        v_body := 'Your order ' || v_order_no || ' was cancelled. ₹'
                  || to_char(v_refund, 'FM999999990.99')
                  || ' has been refunded to your wallet.';
      else
        v_body := 'Your order ' || v_order_no || ' was cancelled.';
      end if;
    else
      v_title := 'Order updated'; v_body := 'Your order ' || v_order_no || ' status changed.'; v_type := 'order_status';
  end case;

  insert into public.notifications (user_id, title, body, type, order_id)
  values (v_user_id, v_title, v_body, v_type, p_order_id);

  return (select to_jsonb(od) from public.order_details od where od.id = p_order_id);
end;
$$;

-- ---------- ORDER STATUS STATE MACHINE ----------
-- Enforced in a trigger (not only inside update_order_status) so the rules
-- hold for every path, including a direct UPDATE that bypasses the RPC.

create or replace function public.enforce_order_status_transition()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'paidPendingApproval' and new.status in ('preparing', 'cancelled'))
    or (old.status = 'preparing'         and new.status in ('readyForPickup', 'cancelled'))
    or (old.status = 'readyForPickup'    and new.status in ('completed', 'cancelled'))
  ) then
    raise exception 'Cannot change order status from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_order_status_transition on public.orders;
create trigger enforce_order_status_transition
  before update of status on public.orders
  for each row execute function public.enforce_order_status_transition();

alter table public.profiles enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.notifications enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.canteen_wallet enable row level security;
alter table public.canteen_payouts enable row level security;

-- profiles
-- Students can only read their own row (no more PII dump of every email /
-- roll number); staff can read everyone.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());

-- The client never updates profiles directly; grants below limit updates to
-- display fields only, so `role` can never be self-assigned. Rows are created
-- by the handle_new_user trigger (security definer), so authenticated needs
-- no INSERT/DELETE either.
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid() or public.is_staff());

revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (name, roll_number) on public.profiles to authenticated;

-- menu_items (any logged-in user can read; only canteen staff can manage)
drop policy if exists menu_items_select on public.menu_items;
create policy menu_items_select on public.menu_items
  for select to authenticated using (true);

drop policy if exists menu_items_insert on public.menu_items;
create policy menu_items_insert on public.menu_items
  for insert to authenticated with check (public.is_canteen_staff());

drop policy if exists menu_items_update on public.menu_items;
create policy menu_items_update on public.menu_items
  for update to authenticated using (public.is_canteen_staff());

drop policy if exists menu_items_delete on public.menu_items;
create policy menu_items_delete on public.menu_items
  for delete to authenticated using (public.is_canteen_staff());

-- orders (users see their own; staff see everything).
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders
  for select to authenticated using (user_id = auth.uid() or public.is_staff());

-- Every write goes through the place_order / update_order_status RPCs, so
-- authenticated gets NO direct INSERT/UPDATE/DELETE: previously a staff user
-- could update total_amount / user_id / status straight on the table and
-- bypass the RPC (and its transition rules) entirely.
drop policy if exists orders_insert on public.orders;
drop policy if exists orders_update on public.orders;
drop policy if exists orders_delete on public.orders;

revoke insert, update, delete on public.orders from anon, authenticated;

-- order_items (read-only for clients; rows are written by place_order only)
drop policy if exists order_items_insert on public.order_items;
drop policy if exists order_items_update on public.order_items;
drop policy if exists order_items_delete on public.order_items;

revoke insert, update, delete on public.order_items from anon, authenticated;

-- TRUNCATE / REFERENCES / TRIGGER survive RLS (they are table-level ops), so
-- a logged-in student could otherwise `truncate public.orders cascade` and
-- wipe every order, item and notification in the system, or attach a trigger
-- function to a table they don't own. Also drop them from the default ACL so
-- tables created later in Supabase never grant them either.
revoke truncate, references, trigger on all tables in schema public
  from anon, authenticated;
alter default privileges in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;

-- order_items
drop policy if exists order_items_select on public.order_items;
create policy order_items_select on public.order_items
  for select to authenticated
  using (
    exists (select 1 from public.orders o where o.id = order_id)
    and (public.is_staff() or exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()))
  );

-- notifications (users see/mark their own; staff can also manage)
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated using (user_id = auth.uid() or public.is_staff());

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
  for insert to authenticated with check (public.is_staff() or user_id = auth.uid());

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated using (user_id = auth.uid() or public.is_staff());

-- wallet (reads only; every write goes through the RPCs above, so
-- authenticated gets NO direct INSERT/UPDATE/DELETE — otherwise a client
-- could credit its own balance with a raw insert).
drop policy if exists wallets_select on public.wallets;
create policy wallets_select on public.wallets
  for select to authenticated using (user_id = auth.uid() or public.is_staff());

drop policy if exists wallet_transactions_select on public.wallet_transactions;
create policy wallet_transactions_select on public.wallet_transactions
  for select to authenticated using (user_id = auth.uid() or public.is_staff());

revoke insert, update, delete on public.wallets from anon, authenticated;
revoke insert, update, delete on public.wallet_transactions from anon, authenticated;

-- canteen wallet / payouts (staff read; payouts written by canteen_payout only)
drop policy if exists canteen_wallet_select on public.canteen_wallet;
create policy canteen_wallet_select on public.canteen_wallet
  for select to authenticated using (public.is_staff());

drop policy if exists canteen_payouts_select on public.canteen_payouts;
create policy canteen_payouts_select on public.canteen_payouts
  for select to authenticated using (public.is_staff());

revoke insert, update, delete on public.canteen_wallet from anon, authenticated;
revoke insert, update, delete on public.canteen_payouts from anon, authenticated;

grant select on public.wallets, public.wallet_transactions,
  public.canteen_wallet, public.canteen_payouts to authenticated;

-- ---------- REALTIME ----------

do $$
begin
  alter publication supabase_realtime add table public.orders;
  alter publication supabase_realtime add table public.menu_items;
  alter publication supabase_realtime add table public.notifications;
  alter publication supabase_realtime add table public.wallet_transactions;
exception
  when duplicate_object then null;
end $$;

-- NOTE: There is intentionally NO seed menu data. Staff add menu items
-- from inside the app (Menu Management tab). The menu stays empty until
-- a staff member adds the first item.
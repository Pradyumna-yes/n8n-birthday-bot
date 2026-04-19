-- ============================================================
-- Birthday Bot — Supabase Schema
-- ============================================================
-- Run this in Supabase → SQL Editor → New Query → Run
-- Creates three tables: contacts, birthday_log, sync_log
-- ============================================================

-- Enable UUID extension (Supabase has it by default, but just in case)
create extension if not exists "uuid-ossp";

-- ============================================================
-- TABLE: contacts
-- Stores people to wish + their personalization fields
-- ============================================================
create table if not exists contacts (
  id uuid primary key default uuid_generate_v4(),

  -- Core identity
  full_name        text not null,
  phone_e164       text not null unique,   -- E.164 without '+', e.g. '918496813845'
  email            text,
  birthday         date not null,          -- YYYY-MM-DD (year may be 1900 if unknown)

  -- Targeting
  country_code     text not null check (country_code in ('IN', 'IE')),
  timezone         text not null,          -- IANA zone, e.g. 'Asia/Kolkata'

  -- Personalization (fill in manually after Google sync)
  tone             text default 'warm and friendly',
  language         text default 'English',
  relationship     text,                   -- e.g. 'college friend', 'cousin'
  inside_jokes     text,                   -- free text for the AI to weave in

  -- Sync metadata
  google_resource_name text unique,        -- e.g. 'people/c1234...' (null for manual rows)
  source           text default 'manual' check (source in ('manual', 'google')),
  is_active        boolean default true,

  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

create index if not exists idx_contacts_active       on contacts(is_active) where is_active = true;
create index if not exists idx_contacts_country      on contacts(country_code);
create index if not exists idx_contacts_birthday     on contacts(birthday);

-- Auto-update `updated_at` on row changes
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_contacts_updated_at on contacts;
create trigger trg_contacts_updated_at
  before update on contacts
  for each row execute function touch_updated_at();


-- ============================================================
-- TABLE: birthday_log
-- One row per send attempt (success or failure)
-- ============================================================
create table if not exists birthday_log (
  id               uuid primary key default uuid_generate_v4(),
  contact_id       uuid references contacts(id) on delete cascade,
  contact_name     text,
  phone_e164       text,
  sent_on          date not null,          -- date the wish was intended for
  status           text not null check (status in ('success', 'failed', 'skipped')),
  attempt_count    int default 1,
  message_preview  text,                   -- first 200 chars of the generated message
  error_message    text,
  evolution_response jsonb,                -- raw Evolution API response (optional)
  created_at       timestamptz default now()
);

create index if not exists idx_log_contact_date on birthday_log(contact_id, sent_on);
create index if not exists idx_log_sent_on      on birthday_log(sent_on);
create index if not exists idx_log_status       on birthday_log(status);

-- Prevent more than one SUCCESS per contact per day (idempotency)
create unique index if not exists uq_log_success_per_day
  on birthday_log(contact_id, sent_on)
  where status = 'success';


-- ============================================================
-- TABLE: sync_log
-- One row per Google sync run (for debugging / audit)
-- ============================================================
create table if not exists sync_log (
  id              uuid primary key default uuid_generate_v4(),
  ran_at          timestamptz default now(),
  contacts_seen   int,
  contacts_kept   int,
  contacts_skipped_no_phone    int,
  contacts_skipped_no_birthday int,
  contacts_skipped_bad_phone   int,
  contacts_skipped_out_of_scope int,
  notes           text
);

create index if not exists idx_sync_log_ran_at on sync_log(ran_at desc);


-- ============================================================
-- Done. Verify with:
--   select count(*) from contacts;
--   select count(*) from birthday_log;
-- ============================================================

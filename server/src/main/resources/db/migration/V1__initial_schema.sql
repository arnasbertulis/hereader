create table users (
                       id            uuid primary key,
                       email         text        not null unique,
                       password_hash text        not null,
                       created_at    timestamptz not null default now()
);

create table sync_events (
                             id              bigserial primary key,
                             user_id         uuid        not null references users (id) on delete cascade,

                             seq             bigint      not null,

                             idempotency_key text        not null,

                             entity_type     text        not null,
                             entity_id       text        not null,
                             payload         jsonb       not null,

                             hlc             text        not null,

                             device_id       text        not null,

                             created_at      timestamptz not null default now(),

                             unique (user_id, seq),
                             unique (user_id, idempotency_key)
);

create index sync_events_user_seq on sync_events (user_id, seq);

create table user_sync_state (
                                 user_id  uuid primary key references users (id) on delete cascade,
                                 last_seq bigint not null default 0
);
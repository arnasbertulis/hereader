create table entity_state (
                              user_id     uuid        not null references users (id) on delete cascade,
                              entity_type text        not null,
                              entity_id   text        not null,

                              payload     jsonb       not null,

                              hlc         text        not null,

                              device_id   text        not null,

                              deleted     boolean     not null default false,

                              updated_at  timestamptz not null default now(),

                              primary key (user_id, entity_type, entity_id)
);

create table position_conflicts (
                                    id          bigserial primary key,
                                    user_id     uuid        not null references users (id) on delete cascade,
                                    book_id     text        not null,

                                    ours        jsonb       not null,
                                    theirs      jsonb       not null,

                                    created_at  timestamptz not null default now(),
                                    resolved_at timestamptz,

                                    unique (user_id, book_id, resolved_at)
);

create index entity_state_lookup
    on entity_state (user_id, entity_type, updated_at);
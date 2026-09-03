CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(255) UNIQUE NOT NULL,
    venue      VARCHAR(255) NOT NULL,
    event_date TIMESTAMPTZ NOT NULL
);

-- Bouncer only ever sells one event. ON CONFLICT keeps this idempotent,
-- same reasoning as the users table above -- safe to run on every boot.
INSERT INTO events (name, venue, event_date)
VALUES ('Bouncer Launch Night', 'Frankfurt Music Hall', '2026-10-15 20:00:00+02')
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS tickets (
    id         SERIAL PRIMARY KEY,
    event_id   INTEGER NOT NULL REFERENCES events(id),
    user_id    INTEGER NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, user_id)
);

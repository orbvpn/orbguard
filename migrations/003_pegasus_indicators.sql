-- +goose Up
-- +goose StatementBegin

SET search_path TO orbguard_lab, public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
    pegasus_campaign_id UUID;
    nso_actor_id UUID;
    pegasus_malware_id UUID;
    citizenlab_source_id UUID;
    amnesty_source_id UUID;
BEGIN
    ------------------------------------------------------------
    -- Get required IDs
    ------------------------------------------------------------
    SELECT id INTO pegasus_campaign_id FROM campaigns WHERE slug = 'pegasus';
    SELECT id INTO nso_actor_id FROM threat_actors WHERE name = 'NSO Group';
    SELECT id INTO pegasus_malware_id FROM malware_families WHERE name = 'Pegasus';
    SELECT id INTO citizenlab_source_id FROM sources WHERE slug = 'citizenlab';
    SELECT id INTO amnesty_source_id FROM sources WHERE slug = 'amnesty_mvt';

    ------------------------------------------------------------
    -- Validation
    ------------------------------------------------------------
    IF pegasus_campaign_id IS NULL THEN
        RAISE EXCEPTION 'Pegasus campaign not found';
    END IF;

    IF nso_actor_id IS NULL THEN
        RAISE EXCEPTION 'NSO Group threat actor not found';
    END IF;

    IF pegasus_malware_id IS NULL THEN
        RAISE EXCEPTION 'Pegasus malware family not found';
    END IF;

    IF citizenlab_source_id IS NULL THEN
        RAISE EXCEPTION 'CitizenLab source not found';
    END IF;

    ------------------------------------------------------------
    -- INSERT indicators (UUID source_id, no source_name)
    ------------------------------------------------------------
    INSERT INTO indicators (
        value, value_hash, type, severity, confidence,
        description, tags, platforms,
        campaign_id, threat_actor_id, malware_family_id,
        source_id, source_name,          -- 🔥 tambahkan lagi
        mitre_techniques, first_seen, last_seen
    )
    VALUES
    (
        'lsgatag.com',
        encode(digest('lsgatag.com', 'sha256'), 'hex'),
        'domain', 'critical', 0.95,
        'Known Pegasus C2 domain',
        ARRAY['pegasus','nso-group','c2'],
        ARRAY['android','ios']::platform_type[],
        pegasus_campaign_id, nso_actor_id, pegasus_malware_id,
        citizenlab_source_id,
        'Citizen Lab',                   -- 🔥 isi manual
        ARRAY['T1071'],
        '2016-08-01', NOW()
    ),
    (
        'setframed',
        encode(digest('setframed', 'sha256'), 'hex'),
        'process', 'critical', 0.95,
        'Pegasus iOS process',
        ARRAY['pegasus','ios'],
        ARRAY['ios']::platform_type[],
        pegasus_campaign_id, nso_actor_id, pegasus_malware_id,
        citizenlab_source_id,
        'Citizen Lab',                   -- 🔥 isi manual
        ARRAY['T1424'],
        '2016-08-01', NOW()
    )
    ON CONFLICT (value_hash) DO UPDATE SET
        last_seen = EXCLUDED.last_seen,
        updated_at = NOW();

    ------------------------------------------------------------
    -- Additional source mapping
    ------------------------------------------------------------
    INSERT INTO indicator_sources (indicator_id, source_id, source_confidence, fetched_at)
    SELECT i.id, amnesty_source_id, 0.95, NOW()
    FROM indicators i
    WHERE i.campaign_id = pegasus_campaign_id
    ON CONFLICT DO NOTHING;

    ------------------------------------------------------------
    -- Recalculate counts (ONLY related rows)
    ------------------------------------------------------------

    -- Update source count
    UPDATE sources s
    SET indicator_count = (
        SELECT COUNT(*)
        FROM indicators i
        WHERE i.source_id = s.id::text
    )
    WHERE s.id IN (citizenlab_source_id, amnesty_source_id);

    -- Update campaign count
    UPDATE campaigns c
    SET indicator_count = (
        SELECT COUNT(*)
        FROM indicators i
        WHERE i.campaign_id = c.id
    )
    WHERE c.id = pegasus_campaign_id;

    -- Update threat actor count
    UPDATE threat_actors t
    SET indicator_count = (
        SELECT COUNT(*)
        FROM indicators i
        WHERE i.threat_actor_id = t.id
    )
    WHERE t.id = nso_actor_id;

    -- Update malware family count
    UPDATE malware_families m
    SET indicator_count = (
        SELECT COUNT(*)
        FROM indicators i
        WHERE i.malware_family_id = m.id
    )
WHERE m.id = pegasus_malware_id;

END $$;

-- +goose StatementEnd



-- +goose Down
-- +goose StatementBegin

DELETE FROM indicators
WHERE value IN ('lsgatag.com','setframed');

-- Optional: reset counters
UPDATE sources SET indicator_count = 0;
UPDATE campaigns SET indicator_count = 0;
UPDATE threat_actors SET indicator_count = 0;
UPDATE malware_families SET indicator_count = 0;

-- +goose StatementEnd
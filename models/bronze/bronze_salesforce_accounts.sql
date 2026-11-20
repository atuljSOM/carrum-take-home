{{ config(alias='salesforce_accounts') }}

-- Exact copy of the raw extract: no renaming, casting, filtering or deduplication.
-- `select *` is deliberate: with an explicit column list a new upstream column would be silently
-- dropped, whereas here the enforced contract in _bronze.yml fails the build on any column drift.
select * from {{ source('raw_sources', 'salesforce_accounts') }}

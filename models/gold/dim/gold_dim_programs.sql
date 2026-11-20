{{ config(alias='dim_programs') }}

-- Grain: one row per employer benefit program.
-- The hub dimension: fee lines and NetSuite adjustments both attach here, and it carries the
-- employer roll-up so every fact reaches the employer through one join.

select
    programs.program_id,
    programs.program_name,
    programs.service_line,
    programs.tpa_name,
    programs.go_live_date,
    programs.term_end_date,
    programs.account_id,
    employers.account_name,
    employers.employer_id,
    employers.employer_name
from {{ ref('silver_stg_salesforce_programs') }} as programs
left join {{ ref('gold_dim_employers') }} as employers
    on employers.account_id = programs.account_id

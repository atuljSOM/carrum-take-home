{{ config(alias='stg_salesforce_programs') }}

-- Grain: one row per employer benefit program. Rules and columns: see the model's yml.

select
    trim(program_id)          as program_id,
    trim(account_id)          as account_id,
    trim(program_name)        as program_name,
    trim(service_line)        as service_line,
    trim(tpa_name)            as tpa_name,
    cast(go_live_date as date)  as go_live_date,
    cast(term_end_date as date) as term_end_date
from {{ ref('bronze_salesforce_programs') }}

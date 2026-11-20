{{ config(alias='stg_salesforce_accounts') }}

-- Grain: one row per Salesforce account. Rules and columns: see the model's yml.

select
    trim(account_id)        as account_id,
    trim(account_name)      as account_name,
    trim(parent_account_id) as parent_account_id,
    trim(industry)          as industry,
    trim(funding_type)      as funding_type
from {{ ref('bronze_salesforce_accounts') }}

{{ config(alias='stg_salesforce_accounts') }}

-- One row per Salesforce account. Trims names and IDs; no other change.
-- The parent hierarchy is kept as delivered: top-level accounts point to themselves, and a
-- parent that does not exist (EMP-108 -> EMP-150) is left as is. Resolving it is a gold decision.
select
    trim(account_id)        as account_id,
    trim(account_name)      as account_name,
    trim(parent_account_id) as parent_account_id,
    trim(industry)          as industry,
    trim(funding_type)      as funding_type
from {{ ref('bronze_salesforce_accounts') }}

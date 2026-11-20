{{ config(alias='dim_employers') }}

-- Grain: one row per Salesforce account.
-- Resolves each account to its employer: the ultimate parent in the account hierarchy.
-- Subsidiaries, unions and duplicate accounts roll up to that parent so one employer is one line.
-- An account whose parent does not exist in Salesforce is treated as its own employer (flagged).

with recursive

accounts as (
    select * from {{ ref('silver_stg_salesforce_accounts') }}
),

-- Walk up the hierarchy one level per step. Stops at a self-parented account, at a parent that
-- does not exist, or after 10 levels (guards against cycles).
walk as (
    select account_id, account_id as ancestor_id, 0 as depth
    from accounts

    union all

    select walk.account_id, accounts.parent_account_id, walk.depth + 1
    from walk
    join accounts on accounts.account_id = walk.ancestor_id
    where accounts.parent_account_id <> accounts.account_id
      and accounts.parent_account_id in (select account_id from accounts)
      and walk.depth < 10
),

ultimate as (
    select account_id, arg_max(ancestor_id, depth) as employer_id, max(depth) as hierarchy_depth
    from walk
    group by account_id
)

select
    accounts.account_id,
    accounts.account_name,
    accounts.parent_account_id,
    accounts.industry,
    accounts.funding_type,
    ultimate.employer_id,
    employer.account_name                                         as employer_name,
    ultimate.hierarchy_depth,
    accounts.parent_account_id not in (select account_id from accounts) as is_parent_missing
from accounts
join ultimate on ultimate.account_id = accounts.account_id
join accounts as employer on employer.account_id = ultimate.employer_id

-- Part 3 contract: every column of the LLM-facing tables carries a definition in the DuckDB file
-- itself (written by persist_docs from the yml). Fails if a column is added without a description,
-- or if comments stop being persisted. Severity: error. Returns each undocumented column.

{% set llm_tables = [
    ref('gold_agg_revenue_employer_monthly'),
    ref('gold_agg_revenue_program_monthly'),
    ref('gold_agg_pacing_fee_line'),
    ref('gold_rpt_data_quality_register'),
] %}

select schema_name, table_name, column_name
from duckdb_columns()
where (comment is null or trim(comment) = '')
  and (
    {%- for t in llm_tables %}
    (schema_name = '{{ t.schema }}' and table_name = '{{ t.identifier }}'){% if not loop.last %} or{% endif %}
    {%- endfor %}
  )

# Workforce Attrition AI (Snowflake + Cortex)

An end-to-end HR analytics project in Snowflake: raw data, a modeled star schema with a scheduled
pipeline, embeddings, vector search, and a retrieval-augmented generation (RAG) assistant that answers
questions about why employees leave, grounded in real attrition statistics and exit-interview comments.

**Data:** the public IBM HR Employee Attrition dataset (Kaggle) plus 300 **synthetic** exit-interview
comments generated for this project. No real employee data is used.

## Architecture
1. **Raw layer** (`RAW`): CSVs loaded from an internal stage with `COPY INTO`.
2. **Modeled layer** (`ANALYTICS`): department and employee dimensions plus an attrition fact table with
   engineered features (overtime flag, tenure band, satisfaction score, stalled promotion flag).
   A stored procedure rebuilds the model and a Snowflake Task runs it daily.
3. **Embeddings:** `AI_EMBED` (Arctic embed model) stores a 768-dimension vector for each comment.
4. **Vector search + RAG:** a question is embedded, the 5 most similar comments are retrieved with
   `VECTOR_COSINE_SIMILARITY`, and `AI_COMPLETE` (Claude Sonnet 4.5, cross-region inference) answers using only those comments and the
   department attrition stats, citing comment IDs.
5. **Governance:** a masking policy hides employee IDs from non-admin roles.
6. **Dashboard:** attrition by department, overtime, job role, and tenure, plus comment themes.

## Key findings (IBM HR dataset, 1,470 employees)
- **Overtime:** employees who work overtime left at **30.5%**, versus **10.4%** for those who don't, nearly **3x** the rate.
- **Tenure:** first-year employees (0 to 1 years) left at **34.9%**, versus **10.4%** for those with 10+ years.
- **Job role:** Sales Representatives had the highest attrition at **39.8%**; Research Directors the lowest at **2.5%**.
- **Department:** Sales **20.6%**, Human Resources **19.0%**, Research & Development **13.8%**.
- Exit-comment themes are synthetic and used only to demonstrate retrieval, not as findings.

## Run order
`sql/01_setup_and_load.sql` > `02_model_and_pipeline.sql` > `03_embeddings.sql` >
`04_vector_search_and_rag.sql` > `05_governance_and_dashboard.sql`

## RAG assistant in action
**Question:** *What do employees say about promotions?* The answer cites 5 comment IDs and notes the pattern is concentrated in Research & Development.

![RAG answer: promotions](screenshots/rag-answer-1.png)

**Question:** *Why are Sales employees leaving?* The answer combines department statistics with cited comments, and flags that only two Sales comments were retrieved instead of overstating its conclusion.

![RAG answer: Sales](screenshots/rag-answer-2.png)

## Semantic search
Searching for "exhausted from long hours" returns comments like "it wore me down" and "constant extra hours left no time for my family," even though none share a keyword with the query.

![Semantic search](screenshots/semantic-search.png)

## Dashboard
![Attrition: overtime vs. no overtime](screenshots/chart-overtime.png)
![Attrition by tenure](screenshots/chart-tenure.png)
![Attrition by job role](screenshots/chart-job-role.png)
![Attrition by department](screenshots/chart-department.png)

## Data masking (admin vs. analyst role)
The same query returns real employee IDs to ACCOUNTADMIN and NULL to the least-privilege HR_ANALYST role.

![Admin view](screenshots/masking-admin.png)
![Analyst view](screenshots/masking-analyst.png)
![Masking policy attached to FACT_ATTRITION](screenshots/masking-policy.png)

## Limitations and next steps
- Retrieval ranks all comments by meaning, so department-specific questions can pull comments from other departments. Next step: filter by department when the question names one, then rank by similarity.
- Exit comments are synthetic; with real data, retrieval quality and findings would need re-validation.
- Built on a Snowflake trial account: AI functions require a payment method on trial accounts, and current LLMs are served through cross-region inference from AWS US West 2.

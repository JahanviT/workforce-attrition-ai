-- 04: Vector search + retrieval-augmented generation (Weekend, day 1)
USE ROLE ACCOUNTADMIN; USE WAREHOUSE HR_WH; USE SCHEMA HR_ANALYTICS.ANALYTICS;

-- Run once: current models are served cross-region from AWS US West 2 (Oregon)
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

-- Change this question and rerun
SET QUESTION = 'Why are Sales employees leaving?';

-- Step A: semantic search only
SELECT COMMENT_ID, DEPARTMENT, COMMENT_TEXT,
       VECTOR_COSINE_SIMILARITY(COMMENT_VEC, AI_EMBED('snowflake-arctic-embed-m', $QUESTION)) AS SIMILARITY
FROM HR_ANALYTICS.ANALYTICS.EXIT_COMMENT_EMBEDDINGS
ORDER BY SIMILARITY DESC
LIMIT 5;

-- Step B: full RAG answer grounded in retrieved comments + attrition stats
WITH Q AS (
  SELECT AI_EMBED('snowflake-arctic-embed-m', $QUESTION) AS QV
),
TOP_COMMENTS AS (                         -- 1. RETRIEVE
  SELECT c.COMMENT_ID, c.DEPARTMENT, c.COMMENT_TEXT
  FROM HR_ANALYTICS.ANALYTICS.EXIT_COMMENT_EMBEDDINGS c, Q
  ORDER BY VECTOR_COSINE_SIMILARITY(c.COMMENT_VEC, Q.QV) DESC
  LIMIT 5
),
CONTEXT AS (
  SELECT LISTAGG('[' || COMMENT_ID || ', ' || DEPARTMENT || '] ' || COMMENT_TEXT, '\n') AS COMMENTS
  FROM TOP_COMMENTS
),
STATS AS (                                -- 2. AUGMENT
  SELECT LISTAGG(DEPARTMENT || ': ' || ATTRITION_PCT || '% attrition, '
                 || OVERTIME_PCT || '% work overtime', '; ') AS FACTS
  FROM (
    SELECT DEPARTMENT,
           ROUND(100 * AVG(ATTRITION_FLAG), 1) AS ATTRITION_PCT,
           ROUND(100 * AVG(OVERTIME_FLAG), 1)  AS OVERTIME_PCT
    FROM HR_ANALYTICS.ANALYTICS.FACT_ATTRITION
    GROUP BY DEPARTMENT
  )
)
SELECT                                    -- 3. GENERATE
  CONTEXT.COMMENTS AS RETRIEVED_COMMENTS,
  AI_COMPLETE(
    'claude-sonnet-4-5',
    'You are an HR analytics assistant. Answer the question using ONLY the data below. '
    || 'Cite comment IDs in brackets. Keep it to 4 to 6 sentences. '
    || 'If the data does not support an answer, say so.\n\n'
    || 'QUESTION: ' || $QUESTION || '\n\n'
    || 'ATTRITION STATS BY DEPARTMENT: ' || STATS.FACTS || '\n\n'
    || 'RELEVANT EXIT COMMENTS (synthetic data):\n' || CONTEXT.COMMENTS
  ) AS ANSWER
FROM CONTEXT, STATS;

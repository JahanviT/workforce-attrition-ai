-- 06: Department-aware RAG (metadata pre-filter + vector ranking)
-- If the question names a department (including aliases like "R&D" and "HR"),
-- retrieval is restricted to that department's comments before ranking by cosine similarity.
-- If no department is named, all comments are searched, as in 04.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE HR_WH;
USE SCHEMA HR_ANALYTICS.ANALYTICS;

SET QUESTION = 'Why are Sales employees leaving?';
-- Other tests:
-- SET QUESTION = 'Why are R&D employees leaving?';              -- filter: Research & Development
-- SET QUESTION = 'What do HR staff say about their managers?';  -- filter: Human Resources
-- SET QUESTION = 'What do employees say about promotions?';     -- filter: none (all departments)

WITH Q AS (
  SELECT AI_EMBED('snowflake-arctic-embed-m', $QUESTION) AS QV,
         ' ' || LOWER(REGEXP_REPLACE($QUESTION, '[^A-Za-z&]', ' ')) || ' ' AS QTEXT
),
DEPT AS (                                  -- 0. DETECT: which department does the question name?
  SELECT MAX(d.DEPARTMENT) AS DEPT_FILTER
  FROM HR_ANALYTICS.ANALYTICS.DIM_DEPARTMENT d, Q
  WHERE CONTAINS(Q.QTEXT, ' ' || LOWER(d.DEPARTMENT) || ' ')
     OR (d.DEPARTMENT = 'Sales' AND CONTAINS(Q.QTEXT, ' sales '))
     OR (d.DEPARTMENT = 'Research & Development'
         AND (CONTAINS(Q.QTEXT, ' r&d ') OR CONTAINS(Q.QTEXT, ' research ')))
     OR (d.DEPARTMENT = 'Human Resources'
         AND (CONTAINS(Q.QTEXT, ' hr ') OR CONTAINS(Q.QTEXT, ' human resources ')))
),
TOP_COMMENTS AS (                          -- 1. RETRIEVE: filter by department first, then rank by meaning
  SELECT c.COMMENT_ID, c.DEPARTMENT, c.COMMENT_TEXT,
         VECTOR_COSINE_SIMILARITY(c.COMMENT_VEC, Q.QV) AS SIMILARITY
  FROM HR_ANALYTICS.ANALYTICS.EXIT_COMMENT_EMBEDDINGS c, Q, DEPT
  WHERE DEPT.DEPT_FILTER IS NULL OR c.DEPARTMENT = DEPT.DEPT_FILTER
  ORDER BY SIMILARITY DESC
  LIMIT 5
),
CONTEXT AS (
  SELECT LISTAGG('[' || COMMENT_ID || ', ' || DEPARTMENT || '] ' || COMMENT_TEXT, '\n') AS COMMENTS
  FROM TOP_COMMENTS
),
STATS AS (                                 -- 2. AUGMENT
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
SELECT                                     -- 3. GENERATE
  COALESCE(DEPT.DEPT_FILTER, 'none (all departments)') AS DEPARTMENT_FILTER,
  CONTEXT.COMMENTS AS RETRIEVED_COMMENTS,
  AI_COMPLETE(
    'claude-sonnet-4-5',
    'You are an HR analytics assistant. Answer the question using ONLY the data below. '
    || 'Cite comment IDs in brackets. Keep it to 4 to 6 sentences. '
    || 'If the data does not support an answer, say so.\n\n'
    || 'QUESTION: ' || $QUESTION || '\n\n'
    || 'DEPARTMENT FILTER APPLIED: ' || COALESCE(DEPT.DEPT_FILTER, 'none') || '\n\n'
    || 'ATTRITION STATS BY DEPARTMENT: ' || STATS.FACTS || '\n\n'
    || 'RELEVANT EXIT COMMENTS (synthetic data):\n' || CONTEXT.COMMENTS
  ) AS ANSWER
FROM CONTEXT, STATS, DEPT;

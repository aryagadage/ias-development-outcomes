"""
Compute QueueT_st: Engineer share of state-year active DC pool.
Output: data/analysis/QueueT_st.csv  (state_id, year, QueueT_st, n_eng, n_tot)
"""
import warnings; warnings.filterwarnings("ignore")
import duckdb, pandas as pd

con = duckdb.connect()

# ── Education classification (one row per officer) ────────────────────────────
edu = con.execute("""
WITH raw AS (
    SELECT ID,
        TRY_CAST(Reference_Value AS INTEGER) AS ref_val,
        CASE
            WHEN Category_of_Subject IS NULL OR trim(Category_of_Subject) = ''
                THEN 'NA_Unclassified'
            WHEN trim(Category_of_Subject) =
                 'Engineering, Technology and Mathematics' THEN 'Engineer'
            WHEN trim(Category_of_Subject) IN (
                 'Social Science and Liberal Arts',
                 'Governance, Law and Management') THEN 'SocialScientist'
            ELSE 'Residual'
        END AS bg_class,
        CASE WHEN Category_of_Subject IS NULL OR trim(Category_of_Subject) = '' THEN 0
             WHEN trim(Category_of_Subject) =
                  'Engineering, Technology and Mathematics' THEN 5
             WHEN trim(Category_of_Subject) IN (
                  'Social Science and Liberal Arts',
                  'Governance, Law and Management') THEN 4
             ELSE 3 END AS bg_priority
    FROM read_csv_auto('data/raw/ias-education.csv', nullstr=['N.A.','NA','n.a.','N/A'])
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY ID ORDER BY ref_val DESC NULLS LAST, bg_priority DESC) AS rn
    FROM raw
)
SELECT ID AS officer_id, bg_class FROM ranked WHERE rn = 1
""").df()

# ── DC spells: officer × cadre × year ────────────────────────────────────────
exp_dc = con.execute("""
SELECT
    ID AS officer_id,
    trim(Cadre) AS cadre,
    YEAR(TRY_CAST(Start_Date AS DATE)) AS year
FROM read_csv_auto('data/raw/ias-experience.csv',
     nullstr=['N.A.','NA','n.a.','N/A'],
     types={'Start_Date':'VARCHAR','End_Date':'VARCHAR'})
WHERE YEAR(TRY_CAST(Start_Date AS DATE)) BETWEEN 1985 AND 2008
  AND (upper(trim(Designation)) LIKE '%DISTRICT COLLECTOR%'
    OR upper(trim(Designation)) LIKE '%COLLECTOR%'
    OR upper(trim(Designation)) LIKE '%DISTRICT MAGISTRATE%'
    OR upper(trim(Designation)) LIKE '%DEPUTY COMMISSIONER%')
  AND upper(trim(Designation)) NOT LIKE '%ADDITIONAL%'
  AND upper(trim(Designation)) NOT LIKE '%JOINT%'
  AND upper(trim(Designation)) NOT LIKE '%JT %'
  AND upper(trim(Designation)) NOT LIKE '%SUB %'
  AND upper(trim(Designation)) NOT LIKE '%ASSISTANT%'
  AND upper(trim(Designation)) NOT LIKE '%DEPUTY COLLECTOR%'
  AND upper(trim(Designation)) NOT LIKE '%SPL DEPUTY%'
""").df()

# ── Cadre → state_id mapping (from crosswalk) ────────────────────────────────
cw = pd.read_csv("data/analysis/crosswalk_v2.csv", dtype=str)
cw = cw[cw["pc11_state_id"].notna() & ~cw["pc11_state_id"].isin(["NA",""])].copy()
cw["cadre"] = cw["cadre"].str.strip()
cw["pc11_state_id"] = cw["pc11_state_id"].str.strip().str.zfill(2)

cadre_state = (cw[["cadre","pc11_state_id"]]
               .drop_duplicates()
               .rename(columns={"pc11_state_id":"state_id"}))

# ── Join education + cadre→state, deduplicate ────────────────────────────────
pool = (exp_dc
        .merge(edu, on="officer_id", how="left")
        .merge(cadre_state, on="cadre", how="inner"))

pool = pool[pool["bg_class"] != "NA_Unclassified"]
pool = pool.drop_duplicates(subset=["officer_id","state_id","year"])

# ── Aggregate to state × year ─────────────────────────────────────────────────
QueueT = (pool.groupby(["state_id","year"])
          .agg(n_eng=("bg_class", lambda x: (x == "Engineer").sum()),
               n_tot=("bg_class", "count"))
          .assign(QueueT_st=lambda x: x["n_eng"] / x["n_tot"])
          .reset_index())

QueueT = QueueT[QueueT["year"].between(1994, 2008)]

print(f"QueueT_st: {len(QueueT)} state-year cells")
print(QueueT["QueueT_st"].describe().round(3))
print("\nMean QueueT_st by year:")
print(QueueT.groupby("year")["QueueT_st"].mean().round(3))

QueueT.to_csv("data/analysis/QueueT_st.csv", index=False)
print(f"\nSaved data/analysis/QueueT_st.csv")

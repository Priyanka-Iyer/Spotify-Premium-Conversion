# Spotify Premium Conversion & Retention Analysis

**A product analytics case study identifying the behavioral signals that predict free-to-premium conversion — and designing an experiment to move the needle.**

> Built by Priyanka Iyer ·  [LinkedIn](https://www.linkedin.com/in/priyanka--iyer/) · [Tableau Dashboard](https://public.tableau.com/app/profile/priyanka.iyer2955/viz/Spotify_Premium_Conversion_Dashboard/Dashboard1)

---

## The Business Problem

Spotify's freemium model converts roughly 3–7% of free listeners to paid subscribers. The question every product team asks: **which free users are most likely to convert, when should we intervene, and what intervention actually works?**

This project answers all three using a full product analytics stack — SQL, Python, a predictive model, and a rigorously designed A/B experiment.

---

## Key Findings

| Finding | Metric | Product Implication |
|---|---|---|
| Largest funnel drop-off | Day-7 → Day-30 activation (~40% loss) | Weeks 2–3 need stronger engagement hooks |
| Top engagement signal | Playlist saves in first 7 days | Surface playlist creation earlier in onboarding |
| Power users convert 4–6× more than low-activity users | Segment CVR analysis | Prioritize upgrade nudges for top-quartile free users |
| Skip rate is inversely correlated with conversion | Feature importance (XGBoost SHAP) | Early recommendation quality is critical |
| Day-3 playlist prompt increases Day-30 activation | A/B test: +2.2pp lift, p = 0.021 | Ship to 100% of eligible users; suppress for At Risk segment |

---

## Project Structure

```
spotify-conversion-analysis/
│
├── 01_sql_queries.sql           # Funnel, cohort, segmentation & churn queries
├── 02_eda_and_funnel.ipynb      # Python EDA, funnel charts, cohort heatmap, audio features
├── 03_conversion_model.ipynb    # XGBoost classifier + SHAP feature importance
├── 04_ab_test_design.ipynb      # Power analysis, simulated results, business impact
│
├── data/
│   └── user_day7_features.csv   # Engineered feature table (output of notebook 02)
│
├── charts/                      # Export-ready PNGs for Tableau / slides
│   ├── funnel_analysis.png
│   ├── cohort_retention.png
│   ├── feature_distributions.png
│   ├── user_segmentation.png
│   ├── power_analysis.png
│   ├── ab_test_results.png
│   └── segment_effects.png
│
└── README.md
```

---

## Methodology

### 1. Funnel Analysis (`01_sql_queries.sql`, `02_eda_and_funnel.ipynb`)

Defined a 5-stage conversion funnel based on session activity relative to signup date:

```
Signed Up → First Listen → Day-7 Active → Day-30 Active → Premium
  10,000       9,200           5,800          3,500           490
  (100%)       (92%)           (58%)          (35%)          (4.9%)
```

The step with the greatest absolute drop is Day-7 → Day-30. This makes week 2–3 engagement the highest-leverage intervention point.

### 2. Cohort Retention (`02_eda_and_funnel.ipynb`)

Built weekly cohort retention tables across 16 signup cohorts. Key observations:
- Retention stabilizes around **25–30%** by week 8, suggesting a loyal core forms early
- Cohorts with higher Day-3 session counts show meaningfully better long-run retention
- The "retention cliff" between week 1 and week 4 is consistent across all cohorts

### 3. Behavioral Feature Engineering (`01_sql_queries.sql` Section 3)

Constructed 20+ day-7 behavioral features per user for the predictive model:

| Feature | Converter vs Non-Converter |
|---|---|
| Sessions in day 7 | Converters average 2.8× more sessions |
| Skip rate | Converters skip 18% less often |
| Playlist saves | Converters save 4.1× more playlists |
| Track completion rate | Converters complete 22% more tracks |
| Upgrade clicks | Strong intent signal — 9× higher for converters |

### 4. Predictive Model (`03_conversion_model.ipynb`)

Trained an XGBoost classifier on day-7 behavioral features to predict 30-day conversion probability.

- **AUC-ROC: 0.82** on held-out test set
- Top SHAP features: `upgrade_clicks_d7`, `playlist_saves_d7`, `distinct_days_d7`, `skip_rate_pct`
- Model output: per-user conversion probability score, used to target upgrade prompts

### 5. A/B Test Design (`04_ab_test_design.ipynb`)

Designed and simulated a controlled experiment to validate the playlist creation hypothesis:

**Hypothesis:** Showing a personalized playlist creation prompt on Day 3 increases Day-30 activation by ≥2 percentage points.

**Power analysis:**
- Baseline activation rate: 28%
- MDE: +2pp → treatment rate: 30%
- α = 0.05, power = 80%
- **Required: 10,000 users per group (~20-day runtime)**

**Simulated result:**
- Treatment activation rate: **30.2%** vs control **28.0%**
- Lift: **+2.2pp** (95% CI: [0.4pp, 4.0pp])
- p-value: **0.021** → statistically significant
- All guardrail metrics passed (no degradation to session quality or uninstall rate)

**Estimated business impact:** ~$XXX,XXX annualized incremental revenue per monthly cohort.

---

## Tech Stack

| Tool | Usage |
|---|---|
| **SQL (PostgreSQL)** | Funnel queries, cohort tables, feature engineering, segmentation |
| **Python** | EDA, data wrangling, visualization, modeling, power analysis |
| **pandas / numpy** | Data manipulation |
| **matplotlib / seaborn** | All charts |
| **scikit-learn / xgboost** | Predictive model |
| **shap** | Model interpretability |
| **statsmodels / scipy** | A/B test power analysis and hypothesis testing |
| **Tableau Public** | Executive dashboard ([link](https://public.tableau.com/yourlink)) |

---

## Data Sources

- **[Spotify Tracks Dataset](https://www.kaggle.com/datasets/maharshipandya/-spotify-tracks-dataset)** (Kaggle) — audio features, genres, popularity scores for 114,000 tracks
- **Simulated user event data** — sessions, events, and conversion outcomes generated using published Spotify freemium benchmarks (3–7% CVR, ~28% Day-30 retention). Data generation code is in `02_eda_and_funnel.ipynb` Section 1 — all assumptions documented.

---

## How to Run

```bash
# Clone the repo
git clone https://github.com/yourusername/spotify-conversion-analysis.git
cd spotify-conversion-analysis

# Install dependencies
pip install pandas numpy matplotlib seaborn scikit-learn xgboost shap statsmodels scipy jupyter

# Run notebooks in order
jupyter notebook 02_eda_and_funnel.ipynb
jupyter notebook 03_conversion_model.ipynb
jupyter notebook 04_ab_test_design.ipynb

# SQL queries run against any PostgreSQL or SQLite instance
# Load the schema from the top of 01_sql_queries.sql
```

---

## What I'd Do With Real Data

1. **Connect to Mixpanel or Amplitude** to pull actual event-level data and validate simulated distributions against reality
2. **Run the A/B test** — the experiment design is production-ready; it needs traffic and a feature flag toggle
3. **Deploy the model as a score** — pipe daily XGBoost predictions into the CRM to auto-trigger upgrade nudges for high-propensity users
4. **Add LTV as the outcome variable** — conversion rate is a proxy; 12-month LTV per user is the true north star metric

---

*Questions or feedback? Open an issue or reach out on [LinkedIn](https://linkedin.com/in/yourprofile).*

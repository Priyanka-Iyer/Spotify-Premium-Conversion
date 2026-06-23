-- =============================================================
-- Spotify Freemium Conversion & Retention Funnel Analysis
-- Author: [Your Name] | UC Davis MSBA
-- Description: Full SQL query suite for funnel, cohort, 
--              segmentation, and power-user analysis
-- Database: PostgreSQL / SQLite compatible
-- =============================================================


-- =============================================================
-- SECTION 0: SCHEMA REFERENCE
-- =============================================================
-- 
-- users (user_id, signup_date, country, age_group, plan_type, converted_date)
-- sessions (session_id, user_id, session_date, session_duration_sec, device_type)
-- events (event_id, session_id, user_id, event_type, event_ts)
--         event_type: 'play', 'skip', 'like', 'playlist_save', 'share',
--                     'ad_view', 'upgrade_click', 'search'
-- tracks_played (play_id, session_id, user_id, track_id, play_date,
--                play_duration_sec, track_duration_sec, completed)
-- tracks (track_id, track_name, artist, genre, energy, danceability,
--         acousticness, tempo, valence, popularity)
--
-- =============================================================


-- =============================================================
-- SECTION 1: FUNNEL ANALYSIS
-- Free-to-Premium conversion funnel with step-by-step drop-off
-- =============================================================

-- 1.1 Full funnel: volume and conversion rate at each stage
WITH funnel_stages AS (
    SELECT
        u.user_id,
        u.signup_date,

        -- Stage 1: Signed up (all users)
        1 AS signed_up,

        -- Stage 2: Had at least one listening session
        CASE WHEN COUNT(DISTINCT s.session_id) >= 1 THEN 1 ELSE 0 END AS first_listen,

        -- Stage 3: Active in first 7 days (2+ sessions)
        CASE WHEN COUNT(DISTINCT CASE
            WHEN s.session_date <= u.signup_date + INTERVAL '7 days'
            THEN s.session_id END) >= 2 THEN 1 ELSE 0 END AS day7_active,

        -- Stage 4: Active in first 30 days (5+ sessions)
        CASE WHEN COUNT(DISTINCT CASE
            WHEN s.session_date <= u.signup_date + INTERVAL '30 days'
            THEN s.session_id END) >= 5 THEN 1 ELSE 0 END AS day30_active,

        -- Stage 5: Converted to premium
        CASE WHEN u.plan_type = 'premium' THEN 1 ELSE 0 END AS converted

    FROM users u
    LEFT JOIN sessions s ON u.user_id = s.user_id
    GROUP BY u.user_id, u.signup_date, u.plan_type
)
SELECT
    'Signed Up'         AS funnel_stage,
    1                   AS stage_order,
    COUNT(*)            AS users,
    100.0               AS pct_of_top,
    NULL                AS pct_of_prev
FROM funnel_stages

UNION ALL

SELECT
    'First Listen'      AS funnel_stage,
    2                   AS stage_order,
    SUM(first_listen)   AS users,
    ROUND(100.0 * SUM(first_listen) / COUNT(*), 1) AS pct_of_top,
    ROUND(100.0 * SUM(first_listen) / COUNT(*), 1) AS pct_of_prev
FROM funnel_stages

UNION ALL

SELECT
    'Day-7 Active'      AS funnel_stage,
    3                   AS stage_order,
    SUM(day7_active)    AS users,
    ROUND(100.0 * SUM(day7_active) / COUNT(*), 1) AS pct_of_top,
    ROUND(100.0 * SUM(day7_active) / NULLIF(SUM(first_listen), 0), 1) AS pct_of_prev
FROM funnel_stages

UNION ALL

SELECT
    'Day-30 Active'     AS funnel_stage,
    4                   AS stage_order,
    SUM(day30_active)   AS users,
    ROUND(100.0 * SUM(day30_active) / COUNT(*), 1) AS pct_of_top,
    ROUND(100.0 * SUM(day30_active) / NULLIF(SUM(day7_active), 0), 1) AS pct_of_prev
FROM funnel_stages

UNION ALL

SELECT
    'Converted to Premium' AS funnel_stage,
    5                      AS stage_order,
    SUM(converted)         AS users,
    ROUND(100.0 * SUM(converted) / COUNT(*), 1) AS pct_of_top,
    ROUND(100.0 * SUM(converted) / NULLIF(SUM(day30_active), 0), 1) AS pct_of_prev
FROM funnel_stages

ORDER BY stage_order;


-- 1.2 Funnel broken down by device type
-- Useful for identifying if mobile vs desktop users convert differently
WITH device_funnel AS (
    SELECT
        u.user_id,
        u.signup_date,
        u.plan_type,
        s.device_type,
        COUNT(DISTINCT s.session_id) AS total_sessions,
        COUNT(DISTINCT CASE
            WHEN s.session_date <= u.signup_date + INTERVAL '7 days'
            THEN s.session_id END) AS day7_sessions,
        COUNT(DISTINCT CASE
            WHEN s.session_date <= u.signup_date + INTERVAL '30 days'
            THEN s.session_id END) AS day30_sessions
    FROM users u
    LEFT JOIN sessions s ON u.user_id = s.user_id
    GROUP BY u.user_id, u.signup_date, u.plan_type, s.device_type
)
SELECT
    device_type,
    COUNT(DISTINCT user_id)                                                       AS total_users,
    SUM(CASE WHEN total_sessions >= 1 THEN 1 ELSE 0 END)                         AS first_listen,
    SUM(CASE WHEN day7_sessions >= 2 THEN 1 ELSE 0 END)                          AS day7_active,
    SUM(CASE WHEN day30_sessions >= 5 THEN 1 ELSE 0 END)                         AS day30_active,
    SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)                       AS converted,
    ROUND(100.0 * SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(DISTINCT user_id), 0), 2)                                 AS conversion_rate_pct
FROM device_funnel
GROUP BY device_type
ORDER BY conversion_rate_pct DESC;


-- =============================================================
-- SECTION 2: COHORT RETENTION ANALYSIS
-- Weekly cohort table showing % of users still active at week N
-- =============================================================

-- 2.1 Define user signup cohorts by week
WITH cohorts AS (
    SELECT
        user_id,
        DATE_TRUNC('week', signup_date) AS cohort_week
    FROM users
),

-- 2.2 Get all active weeks per user (a week is "active" if they had a session)
user_activity AS (
    SELECT
        s.user_id,
        DATE_TRUNC('week', s.session_date) AS activity_week
    FROM sessions s
    GROUP BY s.user_id, DATE_TRUNC('week', s.session_date)
),

-- 2.3 Join to get weeks since signup for each activity
cohort_activity AS (
    SELECT
        c.cohort_week,
        EXTRACT(EPOCH FROM (ua.activity_week - c.cohort_week)) / 604800 AS weeks_since_signup,
        COUNT(DISTINCT ua.user_id) AS active_users
    FROM cohorts c
    JOIN user_activity ua ON c.user_id = ua.user_id
    GROUP BY c.cohort_week, weeks_since_signup
),

-- 2.4 Get cohort sizes (week 0 = signup week)
cohort_sizes AS (
    SELECT
        cohort_week,
        COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_week
)

SELECT
    ca.cohort_week,
    cs.cohort_size,
    ca.weeks_since_signup::INT AS week_number,
    ca.active_users,
    ROUND(100.0 * ca.active_users / cs.cohort_size, 1) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_week = cs.cohort_week
WHERE ca.weeks_since_signup >= 0
  AND ca.weeks_since_signup <= 12
ORDER BY ca.cohort_week, ca.weeks_since_signup;


-- =============================================================
-- SECTION 3: BEHAVIORAL FEATURE ENGINEERING
-- Day-7 behavior signals used as features for the predictive model
-- These are the "leading indicators" of conversion
-- =============================================================

-- 3.1 Build the master behavioral feature table (one row per user)
CREATE TABLE IF NOT EXISTS user_day7_features AS
WITH day7_sessions AS (
    SELECT
        u.user_id,
        u.signup_date,
        u.plan_type,
        COUNT(DISTINCT s.session_id)                                  AS sessions_d7,
        SUM(s.session_duration_sec)                                   AS total_listen_sec_d7,
        AVG(s.session_duration_sec)                                   AS avg_session_sec_d7,
        COUNT(DISTINCT s.session_date)                                AS distinct_days_active_d7,
        COUNT(DISTINCT s.device_type)                                 AS distinct_devices_d7
    FROM users u
    LEFT JOIN sessions s
           ON u.user_id = s.user_id
          AND s.session_date BETWEEN u.signup_date AND u.signup_date + INTERVAL '7 days'
    GROUP BY u.user_id, u.signup_date, u.plan_type
),

day7_events AS (
    SELECT
        u.user_id,
        COUNT(CASE WHEN e.event_type = 'skip'           THEN 1 END)  AS skips_d7,
        COUNT(CASE WHEN e.event_type = 'like'           THEN 1 END)  AS likes_d7,
        COUNT(CASE WHEN e.event_type = 'playlist_save'  THEN 1 END)  AS playlist_saves_d7,
        COUNT(CASE WHEN e.event_type = 'share'          THEN 1 END)  AS shares_d7,
        COUNT(CASE WHEN e.event_type = 'search'         THEN 1 END)  AS searches_d7,
        COUNT(CASE WHEN e.event_type = 'upgrade_click'  THEN 1 END)  AS upgrade_clicks_d7,
        COUNT(CASE WHEN e.event_type = 'ad_view'        THEN 1 END)  AS ad_views_d7
    FROM users u
    LEFT JOIN sessions s
           ON u.user_id = s.user_id
          AND s.session_date BETWEEN u.signup_date AND u.signup_date + INTERVAL '7 days'
    LEFT JOIN events e ON s.session_id = e.session_id
    GROUP BY u.user_id
),

day7_tracks AS (
    SELECT
        u.user_id,
        COUNT(tp.play_id)                                             AS tracks_played_d7,
        SUM(CASE WHEN tp.completed = TRUE THEN 1 ELSE 0 END)         AS tracks_completed_d7,
        COUNT(DISTINCT tp.track_id)                                   AS unique_tracks_d7,
        COUNT(DISTINCT t.genre)                                       AS unique_genres_d7,
        AVG(t.energy)                                                 AS avg_track_energy,
        AVG(t.danceability)                                           AS avg_track_danceability,
        AVG(t.valence)                                                AS avg_track_valence
    FROM users u
    LEFT JOIN tracks_played tp
           ON u.user_id = tp.user_id
          AND tp.play_date BETWEEN u.signup_date AND u.signup_date + INTERVAL '7 days'
    LEFT JOIN tracks t ON tp.track_id = t.track_id
    GROUP BY u.user_id
)

SELECT
    ds.user_id,
    ds.plan_type,
    CASE WHEN ds.plan_type = 'premium' THEN 1 ELSE 0 END            AS converted,

    -- Session behavior
    ds.sessions_d7,
    ds.total_listen_sec_d7,
    ds.avg_session_sec_d7,
    ds.distinct_days_active_d7,
    ds.distinct_devices_d7,

    -- Engagement events
    de.skips_d7,
    de.likes_d7,
    de.playlist_saves_d7,
    de.shares_d7,
    de.searches_d7,
    de.upgrade_clicks_d7,
    de.ad_views_d7,

    -- Track behavior
    dt.tracks_played_d7,
    dt.tracks_completed_d7,
    dt.unique_tracks_d7,
    dt.unique_genres_d7,
    dt.avg_track_energy,
    dt.avg_track_danceability,
    dt.avg_track_valence,

    -- Derived ratios (strong predictive features)
    ROUND(
        CASE WHEN dt.tracks_played_d7 > 0
        THEN 100.0 * de.skips_d7 / dt.tracks_played_d7
        ELSE NULL END, 2
    )                                                                 AS skip_rate_pct,

    ROUND(
        CASE WHEN dt.tracks_played_d7 > 0
        THEN 100.0 * dt.tracks_completed_d7 / dt.tracks_played_d7
        ELSE NULL END, 2
    )                                                                 AS completion_rate_pct,

    ROUND(
        CASE WHEN de.ad_views_d7 > 0
        THEN 1.0 * de.skips_d7 / de.ad_views_d7
        ELSE NULL END, 2
    )                                                                 AS skips_per_ad

FROM day7_sessions ds
LEFT JOIN day7_events de ON ds.user_id = de.user_id
LEFT JOIN day7_tracks dt ON ds.user_id = dt.user_id;


-- =============================================================
-- SECTION 4: POWER USER SEGMENTATION
-- Identify your most engaged free users — highest-value conversion targets
-- =============================================================

-- 4.1 Segment free users into engagement tiers
WITH free_user_stats AS (
    SELECT
        u.user_id,
        COUNT(DISTINCT s.session_id)                                        AS total_sessions,
        SUM(s.session_duration_sec) / 3600.0                                AS total_hours,
        COUNT(DISTINCT s.session_date)                                      AS active_days,
        SUM(CASE WHEN e.event_type = 'playlist_save' THEN 1 ELSE 0 END)    AS playlist_saves,
        SUM(CASE WHEN e.event_type = 'like' THEN 1 ELSE 0 END)             AS likes,
        SUM(CASE WHEN e.event_type = 'upgrade_click' THEN 1 ELSE 0 END)    AS upgrade_clicks,
        SUM(CASE WHEN e.event_type = 'ad_view' THEN 1 ELSE 0 END)          AS ad_views
    FROM users u
    LEFT JOIN sessions s ON u.user_id = s.user_id
    LEFT JOIN events e ON s.session_id = e.session_id
    WHERE u.plan_type = 'free'
    GROUP BY u.user_id
),

scored AS (
    SELECT
        *,
        -- Simple composite engagement score (normalize in Python for the model)
        (   LEAST(total_sessions, 30) * 2
          + LEAST(total_hours, 20) * 3
          + LEAST(active_days, 14) * 2
          + LEAST(playlist_saves, 10) * 4
          + LEAST(likes, 20) * 1
          + upgrade_clicks * 10          -- Strong intent signal
        ) AS engagement_score
    FROM free_user_stats
)

SELECT
    user_id,
    total_sessions,
    ROUND(total_hours, 1)  AS total_hours,
    active_days,
    playlist_saves,
    likes,
    upgrade_clicks,
    ad_views,
    engagement_score,
    NTILE(4) OVER (ORDER BY engagement_score DESC) AS engagement_quartile,
    CASE NTILE(4) OVER (ORDER BY engagement_score DESC)
        WHEN 1 THEN 'Power User'
        WHEN 2 THEN 'Engaged'
        WHEN 3 THEN 'Casual'
        WHEN 4 THEN 'At Risk'
    END AS user_segment
FROM scored
ORDER BY engagement_score DESC;


-- 4.2 Conversion rate by engagement segment
-- Shows the business case for targeting power users with upgrade prompts
WITH segments AS (
    SELECT
        u.user_id,
        u.plan_type,
        COUNT(DISTINCT s.session_id)                                     AS total_sessions,
        SUM(s.session_duration_sec) / 3600.0                             AS total_hours,
        COUNT(DISTINCT s.session_date)                                   AS active_days
    FROM users u
    LEFT JOIN sessions s ON u.user_id = s.user_id
    GROUP BY u.user_id, u.plan_type
),
quartiled AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY total_sessions DESC) AS session_quartile
    FROM segments
)
SELECT
    session_quartile,
    CASE session_quartile
        WHEN 1 THEN 'Power User (top 25%)'
        WHEN 2 THEN 'Engaged (50–75%)'
        WHEN 3 THEN 'Casual (25–50%)'
        WHEN 4 THEN 'Low Activity (bottom 25%)'
    END AS segment_label,
    COUNT(*)                                                             AS total_users,
    SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)              AS premium_users,
    ROUND(AVG(total_hours), 1)                                          AS avg_hours,
    ROUND(AVG(active_days), 1)                                          AS avg_active_days,
    ROUND(100.0 * SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)
        / COUNT(*), 2)                                                  AS conversion_rate_pct
FROM quartiled
GROUP BY session_quartile
ORDER BY session_quartile;


-- =============================================================
-- SECTION 5: CHURN ANALYSIS
-- Identify premium subscribers at risk of downgrading
-- =============================================================

-- 5.1 Premium user engagement in last 30 days
-- Low engagement premium users are churn risks
WITH premium_recent AS (
    SELECT
        u.user_id,
        u.converted_date,
        COUNT(DISTINCT s.session_id)                                   AS sessions_last30,
        SUM(s.session_duration_sec) / 3600.0                          AS hours_last30,
        COUNT(DISTINCT s.session_date)                                 AS active_days_last30,
        COUNT(CASE WHEN e.event_type = 'playlist_save' THEN 1 END)    AS saves_last30,
        COUNT(CASE WHEN e.event_type = 'like'          THEN 1 END)    AS likes_last30
    FROM users u
    LEFT JOIN sessions s
           ON u.user_id = s.user_id
          AND s.session_date >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN events e ON s.session_id = e.session_id
    WHERE u.plan_type = 'premium'
    GROUP BY u.user_id, u.converted_date
)
SELECT
    user_id,
    converted_date,
    CURRENT_DATE - converted_date                                      AS days_as_premium,
    sessions_last30,
    ROUND(hours_last30, 1)                                            AS hours_last30,
    active_days_last30,
    saves_last30,
    likes_last30,
    CASE
        WHEN sessions_last30 = 0                          THEN 'Critical'
        WHEN sessions_last30 <= 2 OR active_days_last30 <= 3 THEN 'High'
        WHEN sessions_last30 <= 5 OR active_days_last30 <= 7 THEN 'Medium'
        ELSE 'Low'
    END AS churn_risk
FROM premium_recent
ORDER BY sessions_last30 ASC;


-- 5.2 Churn risk distribution summary
WITH premium_recent AS (
    SELECT
        u.user_id,
        COUNT(DISTINCT s.session_id) AS sessions_last30,
        COUNT(DISTINCT s.session_date) AS active_days_last30
    FROM users u
    LEFT JOIN sessions s
           ON u.user_id = s.user_id
          AND s.session_date >= CURRENT_DATE - INTERVAL '30 days'
    WHERE u.plan_type = 'premium'
    GROUP BY u.user_id
)
SELECT
    CASE
        WHEN sessions_last30 = 0                              THEN 'Critical'
        WHEN sessions_last30 <= 2 OR active_days_last30 <= 3  THEN 'High'
        WHEN sessions_last30 <= 5 OR active_days_last30 <= 7  THEN 'Medium'
        ELSE 'Low'
    END AS churn_risk,
    COUNT(*) AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_premium
FROM premium_recent
GROUP BY churn_risk
ORDER BY
    CASE churn_risk
        WHEN 'Critical' THEN 1
        WHEN 'High'     THEN 2
        WHEN 'Medium'   THEN 3
        WHEN 'Low'      THEN 4
    END;


-- =============================================================
-- SECTION 6: GENRE & CONTENT AFFINITY
-- Which music genres and audio features correlate with conversion?
-- =============================================================

-- 6.1 Genre preference by plan type
SELECT
    t.genre,
    u.plan_type,
    COUNT(DISTINCT u.user_id)                                AS user_count,
    COUNT(tp.play_id)                                        AS total_plays,
    ROUND(AVG(t.energy), 3)                                  AS avg_energy,
    ROUND(AVG(t.danceability), 3)                            AS avg_danceability,
    ROUND(AVG(t.valence), 3)                                 AS avg_valence,
    ROUND(100.0 * COUNT(tp.play_id) / SUM(COUNT(tp.play_id))
        OVER (PARTITION BY u.plan_type), 1)                  AS pct_of_plan_plays
FROM tracks_played tp
JOIN tracks t   ON tp.track_id = t.track_id
JOIN users u    ON tp.user_id  = u.user_id
GROUP BY t.genre, u.plan_type
ORDER BY u.plan_type, total_plays DESC;


-- 6.2 Audio feature profile: converters vs non-converters
-- Feed this into your Python notebook for visualization
SELECT
    CASE WHEN u.plan_type = 'premium' THEN 'Converted' ELSE 'Free' END AS user_type,
    ROUND(AVG(t.energy), 3)        AS avg_energy,
    ROUND(AVG(t.danceability), 3)  AS avg_danceability,
    ROUND(AVG(t.valence), 3)       AS avg_valence,
    ROUND(AVG(t.acousticness), 3)  AS avg_acousticness,
    ROUND(AVG(t.tempo), 1)         AS avg_tempo,
    ROUND(AVG(t.popularity), 1)    AS avg_popularity,
    COUNT(DISTINCT u.user_id)      AS user_count,
    COUNT(tp.play_id)              AS total_plays
FROM tracks_played tp
JOIN tracks t ON tp.track_id = t.track_id
JOIN users u  ON tp.user_id  = u.user_id
GROUP BY user_type;


-- =============================================================
-- SECTION 7: CONVERSION TIME ANALYSIS
-- How long does it take users to convert, and what triggers it?
-- =============================================================

-- 7.1 Days to conversion distribution
SELECT
    converted_date - signup_date                             AS days_to_convert,
    COUNT(*)                                                 AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_converters
FROM users
WHERE plan_type = 'premium'
  AND converted_date IS NOT NULL
GROUP BY days_to_convert
ORDER BY days_to_convert;


-- 7.2 Upgrade click to conversion funnel
-- What % of users who clicked upgrade actually converted, and how fast?
WITH clickers AS (
    SELECT
        u.user_id,
        u.plan_type,
        MIN(e.event_ts)                                    AS first_upgrade_click,
        u.converted_date,
        EXTRACT(EPOCH FROM (u.converted_date::TIMESTAMP - MIN(e.event_ts))) / 86400
                                                           AS days_click_to_convert
    FROM users u
    JOIN sessions s ON u.user_id = s.user_id
    JOIN events e   ON s.session_id = e.session_id
                    AND e.event_type = 'upgrade_click'
    GROUP BY u.user_id, u.plan_type, u.converted_date
)
SELECT
    COUNT(*)                                                              AS users_clicked_upgrade,
    SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)               AS converted,
    ROUND(100.0 * SUM(CASE WHEN plan_type = 'premium' THEN 1 ELSE 0 END)
        / COUNT(*), 1)                                                    AS click_to_convert_pct,
    ROUND(AVG(CASE WHEN plan_type = 'premium' THEN days_click_to_convert END), 1)
                                                                          AS avg_days_to_convert,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY CASE WHEN plan_type = 'premium' THEN days_click_to_convert END), 1)
                                                                          AS median_days_to_convert
FROM clickers;


-- =============================================================
-- SECTION 8: VALIDATION QUERIES
-- Quick sanity checks — run these first after loading data
-- =============================================================

-- 8.1 Row counts per table
SELECT 'users'         AS tbl, COUNT(*) AS rows FROM users        UNION ALL
SELECT 'sessions'      AS tbl, COUNT(*) AS rows FROM sessions      UNION ALL
SELECT 'events'        AS tbl, COUNT(*) AS rows FROM events        UNION ALL
SELECT 'tracks_played' AS tbl, COUNT(*) AS rows FROM tracks_played UNION ALL
SELECT 'tracks'        AS tbl, COUNT(*) AS rows FROM tracks;

-- 8.2 Plan type distribution
SELECT plan_type, COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM users GROUP BY plan_type;

-- 8.3 Date range check
SELECT
    MIN(signup_date)    AS earliest_signup,
    MAX(signup_date)    AS latest_signup,
    MIN(session_date)   AS earliest_session,
    MAX(session_date)   AS latest_session
FROM users
CROSS JOIN sessions LIMIT 1;

-- 8.4 Null check on key columns
SELECT
    SUM(CASE WHEN user_id IS NULL       THEN 1 ELSE 0 END) AS null_user_id,
    SUM(CASE WHEN signup_date IS NULL   THEN 1 ELSE 0 END) AS null_signup_date,
    SUM(CASE WHEN plan_type IS NULL     THEN 1 ELSE 0 END) AS null_plan_type
FROM users;

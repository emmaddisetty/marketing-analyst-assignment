-- ============================================================
-- Multi-Channel Advertising Data Model
-- Platforms: Facebook, Google Ads, TikTok
-- Period: January 2024
-- ============================================================

-- ============================================================
-- RAW PLATFORM TABLES
-- ============================================================

CREATE TABLE facebook_ads (
    id              SERIAL PRIMARY KEY,
    date            DATE          NOT NULL,
    campaign_id     VARCHAR(50)   NOT NULL,
    campaign_name   VARCHAR(200)  NOT NULL,
    ad_set_id       VARCHAR(50),
    ad_set_name     VARCHAR(200),
    impressions     BIGINT        DEFAULT 0,
    clicks          BIGINT        DEFAULT 0,
    spend           NUMERIC(12,2) DEFAULT 0,
    conversions     BIGINT        DEFAULT 0,
    video_views     BIGINT        DEFAULT 0,
    engagement_rate NUMERIC(8,4),
    reach           BIGINT        DEFAULT 0,
    frequency       NUMERIC(6,2),
    created_at      TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE google_ads (
    id                       SERIAL PRIMARY KEY,
    date                     DATE          NOT NULL,
    campaign_id              VARCHAR(50)   NOT NULL,
    campaign_name            VARCHAR(200)  NOT NULL,
    ad_group_id              VARCHAR(50),
    ad_group_name            VARCHAR(200),
    impressions              BIGINT        DEFAULT 0,
    clicks                   BIGINT        DEFAULT 0,
    cost                     NUMERIC(12,2) DEFAULT 0,  -- Google uses "cost"
    conversions              BIGINT        DEFAULT 0,
    conversion_value         NUMERIC(12,2) DEFAULT 0,
    ctr                      NUMERIC(8,4),
    avg_cpc                  NUMERIC(8,4),
    quality_score            SMALLINT,
    search_impression_share  NUMERIC(6,4),
    created_at               TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE tiktok_ads (
    id               SERIAL PRIMARY KEY,
    date             DATE          NOT NULL,
    campaign_id      VARCHAR(50)   NOT NULL,
    campaign_name    VARCHAR(200)  NOT NULL,
    adgroup_id       VARCHAR(50),
    adgroup_name     VARCHAR(200),
    impressions      BIGINT        DEFAULT 0,
    clicks           BIGINT        DEFAULT 0,
    cost             NUMERIC(12,2) DEFAULT 0,
    conversions      BIGINT        DEFAULT 0,
    video_views      BIGINT        DEFAULT 0,
    video_watch_25   BIGINT        DEFAULT 0,
    video_watch_50   BIGINT        DEFAULT 0,
    video_watch_75   BIGINT        DEFAULT 0,
    video_watch_100  BIGINT        DEFAULT 0,
    likes            BIGINT        DEFAULT 0,
    shares           BIGINT        DEFAULT 0,
    comments         BIGINT        DEFAULT 0,
    created_at       TIMESTAMP     DEFAULT NOW()
);

-- ============================================================
-- UNIFIED CROSS-CHANNEL TABLE
-- Normalises all three platforms into a single model
-- ============================================================

CREATE TABLE unified_ad_performance (
    id               SERIAL PRIMARY KEY,

    -- Common dimensions
    date             DATE         NOT NULL,
    platform         VARCHAR(20)  NOT NULL CHECK (platform IN ('Facebook', 'Google', 'TikTok')),
    campaign_id      VARCHAR(50)  NOT NULL,
    campaign_name    VARCHAR(200) NOT NULL,
    ad_group_id      VARCHAR(50),          -- ad_set / ad_group / adgroup
    ad_group_name    VARCHAR(200),

    -- Core volume metrics (present on all platforms)
    impressions      BIGINT       NOT NULL DEFAULT 0,
    clicks           BIGINT       NOT NULL DEFAULT 0,
    spend            NUMERIC(12,2) NOT NULL DEFAULT 0,
    conversions      BIGINT       NOT NULL DEFAULT 0,

    -- Video metric (Facebook + TikTok; NULL for Google non-video)
    video_views      BIGINT,

    -- Computed efficiency KPIs (stored for query convenience)
    ctr              NUMERIC(8,6),  -- clicks / impressions
    cpc              NUMERIC(10,4), -- spend / clicks
    cpa              NUMERIC(10,4), -- spend / conversions
    roas             NUMERIC(10,4), -- conversion_value / spend (Google only)

    -- Platform-specific extras preserved as JSONB
    platform_extras  JSONB,

    created_at       TIMESTAMP    DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX idx_unified_date     ON unified_ad_performance (date);
CREATE INDEX idx_unified_platform ON unified_ad_performance (platform);
CREATE INDEX idx_unified_campaign ON unified_ad_performance (campaign_name);
CREATE INDEX idx_unified_date_plt ON unified_ad_performance (date, platform);

-- ============================================================
-- ETL: POPULATE unified_ad_performance FROM RAW TABLES
-- ============================================================

-- Facebook
INSERT INTO unified_ad_performance (
    date, platform, campaign_id, campaign_name, ad_group_id, ad_group_name,
    impressions, clicks, spend, conversions, video_views,
    ctr, cpc, cpa, roas, platform_extras
)
SELECT
    date,
    'Facebook',
    campaign_id,
    campaign_name,
    ad_set_id,
    ad_set_name,
    impressions,
    clicks,
    spend,
    conversions,
    video_views,
    CASE WHEN impressions > 0 THEN clicks::NUMERIC / impressions ELSE NULL END,
    CASE WHEN clicks > 0     THEN spend / clicks                 ELSE NULL END,
    CASE WHEN conversions > 0 THEN spend / conversions           ELSE NULL END,
    NULL,  -- no conversion value on Facebook in this dataset
    jsonb_build_object(
        'reach',           reach,
        'frequency',       frequency,
        'engagement_rate', engagement_rate
    )
FROM facebook_ads;

-- Google Ads
INSERT INTO unified_ad_performance (
    date, platform, campaign_id, campaign_name, ad_group_id, ad_group_name,
    impressions, clicks, spend, conversions, video_views,
    ctr, cpc, cpa, roas, platform_extras
)
SELECT
    date,
    'Google',
    campaign_id,
    campaign_name,
    ad_group_id,
    ad_group_name,
    impressions,
    clicks,
    cost,           -- normalised to "spend"
    conversions,
    NULL,           -- no video_views for Google Search/Shopping
    ctr,
    avg_cpc,
    CASE WHEN conversions > 0 THEN cost / conversions       ELSE NULL END,
    CASE WHEN cost > 0        THEN conversion_value / cost  ELSE NULL END,
    jsonb_build_object(
        'conversion_value',        conversion_value,
        'quality_score',           quality_score,
        'search_impression_share', search_impression_share
    )
FROM google_ads;

-- TikTok
INSERT INTO unified_ad_performance (
    date, platform, campaign_id, campaign_name, ad_group_id, ad_group_name,
    impressions, clicks, spend, conversions, video_views,
    ctr, cpc, cpa, roas, platform_extras
)
SELECT
    date,
    'TikTok',
    campaign_id,
    campaign_name,
    adgroup_id,
    adgroup_name,
    impressions,
    clicks,
    cost,
    conversions,
    video_views,
    CASE WHEN impressions > 0 THEN clicks::NUMERIC / impressions ELSE NULL END,
    CASE WHEN clicks > 0     THEN cost / clicks                  ELSE NULL END,
    CASE WHEN conversions > 0 THEN cost / conversions            ELSE NULL END,
    NULL,
    jsonb_build_object(
        'video_watch_25',  video_watch_25,
        'video_watch_50',  video_watch_50,
        'video_watch_75',  video_watch_75,
        'video_watch_100', video_watch_100,
        'likes',           likes,
        'shares',          shares,
        'comments',        comments
    )
FROM tiktok_ads;

-- ============================================================
-- USEFUL ANALYTICAL VIEWS
-- ============================================================

-- Platform summary
CREATE VIEW vw_platform_summary AS
SELECT
    platform,
    SUM(impressions)                                  AS total_impressions,
    SUM(clicks)                                       AS total_clicks,
    SUM(spend)                                        AS total_spend,
    SUM(conversions)                                  AS total_conversions,
    SUM(video_views)                                  AS total_video_views,
    ROUND(SUM(clicks)::NUMERIC / NULLIF(SUM(impressions),0), 4) AS blended_ctr,
    ROUND(SUM(spend) / NULLIF(SUM(clicks),0), 4)     AS blended_cpc,
    ROUND(SUM(spend) / NULLIF(SUM(conversions),0), 4) AS blended_cpa,
    ROUND(SUM(spend) / SUM(spend) OVER () * 100, 2)  AS spend_share_pct
FROM unified_ad_performance
GROUP BY platform;

-- Daily trend
CREATE VIEW vw_daily_trend AS
SELECT
    date,
    platform,
    SUM(impressions)  AS impressions,
    SUM(clicks)       AS clicks,
    SUM(spend)        AS spend,
    SUM(conversions)  AS conversions,
    ROUND(SUM(clicks)::NUMERIC / NULLIF(SUM(impressions),0), 4) AS ctr,
    ROUND(SUM(spend) / NULLIF(SUM(conversions),0), 4)           AS cpa
FROM unified_ad_performance
GROUP BY date, platform
ORDER BY date, platform;

-- Campaign-level leaderboard
CREATE VIEW vw_campaign_leaderboard AS
SELECT
    platform,
    campaign_name,
    SUM(spend)        AS total_spend,
    SUM(conversions)  AS total_conversions,
    ROUND(SUM(spend) / NULLIF(SUM(conversions),0), 2) AS cpa,
    ROUND(SUM(clicks)::NUMERIC / NULLIF(SUM(impressions),0), 4) AS ctr
FROM unified_ad_performance
GROUP BY platform, campaign_name
ORDER BY total_conversions DESC;

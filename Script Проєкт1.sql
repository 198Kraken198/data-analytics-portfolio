WITH
-- 1) Підготовка користувачів: один раз чистимо "сиру" дату в тексті -> d
users_prep AS (
    SELECT
        user_id,
        promo_signup_flag,
        regexp_replace(
            split_part(trim(signup_datetime), ' ', 1),
            '[./]', '-', 'g'
        ) AS d
	FROM cohort_users_raw),
-- 2) Парсимо d у DATE (один CASE, без повторів regexp_replace/split_part/trim)
users_clean AS (
    SELECT
        user_id,
        promo_signup_flag,
        CASE
            WHEN d ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN to_date(d, 'DD-MM-YYYY')
            WHEN d ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN to_date(d, 'DD-MM-YY')
            ELSE NULL
        END AS signup_date
	FROM users_prep),
-- 3) Підготовка подій: так само один раз чистимо дату в тексті -> d
events_prep AS (
    SELECT
        event_id,
        user_id,
        event_type,
        revenue,
        regexp_replace(
            split_part(trim(event_datetime), ' ', 1),
            '[./]', '-', 'g'
        ) AS d
    FROM cohort_events_raw),
-- 4) Парсимо d у DATE
events_clean AS (
    SELECT
        event_id,
        user_id,
        event_type,
        revenue,
        CASE
            WHEN d ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN to_date(d, 'DD-MM-YYYY')
            WHEN d ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN to_date(d, 'DD-MM-YY')
            ELSE NULL
        END AS event_date
    FROM events_prep),
-- 5) Фільтр подій (як було, але вже над чистими полями)
events_filtered AS (
    SELECT *
    FROM events_clean
    WHERE
        event_date IS NOT NULL
        AND event_type IS NOT NULL
        AND event_type <> 'test_event'),
-- 6) Join + місячні поля + month_offset (спрощено)
joined_data AS (
    SELECT
        u.user_id,
        u.promo_signup_flag,
        date_trunc('month', u.signup_date)::date AS cohort_month,
        date_trunc('month', e.event_date)::date  AS activity_month,
        -- month_offset: різниця в "календарних місяцях"
        ((extract(year  from e.event_date)::int - extract(year  from u.signup_date)::int) * 12
          + (extract(month from e.event_date)::int - extract(month from u.signup_date)::int)) AS month_offset
    FROM users_clean u
    JOIN events_filtered e
      ON u.user_id = e.user_id
    WHERE u.signup_date IS NOT NULL)
-- 7) Фінальна агрегація
SELECT
    promo_signup_flag,
    cohort_month,
    month_offset,
    COUNT(DISTINCT user_id) AS users_total
FROM joined_data
WHERE
    activity_month >= DATE '2025-01-01'
    AND activity_month <  DATE '2025-07-01'
GROUP BY
    promo_signup_flag,
    cohort_month,
    month_offset
ORDER BY
    promo_signup_flag,
    cohort_month,
    month_offset;
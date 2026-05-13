WITH base AS (
    SELECT
        p.country_code,
        c.country_name,
        p.iana_code,
        p.population AS pop,
        tz.winter_offset AS winter_offset_min
    FROM population p
    LEFT JOIN countries c
        ON c.country_code = p.country_code
    LEFT JOIN timezones tz
        ON tz.iana_code = p.iana_code
    WHERE p.iana_code IS NOT NULL
      AND p.iana_code <> 'None'
      AND tz.winter_offset IS NOT NULL
),
by_offset AS (
    SELECT
        winter_offset_min,
        SUM(pop) AS pop_total
    FROM base
    GROUP BY winter_offset_min
),
top_tz AS (
    SELECT
        winter_offset_min,
        iana_code,
        pop,
        ROW_NUMBER() OVER (
            PARTITION BY winter_offset_min
            ORDER BY pop DESC
        ) AS rn
    FROM base
),
final AS (
    SELECT
        b.winter_offset_min,
        b.pop_total,
        t.iana_code AS representative_iana
    FROM by_offset b
    LEFT JOIN top_tz t
        ON t.winter_offset_min = b.winter_offset_min
       AND t.rn = 1
)
SELECT
    -- UTC offset у годинах (може бути дробовим)
    (winter_offset_min / 60.0) AS utc_offset_hours,

    -- Текстовий формат UTC±HH:MM
    printf(
        'UTC%s%02d:%02d',
        CASE WHEN winter_offset_min >= 0 THEN '+' ELSE '-' END,
        abs(winter_offset_min) / 60,
        abs(winter_offset_min) % 60
    ) AS utc_label,

    -- Репрезентативна IANA зона (напр. Asia/Tokyo)
    representative_iana,

    -- "Місто" з IANA (Tokyo з Asia/Tokyo)
    CASE
        WHEN instr(representative_iana, '/') > 0
            THEN replace(substr(representative_iana, instr(representative_iana, '/') + 1), '_', ' ')
        ELSE representative_iana
    END AS representative_city,

    -- Населення в млн для Excel-графіка
    ROUND(pop_total / 1000000.0, 1) AS population_mln

FROM final

-- Сортування зі стартом з UTC+09 (540 хв)
ORDER BY
    CASE WHEN winter_offset_min <= 540 THEN 0 ELSE 1 END,
    CASE WHEN winter_offset_min <= 540 THEN winter_offset_min END DESC,
    CASE WHEN winter_offset_min >  540 THEN winter_offset_min END ASC;

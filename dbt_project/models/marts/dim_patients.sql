{#- PII policy: no name, phone number or date of birth is exposed. Only initials,
    an unsalted SHA-256 of the digits-only phone (dedupe key; salt it if this were real PHI), and an age band. -#}
with patients as (
    select * from {{ ref('stg_patients') }}
),

appointment_stats as (
    select
        patient_id,
        count(*) as lifetime_appointments,
        min(cast(created_at as date)) as first_booking_date,
        max(appointment_date) as last_appointment_date
    from {{ ref('int_appointments_enriched') }}
    group by 1
),

base as (
    select
        p.patient_id,
        nullif(regexp_replace(initcap(coalesce(p.patient_name, '')), '[^A-Z]', ''), '') as patient_initials,
        sha2(nullif(regexp_replace(p.mobile_no, '[^0-9]', ''), ''), 256) as mobile_hash,
        case
            when lower(p.gender) like 'm%' then 'male'
            when lower(p.gender) like 'f%' then 'female'
            when p.gender is null then 'unknown'
            else 'other'
        end as gender,
        coalesce(
            p.age,
            -- DATEDIFF('year') counts calendar boundaries, so subtract 1 before the birthday
            case when p.date_of_birth is not null
                then datediff('year', p.date_of_birth, current_date())
                    - iff(dateadd('year', datediff('year', p.date_of_birth, current_date()), p.date_of_birth) > current_date(), 1, 0)
            end
        ) as age,
        cast(p.created_at as date) as registered_date,
        coalesce(s.lifetime_appointments, 0) as lifetime_appointments,
        s.first_booking_date,
        s.last_appointment_date
    from patients as p
    left join appointment_stats as s on p.patient_id = s.patient_id
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['patient_id']) }} as patient_key,
        patient_id,
        patient_initials,
        mobile_hash,
        gender,
        age,
        case
            when age is null then 'unknown'
            when age < 18 then '0-17'
            when age < 35 then '18-34'
            when age < 50 then '35-49'
            when age < 65 then '50-64'
            else '65+'
        end as age_band,
        registered_date,
        lifetime_appointments,
        first_booking_date,
        last_appointment_date,
        false as is_unknown
    from base
)

select * from final

union all

select
    {{ unknown_key() }},
    -1,
    null,
    null,
    'unknown',
    null,
    'unknown',
    null,
    0,
    null,
    null,
    true

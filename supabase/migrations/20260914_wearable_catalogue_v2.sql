-- Wearables Phase 0 — catalogue reconciliation (strategy 2026-09-14, decisions D1–D3).
-- Additive: no row is deleted, no id is renumbered. Zero rows carry the touched ids on CM OS at apply time
-- (checked 2026-09-14: wearable_daily / wearable_epoch have no 1000107/1000110–1000113 rows).
--
-- D2  1000110 / 1000112 / 1000113 collided BY NAME with 5041 SkinTemperature / 3300 BloodPressureDiastolic /
--     3301 BloodPressureSystolic. They become *Alt rows, deprecated, pointing at the canonical id; 1000111
--     BodyFatPercent becomes a deprecated alias of 5025 FatRatio. Adapters write the canonical ids only.
-- D3  1000107 BloodGlucose is STORED in mg/dL (vendor-native for Dexcom/Libre/HealthKit); the app displays
--     mmol/L (÷ 18.0182 at render). `details.original_unit` records what the source sent.
-- D1  Glucose summaries take 1000114–1000118 (the CGM pack's exact math); vendor-only scores start a new
--     block at 1000130 (the corpus had allocated 1000114–1000121 twice). CGM itself is parked (owner call
--     2026-09-14): the ids are reserved so nothing else takes them; no code writes them yet.

alter table public.wearable_data_types
  add column if not exists canonical_id integer references public.wearable_data_types(data_type_id),
  add column if not exists deprecated_at timestamptz;
comment on column public.wearable_data_types.canonical_id is 'Set = this id is a deprecated alias; write/read the canonical id instead.';

-- D2 — rename the colliding rows, deprecate, point at the canonical id.
update public.wearable_data_types set name = 'SkinTemperatureAlt', canonical_id = 5041, deprecated_at = now(),
  description = 'DEPRECATED alias of 5041 SkinTemperature (name collision fixed 2026-09-14). Adapters write 5041.'
  where data_type_id = 1000110;
update public.wearable_data_types set name = 'DiastolicBPAlt', canonical_id = 3300, deprecated_at = now(),
  description = 'DEPRECATED alias of 3300 BloodPressureDiastolic (name collision fixed 2026-09-14). Adapters write 3300.'
  where data_type_id = 1000112;
update public.wearable_data_types set name = 'SystolicBPAlt', canonical_id = 3301, deprecated_at = now(),
  description = 'DEPRECATED alias of 3301 BloodPressureSystolic (name collision fixed 2026-09-14). Adapters write 3301.'
  where data_type_id = 1000113;
update public.wearable_data_types set canonical_id = 5025, deprecated_at = now(),
  description = 'DEPRECATED alias of 5025 FatRatio (percent). Adapters write 5025.'
  where data_type_id = 1000111;

-- D3 — glucose stored in mg/dL.
update public.wearable_data_types set unit = 'mg/dL',
  description = 'Blood glucose (CGM or manual), STORED in mg/dL; displayed in mmol/L (÷ 18.0182). details.original_unit / sample_medium / source_delay_minutes carry provenance.',
  sources = array['AppleHealth','Dexcom','Libre','Fitbit']
  where data_type_id = 1000107;

-- D1 — glucose daily summaries 1000114–1000118 (reserved; CGM parked).
insert into public.wearable_data_types (data_type_id, name, category, granularity, unit, value_type, layer, description, sources) values
  (1000114, 'GlucoseMean',                  'Metabolic', 'daily', 'mg/dL',     'DOUBLE', 'raw', 'Daily mean glucose over the covered samples; suppressed below the coverage floor.', array['AppleHealth','Dexcom','Libre']),
  (1000115, 'GlucoseCV',                    'Metabolic', 'daily', 'percent',   'DOUBLE', 'raw', 'Daily glucose coefficient of variation (SD/mean × 100).', array['AppleHealth','Dexcom','Libre']),
  (1000116, 'GlucoseTimeInConfiguredRange', 'Metabolic', 'daily', 'percent',   'DOUBLE', 'raw', 'Share of covered samples inside the configured range (details.range_low_mgdl / range_high_mgdl).', array['AppleHealth','Dexcom','Libre']),
  (1000117, 'GlucoseCoverage',              'Metabolic', 'daily', 'percent',   'DOUBLE', 'raw', 'Share of the day with a glucose sample (gaps never interpolated).', array['AppleHealth','Dexcom','Libre']),
  (1000118, 'GlucoseRateOfChange',          'Metabolic', 'epoch', 'mg/dL/min', 'DOUBLE', 'raw', 'Glucose rate of change, only where the source exposes and permits it.', array['Dexcom','Libre'])
on conflict (data_type_id) do nothing;

-- D1 — vendor-only scores, new block from 1000130. Categorical values travel as value_type STRING (value_text).
insert into public.wearable_data_types (data_type_id, name, category, granularity, unit, value_type, layer, description, sources) values
  (1000130, 'PolarNightlyRechargeStatus',   'Vendor scores', 'daily', 'categorical',  'STRING', 'raw', 'Polar Nightly Recharge status (vendor categorical; never coerced to a number).', array['Polar']),
  (1000131, 'PolarSleepCharge',             'Vendor scores', 'daily', 'score',        'DOUBLE', 'raw', 'Polar Sleep Charge component (vendor scale).', array['Polar']),
  (1000132, 'PolarAnsStatus',               'Vendor scores', 'daily', 'score',        'DOUBLE', 'raw', 'Polar ANS status (vendor scale, -10…+10). Separate from 1000104 ANSCharge.', array['Polar']),
  (1000133, 'WHOOPSleepPerformance',        'Vendor scores', 'daily', 'percent',      'DOUBLE', 'raw', 'WHOOP sleep_performance_percentage — WHOOP-specific, not generic sleep quality.', array['Whoop']),
  (1000134, 'SuuntoRecoveryBalance',        'Vendor scores', 'daily', 'score',        'DOUBLE', 'raw', 'Suunto 24/7 recovery Balance (vendor scale; pin the scale on a live fixture first).', array['Suunto']),
  (1000135, 'SuuntoStressState',            'Vendor scores', 'epoch', 'categorical',  'STRING', 'raw', 'Suunto StressState (vendor categorical).', array['Suunto']),
  (1000136, 'UltrahumanMetabolicScore',     'Vendor scores', 'daily', 'score 0-100',  'DOUBLE', 'raw', 'Ultrahuman metabolic score (proprietary; reserved).', array['Ultrahuman']),
  (1000137, 'UltrahumanGlucoseVariability', 'Vendor scores', 'daily', 'score',        'DOUBLE', 'raw', 'Ultrahuman glucose variability (proprietary; reserved).', array['Ultrahuman']),
  (1000138, 'GlucoseTrendRate',             'Metabolic',     'epoch', 'categorical',  'STRING', 'raw', 'Glucose trend arrow as the source reports it (e.g. Dexcom flat/fortyFiveUp); categorical, never a derivative.', array['Dexcom','Libre'])
on conflict (data_type_id) do nothing;

-- The labelled views resolve a deprecated id to its canonical name so a stray alias row still labels correctly.
create or replace view public.wearable_daily_labeled with (security_invoker = true) as
select d.patient_id, d.day, d.data_source_id, d.data_type_id,
       coalesce(c.name, t.name, d.data_type_name) as metric,
       coalesce(c.category, t.category) as category,
       coalesce(c.layer, t.layer) as layer,
       coalesce(c.unit, t.unit, d.value_type) as unit,
       d.value, d.value_text, d.value_type, d.timezone_offset, d.details, d.recorded_at, d.ingested_at
from public.wearable_daily d
left join public.wearable_data_types t on t.data_type_id = d.data_type_id
left join public.wearable_data_types c on c.data_type_id = t.canonical_id;

create or replace view public.wearable_epoch_labeled with (security_invoker = true) as
select e.patient_id, e.start_ts, e.end_ts, e.data_source_id, e.data_type_id,
       coalesce(c.name, t.name, e.data_type_name) as metric,
       coalesce(c.category, t.category) as category,
       coalesce(c.layer, t.layer) as layer,
       coalesce(c.unit, t.unit, e.value_type) as unit,
       e.value, e.value_text, e.value_type, e.timezone_offset, e.details, e.ingested_at
from public.wearable_epoch e
left join public.wearable_data_types t on t.data_type_id = e.data_type_id
left join public.wearable_data_types c on c.data_type_id = t.canonical_id;

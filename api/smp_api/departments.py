"""Section order and titles copied from the bot's department_registry.DEPARTMENT_SEED."""

from __future__ import annotations

DEPARTMENT_SEED: list[tuple[str, str]] = [
    ("cardiology", "🩺 КАРДИОЛОГИЯ"),
    ("gynecology", "🚺 ГИНЕКОЛОГИЯ"),
    ("ent_ophthal_stomat", "👂 ЛОР / ОФТАЛЬМОЛОГИЯ / СТОМАТОЛОГИЯ"),
    ("neurology", "🧠 НЕВРОЛОГИЯ"),
    ("pediatrics", "👶 ПЕДИАТРИЯ"),
    ("psychiatry", "🧠 ПСИХИАТРИЯ"),
    ("pulmonology", "🫁 ПУЛЬМОНОЛОГИЯ"),
    ("infectious_diseases", "🦠 ИНФЕКЦИОННЫЕ ЗАБОЛЕВАНИЯ"),
    ("therapy", "💊 ТЕРАПИЯ"),
    ("toxicology", "☣️ ТОКСИКОЛОГИЯ"),
    ("trauma", "🦴 ТРАВМА"),
    ("urology", "🚽 УРОЛОГИЯ"),
    ("surgery", "🔪 ХИРУРГИЯ"),
    ("shock_coma", "⚠️ ШОКИ / КОМЫ (неотложные)"),
    ("neonatal_resuscitation", "🩺 РЕАНИМАЦИЯ НОВОРОЖДЕННЫХ"),
]

CONTINUOUS_SECTION_SLUG = "neonatal_resuscitation"
SHOCK_SECTION_SLUG = "shock_coma"
FINGERPRINT_META_KEY = "medical_source_fp"

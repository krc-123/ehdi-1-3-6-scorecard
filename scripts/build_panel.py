"""Build the state-year EHDI panel from CDC's annual Hearing Screening and
Follow-up Survey (HSFS) tables, 2015 to 2022.

Input: the archived CDC HTML tables (see download_tables.sh), one file per
year and table: 02 screening, 04 screened by 1 month, 06 diagnostics,
07 diagnosed by 3 months, 09 early intervention, 10 EI by 6 months.

Output: data/ehdi_panel.csv (one row per jurisdiction-year) and
data/ehdi_panel_dictionary.csv.

Column names shift a little from year to year (footnote symbols, "Hearing
Loss" became "Permanent Hearing Loss" in 2020 and "Deaf or Hard of
Hearing" in 2022), so each variable is located by a regular expression
over the flattened header rather than by position.

Usage: python3 build_panel.py <tables_dir> <out_dir>
"""
import glob, io, os, re, sys
import pandas as pd

tables_dir, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)

def flat(c):
    if isinstance(c, tuple):
        parts = [re.sub(r"\s+", " ", str(x)).strip() for x in c]
        parts = [p for p in parts if not p.startswith("Unnamed")]
        return " :: ".join(dict.fromkeys(parts))
    return re.sub(r"\s+", " ", str(c)).strip()

def load(year, key):
    files = glob.glob(os.path.join(tables_dir, f"{year}_{key}-*.html"))
    if not files:
        return None
    html = open(files[0], encoding="utf-8", errors="ignore").read()
    t = max(pd.read_html(io.StringIO(html)), key=lambda x: x.shape[0])
    t.columns = [flat(c) for c in t.columns]
    t = t.rename(columns={t.columns[0]: "jurisdiction"})
    # CDC appends footnote markers to jurisdiction names (Georgia^, OklahomaΒ, West Virginia*±).
    # Keep letters, spaces and periods only, then strip.
    t["jurisdiction"] = t["jurisdiction"].astype(str).str.replace(r"[^A-Za-z .]", "", regex=True).str.strip()
    t = t[~t["jurisdiction"].str.match(r"(?i)^(total|u\.?s\.?|united states|national|nan)")]
    return t

def pick(t, pattern, exclude=None):
    """Return the first column whose flattened header matches pattern."""
    for c in t.columns:
        if re.search(pattern, c, re.I) and not (exclude and re.search(exclude, c, re.I)):
            return c
    return None

def num(x):
    if pd.isna(x):
        return None
    s = str(x).strip().replace(",", "").replace("%", "")
    s = re.sub(r"[\*†‡§¶Ω∞+]+$", "", s)
    if s in ("", "-", "--", "N/A", "NA", "n/a", "NR", ".", "nan"):
        return None
    try:
        return float(s)
    except ValueError:
        return None

# variable name -> (table key, header regex, exclude regex)
SPEC = {
    "births_ehdi":            ("02", r"Births Reported to EHDI", None),
    "births_vital":           ("02", r"Births According to Vital", None),
    "screened":               ("02", r"^Total Screened$", None),
    "pct_screened_cdc":       ("02", r"^Percent Screened(\*|†)?$|Percent Screened \(Based on # of EHDI", None),
    "screen_lfu_n":           ("02", r"(Overall )?Number LFU/LTD", None),
    "screened_by_1mo":        ("04", r"Total Screened Before 1 Month", None),
    "pct_screened_by_1mo_of_screened_cdc": ("04", r"Percent Screened by 1 Month", None),
    "not_pass":               ("06", r"^Total Not Pass", None),
    "no_hearing_loss":        ("06", r"^(No Hearing Loss|Typical Hearing)", r"Percent"),
    "hearing_loss":           ("06", r"^(Hearing Loss|Permanent Hearing Loss|Deaf or Hard of Hearing)", r"Percent"),
    "prevalence_per_1000_cdc": ("06", r"Prevalence per 1,000", None),
    "dx_lfu_n":               ("06", r"(Overall )?Number LFU/LTD", None),
    "hl_dx_by_3mo":           ("07", r"^(Hearing Loss|Permanent Hearing Loss|D/HH) Diagnosed Before 3 Months", None),
    "total_dx":               ("07", r"^Total Diagnosed \(", None),
    "total_dx_by_3mo":        ("07", r"^Total Diagnosed Before 3 Months", None),
    "ei_enrolled":            ("09", r"^Total Enrolled in EI", None),
    "pct_ei_enrolled_cdc":    ("09", r"^Percent Enrolled in EI", None),
    "ei_part_c":              ("09", r"^Total Enrolled in Part C", None),
    "ei_lfu_n":               ("09", r"(Overall )?Number LFU/LTD", None),
    "ei_referrals_part_c":    ("10", r"Total Referrals to Part C", None),
    "ei_by_6mo":              ("10", r"Total Enrolled in EI before 6 Months", None),
}

rows = []
missing = []
for year in range(2015, 2023):
    tabs = {k: load(year, k) for k in ["02", "04", "06", "07", "09", "10"]}
    juris = set()
    for t in tabs.values():
        if t is not None:
            juris |= set(t["jurisdiction"])
    for j in sorted(juris):
        rec = {"jurisdiction": j, "year": year}
        for var, (key, pat, exc) in SPEC.items():
            t = tabs[key]
            if t is None:
                rec[var] = None; continue
            col = pick(t, pat, exc)
            if col is None:
                missing.append((year, key, var)); rec[var] = None; continue
            m = t.loc[t["jurisdiction"] == j, col]
            rec[var] = num(m.iloc[0]) if len(m) else None
        rows.append(rec)

df = pd.DataFrame(rows)

# A reported count of zero infants reaching a benchmark, in a state that enrolled
# or diagnosed dozens, is a documentation gap (age at enrollment not recorded), not a
# real zero. Treat those as not reported so they do not read as 0 percent.
df["ei_by_6mo_reported"] = ~((df["ei_by_6mo"] == 0) & (df["ei_enrolled"] >= 5))
df.loc[~df["ei_by_6mo_reported"], "ei_by_6mo"] = None
df["hl_dx_by_3mo_reported"] = ~((df["hl_dx_by_3mo"] == 0) & (df["hearing_loss"] >= 5))
df.loc[~df["hl_dx_by_3mo_reported"], "hl_dx_by_3mo"] = None
df["small_n"] = df["hearing_loss"] < 20

# Derived, consistently defined across years
def ratio(a, b):
    return (df[a] / df[b] * 100).where(df[b] > 0)
df["pct_screened"]                 = ratio("screened", "births_ehdi")
df["pct_screened_by_1mo_of_births"] = ratio("screened_by_1mo", "births_ehdi")
df["pct_screened_by_1mo_of_screened"] = ratio("screened_by_1mo", "screened")
df["pct_not_pass"]                 = ratio("not_pass", "screened")
df["prevalence_per_1000_screened"] = (df["hearing_loss"] / df["screened"] * 1000).where(df["screened"] > 0)
df["pct_hl_dx_by_3mo"]             = ratio("hl_dx_by_3mo", "hearing_loss")
df["pct_dx_lfu"]                   = ratio("dx_lfu_n", "not_pass")
df["pct_ei_enrolled"]              = ratio("ei_enrolled", "hearing_loss")
df["pct_ei_by_6mo_of_hl"]          = ratio("ei_by_6mo", "hearing_loss")
df["pct_ei_by_6mo_of_enrolled"]    = ratio("ei_by_6mo", "ei_enrolled")
df["pct_ei_lfu"]                   = ratio("ei_lfu_n", "hearing_loss")

STATES = {"Alabama":"AL","Alaska":"AK","Arizona":"AZ","Arkansas":"AR","California":"CA","Colorado":"CO","Connecticut":"CT","Delaware":"DE","District of Columbia":"DC","Florida":"FL","Georgia":"GA","Hawaii":"HI","Idaho":"ID","Illinois":"IL","Indiana":"IN","Iowa":"IA","Kansas":"KS","Kentucky":"KY","Louisiana":"LA","Maine":"ME","Maryland":"MD","Massachusetts":"MA","Michigan":"MI","Minnesota":"MN","Mississippi":"MS","Missouri":"MO","Montana":"MT","Nebraska":"NE","Nevada":"NV","New Hampshire":"NH","New Jersey":"NJ","New Mexico":"NM","New York":"NY","North Carolina":"NC","North Dakota":"ND","Ohio":"OH","Oklahoma":"OK","Oregon":"OR","Pennsylvania":"PA","Rhode Island":"RI","South Carolina":"SC","South Dakota":"SD","Tennessee":"TN","Texas":"TX","Utah":"UT","Vermont":"VT","Virginia":"VA","Washington":"WA","West Virginia":"WV","Wisconsin":"WI","Wyoming":"WY"}
df["state"] = df["jurisdiction"].map(STATES)
df["is_state_or_dc"] = df["state"].notna()
df = df.sort_values(["jurisdiction", "year"])
cols = ["jurisdiction", "state", "is_state_or_dc", "year"] + [c for c in df.columns if c not in ("jurisdiction", "state", "is_state_or_dc", "year")]
df[cols].to_csv(os.path.join(out_dir, "ehdi_panel.csv"), index=False)

dictionary = [
    ("jurisdiction", "State or territory name as printed by CDC"),
    ("state", "Two-letter postal code for the 50 states and DC; blank for territories"),
    ("year", "Birth cohort year (HSFS survey year)"),
    ("births_ehdi", "Total occurrent births reported to the EHDI program (table 02)"),
    ("births_vital", "Births according to vital records (table 02)"),
    ("screened", "Infants with a documented hearing screen (table 02)"),
    ("pct_screened_cdc", "CDC's percent screened, based on EHDI births (table 02)"),
    ("screen_lfu_n", "Infants with no documented screen counted as lost to follow-up or documentation (table 02)"),
    ("screened_by_1mo", "Infants screened before 1 month of age, pass and not pass (table 04)"),
    ("pct_screened_by_1mo_of_screened_cdc", "CDC's percent screened by 1 month among screened infants (table 04)"),
    ("not_pass", "Infants not passing the final screen (table 06)"),
    ("no_hearing_loss", "Infants not passing who were diagnosed with no hearing loss / typical hearing (table 06)"),
    ("hearing_loss", "Infants diagnosed with permanent hearing loss, called deaf or hard of hearing from 2022 (table 06)"),
    ("prevalence_per_1000_cdc", "CDC's prevalence per 1,000 (per screened to 2020, per births from 2021; table 06)"),
    ("dx_lfu_n", "Infants not passing with no documented diagnosis counted as lost to follow-up or documentation (table 06)"),
    ("hl_dx_by_3mo", "Infants with hearing loss diagnosed before 3 months of age (table 07)"),
    ("total_dx", "All infants with a documented diagnosis, hearing loss or not (table 07)"),
    ("total_dx_by_3mo", "All infants diagnosed before 3 months, hearing loss or not (table 07)"),
    ("ei_enrolled", "Infants with hearing loss enrolled in early intervention, Part C or non-Part C (table 09)"),
    ("pct_ei_enrolled_cdc", "CDC's percent enrolled in EI among those with hearing loss (table 09)"),
    ("ei_part_c", "Enrolled in Part C EI (table 09)"),
    ("ei_lfu_n", "Infants with hearing loss and no EI counted as lost to follow-up or documentation (table 09)"),
    ("ei_referrals_part_c", "Referrals to Part C (table 10)"),
    ("ei_by_6mo", "Infants with hearing loss enrolled in EI before 6 months of age (table 10)"),
    ("ei_by_6mo_reported", "FALSE where the state reported zero infants in EI by 6 months despite enrolling 5 or more; treated as not reported"),
    ("hl_dx_by_3mo_reported", "FALSE where the state reported zero diagnosed by 3 months despite 5 or more diagnoses; treated as not reported"),
    ("small_n", "TRUE where fewer than 20 infants were diagnosed; percentages are unstable"),
    ("pct_screened", "screened / births_ehdi * 100 (computed)"),
    ("pct_screened_by_1mo_of_births", "screened_by_1mo / births_ehdi * 100 (computed; the '1' in 1-3-6)"),
    ("pct_screened_by_1mo_of_screened", "screened_by_1mo / screened * 100 (computed)"),
    ("pct_not_pass", "not_pass / screened * 100 (computed)"),
    ("prevalence_per_1000_screened", "hearing_loss / screened * 1000 (computed, consistent across years)"),
    ("pct_hl_dx_by_3mo", "hl_dx_by_3mo / hearing_loss * 100 (computed; the '3' in 1-3-6)"),
    ("pct_dx_lfu", "dx_lfu_n / not_pass * 100 (computed; diagnostic loss to follow-up)"),
    ("pct_ei_enrolled", "ei_enrolled / hearing_loss * 100 (computed)"),
    ("pct_ei_by_6mo_of_hl", "ei_by_6mo / hearing_loss * 100 (computed; the '6' in 1-3-6, among all infants with hearing loss)"),
    ("pct_ei_by_6mo_of_enrolled", "ei_by_6mo / ei_enrolled * 100 (computed; among those who enrolled)"),
    ("pct_ei_lfu", "ei_lfu_n / hearing_loss * 100 (computed; intervention loss to follow-up)"),
]
pd.DataFrame(dictionary, columns=["variable", "definition"]).to_csv(os.path.join(out_dir, "ehdi_panel_dictionary.csv"), index=False)

print(f"rows {len(df)}, jurisdictions {df.jurisdiction.nunique()}, years {df.year.min()}-{df.year.max()}")
if missing:
    print("columns not found:", sorted(set(missing)))

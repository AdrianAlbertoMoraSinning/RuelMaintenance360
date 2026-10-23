# Peace River mix catalogue · 0.3.7

Loaded 79 existing RUEL mix references into Production & Dispatch → Customers & setup → Products, scoped only to Peace River Concrete Plant. They can be selected in the Mix design field while creating an order.

Source: user-uploaded Ruel_Concrete_Master_Summary_Prices.xlsm, Library ID libfile_ae1831d18c04819187be3eba6da16b7e. The MASTER SUMMARY contains 79 unique codes. Each was cross-checked against the corresponding mix sheet's B4 (code), B5 (description), and B6 (status). All 79 are Active in that source. Names and codes are catalogue references; no new technical approval or batch-control integration is implied.

For 32C1GU20A, the summary appends /32C1GU20A to the description. The imported description uses the individual sheet's original description: 32MPa, 5-8%, Exterior Concrete. The source summary variant remains in the extraction manifest for traceability. Similar but distinct references, including 30C1-14 / 30C1-14mm and 32MPA14 / 32MPA14mm, remain separate because their source codes differ.

Product display is code — description, unit m³, kind product. Reference code is stored independently and unique case-insensitively within the business unit. The source location is retained per product. New products may also provide an optional reference code. Existing three uncoded products and their order snapshots were preserved without renaming or deleting them.

The seed is idempotent by code and exact catalogue name. Replaying it left 79 coded references and 82 total products. Prices, dosages, formulas, maintenance stock and production consumption were not imported or altered.

Extraction manifest: data/catalogue/peace_river_mix_references.json. The source workbook was read without executing macros or editing it. Data migration resolves the unit by code CONC-PR rather than hardcoded IDs. Existing RLS and manager-only catalogue command permissions remain in place.

# Checkpoints from trained frameworks

The saved fixtures in `tests/fixtures/frameworks` come from eight small models
trained on deterministic, locally generated data (256 rows, four features,
seed 1729). Each ensemble has four trees/boosting rounds, with maximum depth
three. No training data or model downloads are needed.

| Fixture | Framework version | Coverage |
| --- | --- | --- |
| XGBoost regression | 2.1.4 CPU | float32 thresholds/leaves, missing routing, Hessian/gain statistics |
| LightGBM binary classifier | 4.6.0 | float64, actual categorical splits, missing routing, counts and sigmoid |
| CatBoost regression | 1.2.8 | Numeric symmetric trees, `>` comparisons, missing routing, nontrivial scale/bias |
| sklearn RandomForestRegressor | 1.6.1 | Two regression targets, vector leaves and averaging |
| sklearn RandomForestClassifier | 1.6.1 | Three classes, probability vectors and averaging |
| sklearn ExtraTreesClassifier | 1.6.1 | Two targets with unequal class counts `[2, 3]`, padded vector leaves |
| sklearn GradientBoostingClassifier | 1.6.1 | Binary sigmoid, nonzero base margin and statistics |
| sklearn HistGradientBoostingRegressor | 1.6.1 | Missing routing, histogram splits and counts |

All checkpoints are serialized by **Treelite 4.6.1**. They expand framework
coverage, not the set of verified Treelite producer versions. Exact dependency
artifacts are pinned in `pixi.lock`; the framework manifest records versions,
conversion routes, checkpoint SHA256 hashes and upstream JSON field dumps.

## Run the checks

```sh
# Native Mojo only; includes both synthetic and trained-model fixtures.
pixi run test
# Only the eight trained-model native tests:
pixi run test-frameworks

# Read saved files with Balsa, then verify them with the pinned Treelite oracle.
pixi install -e oracle --locked
pixi run -e oracle framework-interop

# Retrain and compare every saved framework artifact byte-for-byte.
pixi install -e frameworks --locked
pixi run -e frameworks framework-fixtures-check
# Intentionally replace the saved framework artifacts:
pixi run -e frameworks framework-fixtures
```

The checks have three layers:

1. Native tests inspect known metadata, split thresholds/operators, missing
   directions, category payloads, vector leaves and statistics independently of
   Balsa's encoder. Both typed and automatically dispatched loading must
   roundtrip every checkpoint byte-for-byte.
2. The interoperability script invokes the compiled Balsa CLI, verifies exact
   bytes, loads the output with Treelite, compares its fields with the recorded
   upstream dump, then reserializes with Treelite and checks exact bytes again.
3. Regeneration retrains all models and checks Treelite's converted predictions
   against source-framework predictions on independent probe rows. This verifies
   fixture conversion; it does not add prediction execution to Balsa. Tolerances
   are recorded per fixture: 1e-6 for XGBoost, 1e-12 for the others (both relative
   and absolute). It then compares all generated artifacts to the checked-in set.

The default environment needs none of the training libraries. The `oracle`
environment needs only Treelite and its dependencies. The `frameworks`
environment adds the training libraries. Existing synthetic fixtures and their
regeneration check remain separate.

## CatBoost conversion is deliberately narrow

Treelite 4.6.1 does not provide a CatBoost frontend. The test-only
`catboost_numeric_model` helper expands exported numeric oblivious trees through
Treelite's builder. It follows CatBoost's split-to-leaf bit ordering, maps NaN
routing, and folds model scale into leaves while retaining bias as the base
score. The canonical exported tree/feature/scale fields are saved alongside the
checkpoint; volatile training metadata is omitted.

The adapter is verified against CatBoost on independent inputs, missing values,
exact split borders and adjacent float32 values, with a non-unit scale and
nonzero bias. It rejects categorical/CTR, text/embedding, asymmetric and
non-scalar models. It is **not a general CatBoost importer**, and this fixture
does not establish support for those model kinds.

References: [Treelite frontend/builder interfaces](https://treelite.readthedocs.io/en/latest/treelite-api.html),
[CatBoost JSON export](https://catboost.ai/docs/en/features/export-model-to-json),
and [CatBoost's numeric JSON tutorial](https://github.com/catboost/catboost/blob/master/catboost/tutorials/model_analysis/model_export_as_json_tutorial.ipynb).

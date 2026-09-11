"""Train small framework models and save reproducible Treelite v4 checkpoints.

Python/frameworks are test-only. The CatBoost adapter deliberately supports only
numeric, symmetric, scalar-regression trees; this is not a production importer.
"""

import argparse
import hashlib
import importlib.metadata
import json
import tempfile
from pathlib import Path

import catboost
import lightgbm as lgb
import numpy as np
import treelite
import treelite.frontend
import treelite.gtil
import treelite.sklearn
import xgboost as xgb
from sklearn.ensemble import (
    ExtraTreesClassifier,
    GradientBoostingClassifier,
    HistGradientBoostingRegressor,
    RandomForestClassifier,
    RandomForestRegressor,
)
from treelite.model_builder import Metadata, ModelBuilder, PostProcessorFunc, TreeAnnotation

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/frameworks"
VERSIONS = {
    "treelite": "4.6.1", "numpy": "2.2.6", "xgboost-cpu": "2.1.4",
    "lightgbm": "4.6.0", "catboost": "1.2.8", "scikit-learn": "1.6.1",
}
SEED = 1729


def catboost_numeric_model(data, num_feature):
    """Expand numeric oblivious trees using CatBoost's split-to-leaf bit order.

    Reference: catboost/tutorials/model_analysis/model_export_as_json_tutorial.ipynb
    Split i sets bit i of the leaf index when feature > border. Treelite's left
    branch is the true branch. Thresholds and leaves retain float64 storage.
    """
    info = data["features_info"]
    if any(info.get(key) for key in ("categorical_features", "ctrs", "text_features",
                                     "embedding_features")):
        raise ValueError("Fixture adapter supports numeric features only")
    trees = data.get("oblivious_trees")
    if not trees:
        raise ValueError("Fixture adapter requires symmetric trees")
    scale, bias = data["scale_and_bias"]
    if len(bias) != 1:
        raise ValueError("Fixture adapter requires scalar regression")
    features = {f["feature_index"]: f for f in info["float_features"]}
    builder = ModelBuilder(
        threshold_type="float64", leaf_output_type="float64",
        metadata=Metadata(num_feature=num_feature, task_type="kRegressor",
                          average_tree_output=False, num_target=1, num_class=[1],
                          leaf_vector_shape=(1, 1)),
        tree_annotation=TreeAnnotation(num_tree=len(trees), target_id=[0] * len(trees),
                                       class_id=[0] * len(trees)),
        postprocessor=PostProcessorFunc(name="identity"), base_scores=bias,
    )
    for tree in trees:
        splits = tree.get("splits") or []
        if any(split["split_type"] != "FloatFeature" for split in splits):
            raise ValueError("Fixture adapter supports FloatFeature splits only")
        if len(tree["leaf_values"]) != 2 ** len(splits):
            raise ValueError("Fixture adapter requires scalar symmetric leaves")
        builder.start_tree()

        def visit(node, level, leaf_index):
            builder.start_node(node)
            if level == len(splits):
                builder.leaf(scale * tree["leaf_values"][leaf_index])
            else:
                split = splits[level]
                feature = features[split["float_feature_index"]]
                treatment = feature["nan_value_treatment"]
                if treatment not in ("AsIs", "AsFalse", "AsTrue"):
                    raise ValueError(f"Unknown NaN treatment: {treatment}")
                builder.numerical_test(
                    feature_id=feature["flat_feature_index"], threshold=split["border"],
                    default_left=treatment == "AsTrue", opname=">",
                    left_child_key=2 * node + 1, right_child_key=2 * node + 2,
                )
            builder.end_node()
            if level < len(splits):
                visit(2 * node + 1, level + 1, leaf_index | (1 << level))
                visit(2 * node + 2, level + 1, leaf_index)

        visit(0, 0, 0)
        builder.end_tree()
    return builder.commit()


def trained_cases(directory):
    rng = np.random.default_rng(SEED)
    x = rng.normal(size=(256, 4)).astype(np.float32)
    y = (2 * x[:, 0] - x[:, 1] + 0.5 * x[:, 2] ** 2).astype(np.float64)
    multi_y = np.column_stack((y, x[:, 1] - 3 * x[:, 3]))
    cls = np.digitize(y, [-1.0, 1.0])
    binary = (y > 0).astype(np.int32)
    probe = rng.normal(size=(64, 4)).astype(np.float32)
    missing = x.copy()
    missing[::7, 0] = np.nan
    missing_probe = probe.copy()
    missing_probe[::5, 0] = np.nan

    booster = xgb.XGBRegressor(n_estimators=4, max_depth=3, learning_rate=0.2,
                               n_jobs=1, random_state=SEED, tree_method="hist")
    booster.fit(missing, y)
    yield ("xgboost_regression", treelite.frontend.from_xgboost(booster.get_booster()),
           "xgboost.XGBRegressor", "treelite.frontend.from_xgboost",
           missing_probe, booster.predict(missing_probe)[:, None, None], 1e-6)

    categorical = x.copy()
    categorical[:, 0] = rng.integers(0, 4, size=len(x))
    labels = np.isin(categorical[:, 0], [0, 2]).astype(np.int32)
    categorical_probe = probe.copy()
    categorical_probe[:, 0] = np.arange(len(probe)) % 4
    categorical_probe[::9, 0] = np.nan
    booster = lgb.train(
        dict(objective="binary", num_leaves=4, max_depth=3, learning_rate=0.2,
             min_data_in_leaf=5, min_data_per_group=1, cat_smooth=0,
             cat_l2=0, max_cat_to_onehot=1, verbosity=-1, num_threads=1,
             deterministic=True, force_col_wise=True, seed=SEED),
        lgb.Dataset(categorical, label=labels, categorical_feature=[0]), num_boost_round=4,
    )
    yield ("lightgbm_categorical", treelite.frontend.from_lightgbm(booster),
           "lightgbm.Booster", "treelite.frontend.from_lightgbm",
           categorical_probe, booster.predict(categorical_probe)[:, None, None], 1e-12)

    booster = catboost.CatBoostRegressor(iterations=4, depth=3, learning_rate=0.2,
                                         random_seed=SEED, thread_count=1, verbose=False,
                                         allow_writing_files=False, nan_mode="Min")
    booster.fit(missing, y)
    # Exercise both factors, rather than relying on the default scale=1.
    booster.set_scale_and_bias(1.25, -0.75)
    with tempfile.TemporaryDirectory(prefix="balsa-catboost-") as temporary:
        path = Path(temporary) / "model.json"
        booster.save_model(path, format="json")
        original = json.loads(path.read_text())
    # Retain semantic source fields, excluding timestamps/GUIDs/training logs.
    source = {key: original[key] for key in ("features_info", "oblivious_trees", "scale_and_bias")}
    (directory / "catboost-numeric-source.json").write_text(json.dumps(source, indent=2) + "\n")
    converted = catboost_numeric_model(source, num_feature=4)
    # Include exact borders and adjacent representable inputs in adapter checks.
    boundary_rows = []
    for feature in source["features_info"]["float_features"]:
        for border in feature["borders"]:
            for value in (np.nextafter(np.float32(border), np.float32(-np.inf)),
                          np.float32(border),
                          np.nextafter(np.float32(border), np.float32(np.inf))):
                row = np.zeros(4, dtype=np.float32)
                row[feature["flat_feature_index"]] = value
                boundary_rows.append(row)
    cat_probe = np.vstack((missing_probe, np.array(boundary_rows, dtype=np.float32)))
    yield ("catboost_numeric_regression", converted, "catboost.CatBoostRegressor",
           "test-only numeric symmetric-tree adapter via treelite.model_builder",
           cat_probe, booster.predict(cat_probe)[:, None, None], 1e-12)

    cases = [
        ("sklearn_rf_multioutput_regression", RandomForestRegressor(
            n_estimators=4, max_depth=3, n_jobs=1, random_state=SEED), x, multi_y, probe),
        ("sklearn_rf_multiclass", RandomForestClassifier(
            n_estimators=4, max_depth=3, n_jobs=1, random_state=SEED), x, cls, probe),
        ("sklearn_extra_multioutput_classification", ExtraTreesClassifier(
            n_estimators=4, max_depth=3, n_jobs=1, random_state=SEED),
         x, np.column_stack((binary, cls)), probe),
        ("sklearn_gradient_binary", GradientBoostingClassifier(
            n_estimators=4, max_depth=3, random_state=SEED), x, binary, probe),
        ("sklearn_hist_missing_regression", HistGradientBoostingRegressor(
            max_iter=4, max_depth=3, min_samples_leaf=8, random_state=SEED),
         missing, y, missing_probe),
    ]
    for name, estimator, train_x, train_y, test_x in cases:
        estimator.fit(train_x, train_y)
        if name == "sklearn_gradient_binary":
            expected = estimator.predict_proba(test_x)[:, 1, None, None]
        elif hasattr(estimator, "predict_proba"):
            probabilities = estimator.predict_proba(test_x)
            if isinstance(probabilities, list):
                expected = np.zeros((len(test_x), len(probabilities),
                                     max(p.shape[1] for p in probabilities)))
                for target, values in enumerate(probabilities):
                    expected[:, target, :values.shape[1]] = values
            else:
                expected = probabilities[:, None, :]
        else:
            expected = estimator.predict(test_x).reshape(len(test_x), -1, 1)
        yield (name, treelite.sklearn.import_model(estimator),
               f"sklearn.ensemble.{type(estimator).__name__}", "treelite.sklearn.import_model",
               test_x, expected, 1e-12)


def generate(directory):
    versions = {name: importlib.metadata.version(name) for name in VERSIONS}
    assert versions == VERSIONS, versions
    directory.mkdir(parents=True, exist_ok=True)
    records = []
    for name, model, framework_class, conversion, probe, expected, tolerance in trained_cases(directory):
        actual = treelite.gtil.predict(model, probe, nthread=1)
        np.testing.assert_allclose(actual, expected, rtol=tolerance, atol=tolerance,
                                   err_msg=f"Source conversion: {name}")
        data = model.serialize_bytes()
        restored = treelite.Model.deserialize_bytes(data)
        assert restored.serialize_bytes() == data, name
        fields = json.loads(model.dump_as_json(pretty_print=False))
        if name == "lightgbm_categorical":
            assert any("category_list" in node for tree in fields["trees"] for node in tree["nodes"])
        (directory / f"{name}.tl").write_bytes(data)
        records.append(dict(
            name=name, framework_class=framework_class, conversion=conversion,
            sha256=hashlib.sha256(data).hexdigest(), bytes=len(data),
            probe_rows=len(probe), conversion_tolerance=tolerance,
            metadata=fields,
        ))
        print(f"Generated {name}: {len(data)} bytes; source predictions agree")
    source = directory / "catboost-numeric-source.json"
    manifest = dict(versions=versions, seed=SEED, platform="linux-64", byteorder="little",
                    command="pixi run -e frameworks framework-fixtures",
                    source_artifacts={source.name: hashlib.sha256(source.read_bytes()).hexdigest()},
                    cases=records)
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=FIXTURES)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="balsa-frameworks-") as temporary:
            generated = Path(temporary)
            generate(generated)
            expected = {p.name for p in args.output.iterdir() if p.is_file()}
            actual = {p.name for p in generated.iterdir()}
            assert actual == expected, actual ^ expected
            for name in actual:
                assert (generated / name).read_bytes() == (args.output / name).read_bytes(), name
        print("PASS: framework fixtures regenerate byte-for-byte")
    else:
        generate(args.output)


if __name__ == "__main__":
    main()

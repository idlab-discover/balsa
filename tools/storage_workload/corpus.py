"""Train distinct larger forests on seeded generated data; no tree replication."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import time

import numpy as np
from sklearn.ensemble import ExtraTreesClassifier, RandomForestRegressor
import treelite
import treelite.sklearn
import xgboost as xgb


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=False)
    rng = np.random.default_rng(20260918)
    x = rng.normal(size=(30000, 24)).astype(np.float32)
    signal = 3 * np.sin(x[:, 0] * x[:, 1]) + x[:, 2] ** 2 - 2 * x[:, 3]
    y = signal + rng.normal(size=len(x))
    targets = np.stack([y, x[:, 4] * x[:, 5] + rng.normal(size=len(x))], axis=1)
    labels = np.digitize(y, np.quantile(y, [.25, .5, .75]))
    configs = [
        ("rf_multioutput", RandomForestRegressor(n_estimators=128, max_leaf_nodes=1024,
            max_features=.7, n_jobs=4, random_state=101), targets),
        ("extra_multiclass", ExtraTreesClassifier(n_estimators=128, max_leaf_nodes=1024,
            n_jobs=4, random_state=102), labels),
        ("xgboost_regression", xgb.XGBRegressor(n_estimators=384, max_depth=8,
            tree_method="hist", n_jobs=4, random_state=103), y),
    ]
    cases = []
    for name, estimator, target in configs:
        start = time.monotonic()
        estimator.fit(x, target)
        model = (treelite.frontend.from_xgboost(estimator.get_booster())
                 if name.startswith("xgboost") else treelite.sklearn.import_model(estimator))
        path = args.directory / (name + ".tl")
        model.serialize(path)
        # Independently compare framework predictions with upstream checkpoint inference.
        prediction = treelite.gtil.predict(model, x[:100], nthread=1)
        expected = estimator.predict_proba(x[:100]) if name == "extra_multiclass" else estimator.predict(x[:100])
        np.testing.assert_allclose(prediction.reshape(expected.shape), expected, rtol=2e-5, atol=2e-5)
        nodes = sum(int(model.get_tree_accessor(i).get_field("num_nodes")[0]) for i in range(model.num_tree))
        data = path.read_bytes()
        cases.append(dict(name=name, file=path.name, trees=model.num_tree, nodes=nodes,
            bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
            dtype={2: "float32", 3: "float64"}[data[12]],
            estimator=type(estimator).__name__, parameters=estimator.get_params(),
            training_seconds=time.monotonic()-start, prediction_check_rows=100))
        print(name, model.num_tree, nodes, len(data), flush=True)
        (args.directory / "manifest.json").write_text(json.dumps(dict(
            seed=20260918, rows=30000, features=24,
            description="Distinct trained trees on generated data; not production datasets",
            versions={n: importlib.metadata.version(n) for n in ["numpy", "scikit-learn", "xgboost-cpu", "treelite"]},
            generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), cases=cases), indent=2) + "\n")


if __name__ == "__main__":
    main()

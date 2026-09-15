# 0.2.0 public API benchmark

Median microseconds per call; five shuffled batches by default. Consuming decode
includes the input copy and result destruction. Checked runs use one worker.
Output compares copying packed bytes with serializing editable fields. File I/O,
first-use latency, conversion and peak memory are excluded. Local regression
evidence only; large forests repeat trained trees.

| Input | Default decode | Packed off | Packed on | Editable off | Editable on | Default output | Editable output |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| catboost_numeric_regression.tl | 0.959 | 0.950 | 3.366 | 2.635 | 3.623 | 0.124 | 1.559 |
| lightgbm_categorical.tl | 0.940 | 0.934 | 3.135 | 2.983 | 3.662 | 0.100 | 1.567 |
| sklearn_extra_multioutput_classification.tl | 0.991 | 0.988 | 3.617 | 3.252 | 4.500 | 0.141 | 1.643 |
| sklearn_gradient_binary.tl | 0.959 | 0.959 | 3.736 | 3.231 | 4.388 | 0.127 | 1.664 |
| sklearn_hist_missing_regression.tl | 0.962 | 0.961 | 3.637 | 2.994 | 4.081 | 0.124 | 1.637 |
| sklearn_rf_multiclass.tl | 0.997 | 0.992 | 4.643 | 3.152 | 4.179 | 0.139 | 1.549 |
| sklearn_rf_multioutput_regression.tl | 0.974 | 0.970 | 3.709 | 3.299 | 4.359 | 0.138 | 1.684 |
| sklearn_rf_multioutput_regression_x16.tl | 10.413 | 10.548 | 44.601 | 47.864 | 62.360 | 1.577 | 23.449 |
| sklearn_rf_multioutput_regression_x1667.tl | 1122.787 | 1134.043 | 4695.358 | 7607.154 | 10119.382 | 191.342 | 2502.338 |
| xgboost_regression.tl | 0.948 | 0.954 | 3.713 | 3.056 | 4.186 | 0.119 | 1.598 |
| xgboost_regression_x16.tl | 10.101 | 10.098 | 44.344 | 44.052 | 59.709 | 1.250 | 22.462 |
| xgboost_regression_x1667.tl | 1067.377 | 1076.261 | 4716.865 | 6865.425 | 7863.271 | 146.319 | 2361.079 |

Compiler: Mojo 1.0.0 (ed45d567). CPU affinity: 0.

Reproduce with `pixi run -e benchmark python tools/benchmark_defaults.py OUTPUT FILE...`.
Raw samples and source/input hashes are in OUTPUT/results.json.

# Synthetic shape supplement

Median microseconds per call; five shuffled batches by default. Consuming decode
includes the input copy and result destruction. Checked runs use one worker.
Output compares copying packed bytes with serializing editable fields. File I/O,
first-use latency, conversion and peak memory are excluded. Local regression
evidence only; large forests repeat trained trees.

| Input | Default decode | Packed off | Packed on | Editable off | Editable on | Default output | Editable output |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| leaves.tl | 585.558 | 585.583 | 1715.798 | 2644.226 | 2835.686 | 27.654 | 1206.507 |
| uneven.tl | 659.306 | 654.806 | 2678.546 | 2732.617 | 3651.975 | 76.367 | 1306.468 |
| few-large.tl | 138.239 | 136.227 | 1764.813 | 407.475 | 1814.070 | 109.636 | 171.456 |
| dominant.tl | 638.101 | 631.103 | 2604.265 | 2712.708 | 3692.479 | 77.345 | 1267.142 |

Compiler: Mojo 1.0.0 (ed45d567). CPU affinity: 0.

Reproduce with `pixi run -e benchmark python tools/benchmark_defaults.py OUTPUT FILE...`.
Raw samples and source/input hashes are in OUTPUT/results.json.

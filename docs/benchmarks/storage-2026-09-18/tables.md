# Storage workload measurements

Library revision: `b933b55f409d155190b3df25e0763ddcbd66fe56`. Host: `rgbcore`.

Seven fresh-process samples per cell by default; table reports medians. See build.json for contracts.

| Case | Engine | Operation | Checked | Operation ms | Process wall ms | Peak RSS MiB |
| --- | --- | --- | --- | ---: | ---: | ---: |
| extra_multiclass | balsa | convert | 0 | 4.062 | 18.630 | 70.43 |
| extra_multiclass | balsa | convert | 1 | 8.280 | 22.890 | 70.40 |
| extra_multiclass | native | load | None | 16.494 | 22.182 | 31.61 |
| extra_multiclass | balsa | load-editable | 0 | 7.835 | 18.721 | 70.44 |
| extra_multiclass | balsa | load-editable | 1 | 12.090 | 23.098 | 70.34 |
| extra_multiclass | balsa | load-packed | 0 | 3.853 | 14.435 | 42.19 |
| extra_multiclass | balsa | load-packed | 1 | 9.295 | 20.017 | 42.02 |
| extra_multiclass | native | roundtrip | None | 32.728 | 38.602 | 31.55 |
| extra_multiclass | balsa | roundtrip-editable | 0 | 16.956 | 27.785 | 92.53 |
| extra_multiclass | balsa | roundtrip-editable | 1 | 26.209 | 37.261 | 92.41 |
| extra_multiclass | balsa | roundtrip-packed | 0 | 9.901 | 20.383 | 42.24 |
| extra_multiclass | balsa | roundtrip-packed | 1 | 15.034 | 25.622 | 42.23 |
| extra_multiclass | native | save | None | 16.517 | 39.056 | 31.73 |
| extra_multiclass | balsa | save-editable | 0 | 9.303 | 27.829 | 92.48 |
| extra_multiclass | balsa | save-editable | 1 | 13.812 | 37.179 | 92.49 |
| extra_multiclass | balsa | save-packed | 0 | 6.104 | 20.420 | 42.20 |
| extra_multiclass | balsa | save-packed | 1 | 5.737 | 25.480 | 42.25 |
| rf_multioutput | balsa | convert | 0 | 3.761 | 18.305 | 66.35 |
| rf_multioutput | balsa | convert | 1 | 7.821 | 22.336 | 66.37 |
| rf_multioutput | native | load | None | 15.477 | 21.120 | 29.67 |
| rf_multioutput | balsa | load-editable | 0 | 7.014 | 17.951 | 66.35 |
| rf_multioutput | balsa | load-editable | 1 | 11.445 | 22.393 | 66.34 |
| rf_multioutput | balsa | load-packed | 0 | 3.601 | 14.201 | 40.03 |
| rf_multioutput | balsa | load-packed | 1 | 8.766 | 19.306 | 40.22 |
| rf_multioutput | native | roundtrip | None | 31.087 | 36.757 | 29.65 |
| rf_multioutput | balsa | roundtrip-editable | 0 | 16.002 | 26.883 | 88.41 |
| rf_multioutput | balsa | roundtrip-editable | 1 | 24.149 | 35.095 | 88.47 |
| rf_multioutput | balsa | roundtrip-packed | 0 | 9.177 | 19.783 | 40.21 |
| rf_multioutput | balsa | roundtrip-packed | 1 | 14.092 | 24.833 | 40.20 |
| rf_multioutput | native | save | None | 15.923 | 37.271 | 29.73 |
| rf_multioutput | balsa | save-editable | 0 | 8.632 | 26.363 | 88.44 |
| rf_multioutput | balsa | save-editable | 1 | 12.996 | 35.174 | 88.44 |
| rf_multioutput | balsa | save-packed | 0 | 5.627 | 19.778 | 40.24 |
| rf_multioutput | balsa | save-packed | 1 | 5.316 | 24.375 | 40.20 |
| xgboost_regression | balsa | convert | 0 | 2.009 | 15.082 | 40.55 |
| xgboost_regression | balsa | convert | 1 | 4.256 | 16.663 | 40.52 |
| xgboost_regression | native | load | None | 9.295 | 14.263 | 18.93 |
| xgboost_regression | balsa | load-editable | 0 | 3.709 | 14.619 | 40.55 |
| xgboost_regression | balsa | load-editable | 1 | 5.954 | 16.884 | 40.55 |
| xgboost_regression | balsa | load-packed | 0 | 1.792 | 12.260 | 26.52 |
| xgboost_regression | balsa | load-packed | 1 | 4.747 | 15.345 | 26.52 |
| xgboost_regression | native | roundtrip | None | 18.152 | 23.134 | 19.12 |
| xgboost_regression | balsa | roundtrip-editable | 0 | 7.826 | 18.681 | 52.25 |
| xgboost_regression | balsa | roundtrip-editable | 1 | 12.027 | 22.848 | 52.26 |
| xgboost_regression | balsa | roundtrip-packed | 0 | 4.373 | 14.669 | 26.46 |
| xgboost_regression | balsa | roundtrip-packed | 1 | 7.111 | 17.330 | 26.50 |
| xgboost_regression | native | save | None | 8.902 | 23.227 | 18.98 |
| xgboost_regression | balsa | save-editable | 0 | 4.113 | 18.558 | 52.27 |
| xgboost_regression | balsa | save-editable | 1 | 6.204 | 22.917 | 52.28 |
| xgboost_regression | balsa | save-packed | 0 | 2.609 | 14.831 | 26.50 |
| xgboost_regression | balsa | save-packed | 1 | 2.567 | 17.546 | 26.50 |

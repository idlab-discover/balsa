Generated from the audited 2026-09-15 run. See the [report](final-report.md) for interpretation, contracts, and limitations.

# Controlled codec results

All times are microseconds per call (µs); lower is better.

## Corpus

| Case | Dtype | Trees | Nodes | Bytes |
|---|---|---:|---:|---:|
| catboost_numeric_regression | float64 | 4 | 60 | 4726 |
| lightgbm_categorical | float64 | 4 | 26 | 3053 |
| sklearn_extra_multioutput_classification | float64 | 4 | 54 | 7247 |
| sklearn_gradient_binary | float64 | 4 | 60 | 6345 |
| sklearn_hist_missing_regression | float64 | 4 | 60 | 5806 |
| sklearn_rf_multiclass | float64 | 4 | 50 | 6111 |
| sklearn_rf_multioutput_regression | float64 | 4 | 60 | 6870 |
| sklearn_rf_multioutput_regression_x16 | float64 | 64 | 960 | 107790 |
| sklearn_rf_multioutput_regression_x1667 | float64 | 6668 | 100020 | 11215718 |
| xgboost_regression | float32 | 4 | 60 | 5326 |
| xgboost_regression_x16 | float32 | 64 | 960 | 83266 |
| xgboost_regression_x1667 | float32 | 6668 | 100020 | 8661862 |
| leaves | float32 | 4096 | 4096 | 1003650 |
| uneven | float32 | 4096 | 69120 | 4644994 |
| few-large | float32 | 128 | 130944 | 7357186 |
| dominant | float32 | 4096 | 69630 | 4673554 |

## Directional summary versus native Treelite

Counts require an interval excluding one and agreement in both run orders.
Packed-copy remains a different operation contract; do not combine it with editable encode.

| Corpus | Operation | Engine | Faster | Slower | Overlap/inconsistent | Incomplete |
|---|---|---|---:|---:|---:|---:|
| framework/scaled (12) | decode | balsa-borrow-off | 11 | 1 | 0 | 0 |
| framework/scaled (12) | decode | balsa-borrow-on | 0 | 12 | 0 | 0 |
| framework/scaled (12) | decode | balsa-off | 11 | 1 | 0 | 0 |
| framework/scaled (12) | decode | balsa-on | 0 | 12 | 0 | 0 |
| framework/scaled (12) | decode | packed-off | 12 | 0 | 0 | 0 |
| framework/scaled (12) | decode | packed-on | 6 | 6 | 0 | 0 |
| framework/scaled (12) | decode | treelite-python | 0 | 12 | 0 | 0 |
| framework/scaled (12) | encode | balsa-off | 12 | 0 | 0 | 0 |
| framework/scaled (12) | encode | balsa-on | 2 | 10 | 0 | 0 |
| framework/scaled (12) | encode | packed-copy | 12 | 0 | 0 | 0 |
| framework/scaled (12) | encode | treelite-python | 4 | 8 | 0 | 0 |
| synthetic shapes (4) | decode | balsa-borrow-off | 4 | 0 | 0 | 0 |
| synthetic shapes (4) | decode | balsa-borrow-on | 1 | 3 | 0 | 0 |
| synthetic shapes (4) | decode | balsa-off | 4 | 0 | 0 | 0 |
| synthetic shapes (4) | decode | balsa-on | 1 | 3 | 0 | 0 |
| synthetic shapes (4) | decode | packed-off | 4 | 0 | 0 | 0 |
| synthetic shapes (4) | decode | packed-on | 3 | 1 | 0 | 0 |
| synthetic shapes (4) | decode | treelite-python | 0 | 3 | 1 | 0 |
| synthetic shapes (4) | encode | balsa-off | 4 | 0 | 0 | 0 |
| synthetic shapes (4) | encode | balsa-on | 0 | 3 | 1 | 0 |
| synthetic shapes (4) | encode | packed-copy | 4 | 0 | 0 | 0 |
| synthetic shapes (4) | encode | treelite-python | 2 | 0 | 2 | 0 |

## Decode: treelite-native, treelite-python, balsa-on, balsa-off, balsa-borrow-on, balsa-borrow-off

| Case | treelite-native | treelite-python | balsa-on | balsa-off | balsa-borrow-on | balsa-borrow-off |
|---|---:|---:|---:|---:|---:|---:|
| catboost_numeric_regression | 3.124 | 5.818 | 3.725 | 2.782 | 3.684 | 2.667 |
| dominant | 3076.640 | 7072.879 | 3688.883 | 2767.856 | 3712.184 | 2702.970 |
| few-large | 577.813 | 1190.159 | 1826.819 | 371.429 | 1660.025 | 244.951 |
| leaves | 4609.797 | 4584.201 | 2864.507 | 2674.392 | 2858.006 | 2630.030 |
| lightgbm_categorical | 3.538 | 5.943 | 3.781 | 3.201 | 3.704 | 3.123 |
| sklearn_extra_multioutput_classification | 3.911 | 6.388 | 4.422 | 3.375 | 4.289 | 3.255 |
| sklearn_gradient_binary | 3.842 | 6.307 | 4.482 | 3.317 | 4.378 | 3.203 |
| sklearn_hist_missing_regression | 3.590 | 6.129 | 4.258 | 3.313 | 4.198 | 3.032 |
| sklearn_rf_multiclass | 3.844 | 6.417 | 4.341 | 3.278 | 4.230 | 3.184 |
| sklearn_rf_multioutput_regression | 3.906 | 6.386 | 4.448 | 3.374 | 4.402 | 3.257 |
| sklearn_rf_multioutput_regression_x16 | 60.782 | 66.800 | 63.819 | 48.863 | 61.765 | 46.822 |
| sklearn_rf_multioutput_regression_x1667 | 8094.120 | 8833.288 | 10127.667 | 7618.418 | 8722.158 | 6867.707 |
| uneven | 3024.753 | 3357.586 | 3673.746 | 2756.605 | 3549.264 | 2634.045 |
| xgboost_regression | 3.454 | 5.944 | 4.272 | 3.125 | 4.173 | 3.087 |
| xgboost_regression_x16 | 54.504 | 62.087 | 60.560 | 44.739 | 60.060 | 43.690 |
| xgboost_regression_x1667 | 5898.960 | 6815.877 | 7973.494 | 6446.532 | 7731.304 | 6223.602 |

## Encode: treelite-native, treelite-python, balsa-on, balsa-off

| Case | treelite-native | treelite-python | balsa-on | balsa-off |
|---|---:|---:|---:|---:|
| catboost_numeric_regression | 1.998 | 3.129 | 2.602 | 1.582 |
| dominant | 2152.041 | 1999.250 | 2205.823 | 1330.522 |
| few-large | 1425.926 | 1436.076 | 1574.520 | 182.586 |
| leaves | 1363.272 | 1261.827 | 1440.617 | 1246.768 |
| lightgbm_categorical | 2.036 | 3.166 | 2.184 | 1.564 |
| sklearn_extra_multioutput_classification | 2.254 | 3.421 | 2.661 | 1.685 |
| sklearn_gradient_binary | 2.205 | 3.360 | 2.827 | 1.663 |
| sklearn_hist_missing_regression | 2.131 | 3.265 | 2.747 | 1.622 |
| sklearn_rf_multiclass | 2.212 | 3.394 | 2.631 | 1.555 |
| sklearn_rf_multioutput_regression | 2.247 | 3.610 | 2.847 | 1.669 |
| sklearn_rf_multioutput_regression_x16 | 32.243 | 31.567 | 39.265 | 23.974 |
| sklearn_rf_multioutput_regression_x1667 | 5173.697 | 4926.307 | 4177.657 | 2501.272 |
| uneven | 2030.733 | 1962.898 | 2226.669 | 1304.744 |
| xgboost_regression | 2.090 | 3.227 | 2.739 | 1.635 |
| xgboost_regression_x16 | 28.536 | 27.849 | 38.742 | 23.574 |
| xgboost_regression_x1667 | 4489.850 | 4176.919 | 4065.472 | 2500.559 |

## Decode: treelite-native, balsa-on, packed-on, balsa-off, packed-off

| Case | treelite-native | balsa-on | packed-on | balsa-off | packed-off |
|---|---:|---:|---:|---:|---:|
| catboost_numeric_regression | 3.124 | 3.725 | 3.732 | 2.782 | 0.956 |
| dominant | 3076.640 | 3688.883 | 2700.225 | 2767.856 | 656.059 |
| few-large | 577.813 | 1826.819 | 1709.156 | 371.429 | 145.301 |
| leaves | 4609.797 | 2864.507 | 1796.009 | 2674.392 | 604.729 |
| lightgbm_categorical | 3.538 | 3.781 | 3.362 | 3.201 | 0.939 |
| sklearn_extra_multioutput_classification | 3.911 | 4.422 | 3.879 | 3.375 | 1.008 |
| sklearn_gradient_binary | 3.842 | 4.482 | 4.025 | 3.317 | 0.966 |
| sklearn_hist_missing_regression | 3.590 | 4.258 | 3.891 | 3.313 | 0.970 |
| sklearn_rf_multiclass | 3.844 | 4.341 | 4.831 | 3.278 | 0.989 |
| sklearn_rf_multioutput_regression | 3.906 | 4.448 | 3.933 | 3.374 | 0.967 |
| sklearn_rf_multioutput_regression_x16 | 60.782 | 63.819 | 48.021 | 48.863 | 10.774 |
| sklearn_rf_multioutput_regression_x1667 | 8094.120 | 10127.667 | 5151.828 | 7618.418 | 1170.481 |
| uneven | 3024.753 | 3673.746 | 2663.479 | 2756.605 | 672.462 |
| xgboost_regression | 3.454 | 4.272 | 3.821 | 3.125 | 0.958 |
| xgboost_regression_x16 | 54.504 | 60.560 | 46.315 | 44.739 | 10.543 |
| xgboost_regression_x1667 | 5898.960 | 7973.494 | 4936.515 | 6446.532 | 1138.927 |

## Encode: treelite-native, balsa-off, packed-copy

| Case | treelite-native | balsa-off | packed-copy |
|---|---:|---:|---:|
| catboost_numeric_regression | 1.998 | 1.582 | 0.084 |
| dominant | 2152.041 | 1330.522 | 74.272 |
| few-large | 1425.926 | 182.586 | 113.190 |
| leaves | 1363.272 | 1246.768 | 16.532 |
| lightgbm_categorical | 2.036 | 1.564 | 0.063 |
| sklearn_extra_multioutput_classification | 2.254 | 1.685 | 0.100 |
| sklearn_gradient_binary | 2.205 | 1.663 | 0.090 |
| sklearn_hist_missing_regression | 2.131 | 1.622 | 0.088 |
| sklearn_rf_multiclass | 2.212 | 1.555 | 0.097 |
| sklearn_rf_multioutput_regression | 2.247 | 1.669 | 0.101 |
| sklearn_rf_multioutput_regression_x16 | 32.243 | 23.974 | 1.614 |
| sklearn_rf_multioutput_regression_x1667 | 5173.697 | 2501.272 | 171.653 |
| uneven | 2030.733 | 1304.744 | 69.885 |
| xgboost_regression | 2.090 | 1.635 | 0.085 |
| xgboost_regression_x16 | 28.536 | 23.574 | 1.244 |
| xgboost_regression_x1667 | 4489.850 | 2500.559 | 137.424 |

Packed-copy copies an already serialized checkpoint; it is not serialization of an editable model.

## Default four-worker policy (four available cores)


### Decode

| Case | treelite-native | balsa-default |
|---|---:|---:|
| sklearn_rf_multioutput_regression_x1667 | 9313.547 | 11151.134 |
| xgboost_regression_x1667 | 7751.105 | 9873.370 |

### Encode

| Case | treelite-native | balsa-default |
|---|---:|---:|
| sklearn_rf_multioutput_regression_x1667 | 6015.454 | 4149.096 |
| xgboost_regression_x1667 | 5238.137 | 4031.798 |

## Ratios against native Treelite

Ratio = engine time / native time. Below 1 is faster. Intervals resample process-group means
within each order block (5,000 bootstrap draws). Blocks and all samples are retained.
These are descriptive intervals, not a multiple-comparison-corrected significance test.

| Section | Case | Operation | Engine | Ratio | 95% interval | Block 0 / 1 | Assessment |
|---|---|---|---|---:|---|---|---|
| default | sklearn_rf_multioutput_regression_x1667 | decode | balsa-default | 1.197 | 1.153–1.243 | 1.221 / 1.173 | slower |
| default | sklearn_rf_multioutput_regression_x1667 | encode | balsa-default | 0.690 | 0.680–0.700 | 0.723 / 0.658 | faster |
| default | xgboost_regression_x1667 | decode | balsa-default | 1.274 | 1.186–1.361 | 1.248 / 1.301 | slower |
| default | xgboost_regression_x1667 | encode | balsa-default | 0.770 | 0.736–0.797 | 0.783 / 0.757 | faster |
| serial | catboost_numeric_regression | decode | treelite-python | 1.863 | 1.762–1.985 | 1.892 / 1.833 | slower |
| serial | catboost_numeric_regression | decode | balsa-on | 1.193 | 1.153–1.218 | 1.175 / 1.211 | slower |
| serial | catboost_numeric_regression | decode | balsa-off | 0.891 | 0.847–0.941 | 0.905 / 0.876 | faster |
| serial | catboost_numeric_regression | decode | balsa-borrow-on | 1.179 | 1.140–1.216 | 1.181 / 1.178 | slower |
| serial | catboost_numeric_regression | decode | balsa-borrow-off | 0.854 | 0.819–0.890 | 0.854 / 0.853 | faster |
| serial | catboost_numeric_regression | decode | packed-on | 1.195 | 1.152–1.238 | 1.193 / 1.196 | slower |
| serial | catboost_numeric_regression | decode | packed-off | 0.306 | 0.296–0.312 | 0.299 / 0.313 | faster |
| serial | catboost_numeric_regression | encode | treelite-python | 1.566 | 1.543–1.590 | 1.553 / 1.579 | slower |
| serial | catboost_numeric_regression | encode | balsa-on | 1.303 | 1.283–1.324 | 1.295 / 1.310 | slower |
| serial | catboost_numeric_regression | encode | balsa-off | 0.792 | 0.780–0.804 | 0.789 / 0.795 | faster |
| serial | catboost_numeric_regression | encode | packed-copy | 0.042 | 0.042–0.043 | 0.042 / 0.043 | faster |
| serial | dominant | decode | treelite-python | 2.299 | 2.198–2.390 | 2.278 / 2.319 | slower |
| serial | dominant | decode | balsa-on | 1.199 | 1.186–1.211 | 1.210 / 1.189 | slower |
| serial | dominant | decode | balsa-off | 0.900 | 0.887–0.911 | 0.910 / 0.890 | faster |
| serial | dominant | decode | balsa-borrow-on | 1.207 | 1.162–1.242 | 1.283 / 1.134 | slower |
| serial | dominant | decode | balsa-borrow-off | 0.879 | 0.857–0.909 | 0.907 / 0.851 | faster |
| serial | dominant | decode | packed-on | 0.878 | 0.869–0.885 | 0.889 / 0.867 | faster |
| serial | dominant | decode | packed-off | 0.213 | 0.211–0.215 | 0.216 / 0.211 | faster |
| serial | dominant | encode | treelite-python | 0.929 | 0.918–0.941 | 0.937 / 0.922 | faster |
| serial | dominant | encode | balsa-on | 1.025 | 1.013–1.037 | 1.056 / 0.996 | overlap/inconsistent |
| serial | dominant | encode | balsa-off | 0.618 | 0.610–0.628 | 0.637 / 0.601 | faster |
| serial | dominant | encode | packed-copy | 0.035 | 0.034–0.035 | 0.034 / 0.035 | faster |
| serial | few-large | decode | treelite-python | 2.060 | 2.047–2.073 | 2.048 / 2.070 | slower |
| serial | few-large | decode | balsa-on | 3.162 | 3.110–3.213 | 3.203 / 3.124 | slower |
| serial | few-large | decode | balsa-off | 0.643 | 0.639–0.647 | 0.634 / 0.651 | faster |
| serial | few-large | decode | balsa-borrow-on | 2.873 | 2.831–2.930 | 2.986 / 2.770 | slower |
| serial | few-large | decode | balsa-borrow-off | 0.424 | 0.418–0.432 | 0.430 / 0.418 | faster |
| serial | few-large | decode | packed-on | 2.958 | 2.924–2.991 | 2.990 / 2.929 | slower |
| serial | few-large | decode | packed-off | 0.251 | 0.250–0.253 | 0.252 / 0.251 | faster |
| serial | few-large | encode | treelite-python | 1.007 | 0.963–1.051 | 1.085 / 0.935 | overlap/inconsistent |
| serial | few-large | encode | balsa-on | 1.104 | 1.071–1.141 | 1.169 / 1.044 | slower |
| serial | few-large | encode | balsa-off | 0.128 | 0.125–0.131 | 0.136 / 0.120 | faster |
| serial | few-large | encode | packed-copy | 0.079 | 0.077–0.082 | 0.085 / 0.074 | faster |
| serial | leaves | decode | treelite-python | 0.994 | 0.956–1.033 | 1.014 / 0.976 | overlap/inconsistent |
| serial | leaves | decode | balsa-on | 0.621 | 0.601–0.642 | 0.631 / 0.612 | faster |
| serial | leaves | decode | balsa-off | 0.580 | 0.561–0.599 | 0.584 / 0.577 | faster |
| serial | leaves | decode | balsa-borrow-on | 0.620 | 0.599–0.641 | 0.619 / 0.621 | faster |
| serial | leaves | decode | balsa-borrow-off | 0.571 | 0.551–0.589 | 0.573 / 0.568 | faster |
| serial | leaves | decode | packed-on | 0.390 | 0.377–0.402 | 0.393 / 0.387 | faster |
| serial | leaves | decode | packed-off | 0.131 | 0.127–0.135 | 0.132 / 0.130 | faster |
| serial | leaves | encode | treelite-python | 0.926 | 0.890–0.978 | 0.933 / 0.918 | faster |
| serial | leaves | encode | balsa-on | 1.057 | 1.041–1.071 | 1.038 / 1.076 | slower |
| serial | leaves | encode | balsa-off | 0.915 | 0.901–0.926 | 0.896 / 0.933 | faster |
| serial | leaves | encode | packed-copy | 0.012 | 0.012–0.012 | 0.011 / 0.013 | faster |
| serial | lightgbm_categorical | decode | treelite-python | 1.680 | 1.652–1.705 | 1.698 / 1.662 | slower |
| serial | lightgbm_categorical | decode | balsa-on | 1.069 | 1.053–1.083 | 1.094 / 1.044 | slower |
| serial | lightgbm_categorical | decode | balsa-off | 0.905 | 0.874–0.945 | 0.893 / 0.916 | faster |
| serial | lightgbm_categorical | decode | balsa-borrow-on | 1.047 | 1.031–1.062 | 1.059 / 1.035 | slower |
| serial | lightgbm_categorical | decode | balsa-borrow-off | 0.883 | 0.853–0.915 | 0.891 / 0.874 | faster |
| serial | lightgbm_categorical | decode | packed-on | 0.950 | 0.937–0.962 | 0.964 / 0.937 | faster |
| serial | lightgbm_categorical | decode | packed-off | 0.266 | 0.262–0.269 | 0.270 / 0.262 | faster |
| serial | lightgbm_categorical | encode | treelite-python | 1.555 | 1.546–1.564 | 1.555 / 1.555 | slower |
| serial | lightgbm_categorical | encode | balsa-on | 1.073 | 1.068–1.077 | 1.072 / 1.074 | slower |
| serial | lightgbm_categorical | encode | balsa-off | 0.768 | 0.764–0.772 | 0.766 / 0.769 | faster |
| serial | lightgbm_categorical | encode | packed-copy | 0.031 | 0.031–0.031 | 0.031 / 0.031 | faster |
| serial | sklearn_extra_multioutput_classification | decode | treelite-python | 1.633 | 1.624–1.642 | 1.636 / 1.631 | slower |
| serial | sklearn_extra_multioutput_classification | decode | balsa-on | 1.131 | 1.126–1.135 | 1.132 / 1.129 | slower |
| serial | sklearn_extra_multioutput_classification | decode | balsa-off | 0.863 | 0.859–0.867 | 0.864 / 0.862 | faster |
| serial | sklearn_extra_multioutput_classification | decode | balsa-borrow-on | 1.096 | 1.092–1.101 | 1.098 / 1.095 | slower |
| serial | sklearn_extra_multioutput_classification | decode | balsa-borrow-off | 0.832 | 0.829–0.835 | 0.834 / 0.831 | faster |
| serial | sklearn_extra_multioutput_classification | decode | packed-on | 0.992 | 0.985–0.999 | 0.987 / 0.996 | faster |
| serial | sklearn_extra_multioutput_classification | decode | packed-off | 0.258 | 0.253–0.264 | 0.251 / 0.264 | faster |
| serial | sklearn_extra_multioutput_classification | encode | treelite-python | 1.518 | 1.512–1.524 | 1.520 / 1.515 | slower |
| serial | sklearn_extra_multioutput_classification | encode | balsa-on | 1.180 | 1.177–1.184 | 1.181 / 1.179 | slower |
| serial | sklearn_extra_multioutput_classification | encode | balsa-off | 0.747 | 0.732–0.757 | 0.763 / 0.732 | faster |
| serial | sklearn_extra_multioutput_classification | encode | packed-copy | 0.044 | 0.044–0.044 | 0.044 / 0.044 | faster |
| serial | sklearn_gradient_binary | decode | treelite-python | 1.641 | 1.630–1.652 | 1.650 / 1.633 | slower |
| serial | sklearn_gradient_binary | decode | balsa-on | 1.167 | 1.155–1.179 | 1.167 / 1.167 | slower |
| serial | sklearn_gradient_binary | decode | balsa-off | 0.863 | 0.852–0.876 | 0.862 / 0.865 | faster |
| serial | sklearn_gradient_binary | decode | balsa-borrow-on | 1.139 | 1.132–1.146 | 1.135 / 1.143 | slower |
| serial | sklearn_gradient_binary | decode | balsa-borrow-off | 0.834 | 0.828–0.839 | 0.836 / 0.832 | faster |
| serial | sklearn_gradient_binary | decode | packed-on | 1.048 | 1.039–1.055 | 1.038 / 1.057 | slower |
| serial | sklearn_gradient_binary | decode | packed-off | 0.251 | 0.250–0.253 | 0.250 / 0.253 | faster |
| serial | sklearn_gradient_binary | encode | treelite-python | 1.524 | 1.515–1.533 | 1.518 / 1.530 | slower |
| serial | sklearn_gradient_binary | encode | balsa-on | 1.282 | 1.273–1.292 | 1.277 / 1.287 | slower |
| serial | sklearn_gradient_binary | encode | balsa-off | 0.754 | 0.751–0.758 | 0.753 / 0.755 | faster |
| serial | sklearn_gradient_binary | encode | packed-copy | 0.041 | 0.041–0.041 | 0.041 / 0.041 | faster |
| serial | sklearn_hist_missing_regression | decode | treelite-python | 1.707 | 1.685–1.728 | 1.734 / 1.680 | slower |
| serial | sklearn_hist_missing_regression | decode | balsa-on | 1.186 | 1.175–1.197 | 1.188 / 1.184 | slower |
| serial | sklearn_hist_missing_regression | decode | balsa-off | 0.923 | 0.870–0.998 | 0.866 / 0.980 | faster |
| serial | sklearn_hist_missing_regression | decode | balsa-borrow-on | 1.169 | 1.157–1.181 | 1.167 / 1.171 | slower |
| serial | sklearn_hist_missing_regression | decode | balsa-borrow-off | 0.845 | 0.834–0.855 | 0.842 / 0.847 | faster |
| serial | sklearn_hist_missing_regression | decode | packed-on | 1.084 | 1.074–1.093 | 1.078 / 1.090 | slower |
| serial | sklearn_hist_missing_regression | decode | packed-off | 0.270 | 0.267–0.273 | 0.270 / 0.270 | faster |
| serial | sklearn_hist_missing_regression | encode | treelite-python | 1.532 | 1.519–1.546 | 1.526 / 1.538 | slower |
| serial | sklearn_hist_missing_regression | encode | balsa-on | 1.289 | 1.274–1.305 | 1.290 / 1.288 | slower |
| serial | sklearn_hist_missing_regression | encode | balsa-off | 0.761 | 0.756–0.765 | 0.757 / 0.765 | faster |
| serial | sklearn_hist_missing_regression | encode | packed-copy | 0.041 | 0.041–0.042 | 0.041 / 0.042 | faster |
| serial | sklearn_rf_multiclass | decode | treelite-python | 1.669 | 1.659–1.681 | 1.666 / 1.672 | slower |
| serial | sklearn_rf_multiclass | decode | balsa-on | 1.129 | 1.124–1.135 | 1.132 / 1.126 | slower |
| serial | sklearn_rf_multiclass | decode | balsa-off | 0.853 | 0.848–0.858 | 0.858 / 0.847 | faster |
| serial | sklearn_rf_multiclass | decode | balsa-borrow-on | 1.100 | 1.098–1.103 | 1.096 / 1.104 | slower |
| serial | sklearn_rf_multiclass | decode | balsa-borrow-off | 0.828 | 0.825–0.832 | 0.825 / 0.832 | faster |
| serial | sklearn_rf_multiclass | decode | packed-on | 1.257 | 1.252–1.262 | 1.251 / 1.262 | slower |
| serial | sklearn_rf_multiclass | decode | packed-off | 0.257 | 0.256–0.258 | 0.258 / 0.256 | faster |
| serial | sklearn_rf_multiclass | encode | treelite-python | 1.534 | 1.526–1.542 | 1.541 / 1.527 | slower |
| serial | sklearn_rf_multiclass | encode | balsa-on | 1.189 | 1.185–1.194 | 1.190 / 1.189 | slower |
| serial | sklearn_rf_multiclass | encode | balsa-off | 0.703 | 0.699–0.706 | 0.706 / 0.700 | faster |
| serial | sklearn_rf_multiclass | encode | packed-copy | 0.044 | 0.044–0.044 | 0.044 / 0.044 | faster |
| serial | sklearn_rf_multioutput_regression | decode | treelite-python | 1.635 | 1.628–1.642 | 1.634 / 1.635 | slower |
| serial | sklearn_rf_multioutput_regression | decode | balsa-on | 1.139 | 1.135–1.142 | 1.135 / 1.142 | slower |
| serial | sklearn_rf_multioutput_regression | decode | balsa-off | 0.864 | 0.861–0.867 | 0.862 / 0.865 | faster |
| serial | sklearn_rf_multioutput_regression | decode | balsa-borrow-on | 1.127 | 1.123–1.131 | 1.127 / 1.127 | slower |
| serial | sklearn_rf_multioutput_regression | decode | balsa-borrow-off | 0.834 | 0.830–0.838 | 0.829 / 0.839 | faster |
| serial | sklearn_rf_multioutput_regression | decode | packed-on | 1.007 | 1.004–1.010 | 1.002 / 1.012 | slower |
| serial | sklearn_rf_multioutput_regression | decode | packed-off | 0.248 | 0.247–0.249 | 0.247 / 0.248 | faster |
| serial | sklearn_rf_multioutput_regression | encode | treelite-python | 1.606 | 1.548–1.666 | 1.678 / 1.535 | slower |
| serial | sklearn_rf_multioutput_regression | encode | balsa-on | 1.267 | 1.232–1.309 | 1.283 / 1.250 | slower |
| serial | sklearn_rf_multioutput_regression | encode | balsa-off | 0.743 | 0.736–0.749 | 0.735 / 0.750 | faster |
| serial | sklearn_rf_multioutput_regression | encode | packed-copy | 0.045 | 0.045–0.045 | 0.045 / 0.045 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | decode | treelite-python | 1.099 | 1.095–1.103 | 1.095 / 1.104 | slower |
| serial | sklearn_rf_multioutput_regression_x16 | decode | balsa-on | 1.050 | 1.042–1.060 | 1.051 / 1.049 | slower |
| serial | sklearn_rf_multioutput_regression_x16 | decode | balsa-off | 0.804 | 0.798–0.810 | 0.798 / 0.810 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | decode | balsa-borrow-on | 1.016 | 1.011–1.021 | 1.011 / 1.021 | slower |
| serial | sklearn_rf_multioutput_regression_x16 | decode | balsa-borrow-off | 0.770 | 0.767–0.773 | 0.769 / 0.771 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | decode | packed-on | 0.790 | 0.786–0.795 | 0.788 / 0.792 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | decode | packed-off | 0.177 | 0.177–0.178 | 0.178 / 0.177 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | encode | treelite-python | 0.979 | 0.976–0.982 | 0.979 / 0.979 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | encode | balsa-on | 1.218 | 1.209–1.229 | 1.206 / 1.230 | slower |
| serial | sklearn_rf_multioutput_regression_x16 | encode | balsa-off | 0.744 | 0.741–0.746 | 0.727 / 0.761 | faster |
| serial | sklearn_rf_multioutput_regression_x16 | encode | packed-copy | 0.050 | 0.050–0.050 | 0.049 / 0.051 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | treelite-python | 1.091 | 1.081–1.101 | 1.066 / 1.115 | slower |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | balsa-on | 1.251 | 1.192–1.293 | 1.322 / 1.187 | slower |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | balsa-off | 0.941 | 0.933–0.949 | 0.949 / 0.935 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | balsa-borrow-on | 1.078 | 1.063–1.092 | 1.074 / 1.081 | slower |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | balsa-borrow-off | 0.848 | 0.840–0.856 | 0.863 / 0.835 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | packed-on | 0.636 | 0.631–0.642 | 0.652 / 0.623 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | decode | packed-off | 0.145 | 0.142–0.147 | 0.147 / 0.142 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | encode | treelite-python | 0.952 | 0.939–0.966 | 0.946 / 0.959 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | encode | balsa-on | 0.807 | 0.791–0.821 | 0.796 / 0.820 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | encode | balsa-off | 0.483 | 0.480–0.488 | 0.465 / 0.503 | faster |
| serial | sklearn_rf_multioutput_regression_x1667 | encode | packed-copy | 0.033 | 0.033–0.033 | 0.032 / 0.035 | faster |
| serial | uneven | decode | treelite-python | 1.110 | 1.106–1.115 | 1.113 / 1.107 | slower |
| serial | uneven | decode | balsa-on | 1.215 | 1.205–1.225 | 1.218 / 1.211 | slower |
| serial | uneven | decode | balsa-off | 0.911 | 0.907–0.916 | 0.913 / 0.909 | faster |
| serial | uneven | decode | balsa-borrow-on | 1.173 | 1.167–1.181 | 1.179 / 1.167 | slower |
| serial | uneven | decode | balsa-borrow-off | 0.871 | 0.867–0.875 | 0.877 / 0.865 | faster |
| serial | uneven | decode | packed-on | 0.881 | 0.875–0.886 | 0.882 / 0.879 | faster |
| serial | uneven | decode | packed-off | 0.222 | 0.220–0.225 | 0.226 / 0.218 | faster |
| serial | uneven | encode | treelite-python | 0.967 | 0.946–1.001 | 0.951 / 0.982 | overlap/inconsistent |
| serial | uneven | encode | balsa-on | 1.096 | 1.077–1.122 | 1.070 / 1.123 | slower |
| serial | uneven | encode | balsa-off | 0.642 | 0.640–0.646 | 0.640 / 0.645 | faster |
| serial | uneven | encode | packed-copy | 0.034 | 0.034–0.035 | 0.034 / 0.035 | faster |
| serial | xgboost_regression | decode | treelite-python | 1.721 | 1.703–1.737 | 1.721 / 1.720 | slower |
| serial | xgboost_regression | decode | balsa-on | 1.237 | 1.229–1.243 | 1.241 / 1.232 | slower |
| serial | xgboost_regression | decode | balsa-off | 0.905 | 0.897–0.914 | 0.897 / 0.912 | faster |
| serial | xgboost_regression | decode | balsa-borrow-on | 1.208 | 1.201–1.214 | 1.206 / 1.210 | slower |
| serial | xgboost_regression | decode | balsa-borrow-off | 0.894 | 0.885–0.902 | 0.884 / 0.903 | faster |
| serial | xgboost_regression | decode | packed-on | 1.106 | 1.100–1.112 | 1.099 / 1.113 | slower |
| serial | xgboost_regression | decode | packed-off | 0.277 | 0.276–0.279 | 0.277 / 0.278 | faster |
| serial | xgboost_regression | encode | treelite-python | 1.544 | 1.532–1.555 | 1.549 / 1.540 | slower |
| serial | xgboost_regression | encode | balsa-on | 1.311 | 1.301–1.319 | 1.311 / 1.311 | slower |
| serial | xgboost_regression | encode | balsa-off | 0.782 | 0.777–0.787 | 0.784 / 0.780 | faster |
| serial | xgboost_regression | encode | packed-copy | 0.041 | 0.041–0.041 | 0.041 / 0.041 | faster |
| serial | xgboost_regression_x16 | decode | treelite-python | 1.139 | 1.099–1.186 | 1.151 / 1.127 | slower |
| serial | xgboost_regression_x16 | decode | balsa-on | 1.111 | 1.085–1.136 | 1.101 / 1.121 | slower |
| serial | xgboost_regression_x16 | decode | balsa-off | 0.821 | 0.802–0.835 | 0.808 / 0.834 | faster |
| serial | xgboost_regression_x16 | decode | balsa-borrow-on | 1.102 | 1.072–1.131 | 1.113 / 1.091 | slower |
| serial | xgboost_regression_x16 | decode | balsa-borrow-off | 0.802 | 0.783–0.815 | 0.787 / 0.817 | faster |
| serial | xgboost_regression_x16 | decode | packed-on | 0.850 | 0.831–0.866 | 0.834 / 0.866 | faster |
| serial | xgboost_regression_x16 | decode | packed-off | 0.193 | 0.189–0.197 | 0.190 / 0.197 | faster |
| serial | xgboost_regression_x16 | encode | treelite-python | 0.976 | 0.968–0.982 | 0.978 / 0.974 | faster |
| serial | xgboost_regression_x16 | encode | balsa-on | 1.358 | 1.346–1.367 | 1.364 / 1.352 | slower |
| serial | xgboost_regression_x16 | encode | balsa-off | 0.826 | 0.819–0.831 | 0.829 / 0.823 | faster |
| serial | xgboost_regression_x16 | encode | packed-copy | 0.044 | 0.043–0.044 | 0.044 / 0.043 | faster |
| serial | xgboost_regression_x1667 | decode | treelite-python | 1.155 | 1.149–1.162 | 1.156 / 1.155 | slower |
| serial | xgboost_regression_x1667 | decode | balsa-on | 1.352 | 1.337–1.367 | 1.338 / 1.365 | slower |
| serial | xgboost_regression_x1667 | decode | balsa-off | 1.093 | 1.089–1.098 | 1.054 / 1.132 | slower |
| serial | xgboost_regression_x1667 | decode | balsa-borrow-on | 1.311 | 1.297–1.323 | 1.283 / 1.339 | slower |
| serial | xgboost_regression_x1667 | decode | balsa-borrow-off | 1.055 | 1.050–1.061 | 1.018 / 1.093 | slower |
| serial | xgboost_regression_x1667 | decode | packed-on | 0.837 | 0.817–0.850 | 0.814 / 0.860 | faster |
| serial | xgboost_regression_x1667 | decode | packed-off | 0.193 | 0.191–0.196 | 0.186 / 0.200 | faster |
| serial | xgboost_regression_x1667 | encode | treelite-python | 0.930 | 0.919–0.941 | 0.935 / 0.926 | faster |
| serial | xgboost_regression_x1667 | encode | balsa-on | 0.905 | 0.896–0.913 | 0.934 / 0.879 | faster |
| serial | xgboost_regression_x1667 | encode | balsa-off | 0.557 | 0.551–0.562 | 0.569 / 0.546 | faster |
| serial | xgboost_regression_x1667 | encode | packed-copy | 0.031 | 0.030–0.031 | 0.030 / 0.031 | faster |

## Measurement quality

Completed cells: 432; measured batches: 6480; cells with pyperf warnings: 253.

Per-engine CV, batch median/p95, and block means are in summary.json. The p95 is a percentile
of batch-average times, not individual request latency. Warnings are retained in quality.json
and original logs; no noisy samples were removed.

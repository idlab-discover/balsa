"""Small deterministic checks for the report's statistical bookkeeping."""

import unittest

from analyze import affinity, bootstrap_ratio, compare, describe, percentile


def blocks(scale=1):
    return [dict(block=i, runs=[[scale * value] * 5 for value in (1, 2, 3)])
            for i in range(2)]


class AnalysisTests(unittest.TestCase):
    def test_affinity_ranges(self):
        self.assertEqual(affinity("14-17"), affinity("14,15,16,17"))

    def test_description_retains_all_batches(self):
        result = describe(blocks())
        self.assertEqual(result["values"], 30)
        self.assertEqual(result["mean_seconds"], 2)
        self.assertEqual(result["median_batch_seconds"], 2)
        self.assertEqual(result["block_means"], {"0": 2, "1": 2})

    def test_percentile_interpolates(self):
        self.assertEqual(percentile([1, 2, 3, 4], .5), 2.5)

    def test_ratio_direction_and_reproducibility(self):
        first, second = blocks(.1), blocks()
        self.assertEqual(bootstrap_ratio(first, second), bootstrap_ratio(first, second))
        result = compare(first, second, partial=False)
        self.assertAlmostEqual(result["ratio"], .1)
        self.assertEqual(result["verdict"], "faster")

    def test_partial_does_not_claim_direction(self):
        result = compare(blocks(.1), blocks(), partial=True)
        self.assertIsNone(result["bootstrap_95"])
        self.assertEqual(result["verdict"], "incomplete")


if __name__ == "__main__":
    unittest.main()

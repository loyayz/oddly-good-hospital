"""Exact populations and original-order windows; never launches a capture."""
import itertools
import math
import random
import unittest

import analyze
import analysis_reference as reference


class Clock:
    def map(self, value):
        return None if value is None or value < 0 else (value-2, value+3)


class AnalysisTests(unittest.TestCase):
    def assert_statistics(self, actual, expected):
        if isinstance(expected, dict):
            self.assertEqual(actual.keys(), expected.keys())
            for key in expected:
                self.assert_statistics(actual[key], expected[key])
        elif isinstance(expected, (list, tuple)):
            self.assertEqual(len(actual), len(expected))
            for left, right in zip(actual, expected):
                self.assert_statistics(left, right)
        elif isinstance(expected, float):
            self.assertAlmostEqual(actual, expected, places=8)
        else:
            self.assertEqual(actual, expected)

    def test_every_optional_subset_and_nearest_rank(self):
        limits = {"p95_ms": 30, "p99_ms": 50, "max_ms": 100, "mean_ms": 40}
        for definite, optional in [([], []), ([], [10]), ([10], []), ([1, 20], [3, 99, 0]), ([5]*19, [6, 7])]:
            result = analyze.bounded_distribution(definite, optional, 1, limits)
            populations = [analyze.distribution(definite+[value for value, keep in zip(optional, mask) if keep])
                           for mask in itertools.product((False, True), repeat=len(optional))]
            for metric in limits:
                values = [row[metric] for row in populations if row[metric] is not None]
                self.assertEqual(result["metric_lower"][metric], min(values) if values else None)
                self.assertEqual(result["metric_upper"][metric], max(values) if values else None)
        # 19 samples have rank19 at P95; 20 have rank19, not interpolation.
        self.assertEqual(analyze.distribution(list(range(19)))["p95_ms"], 18)
        self.assertEqual(analyze.distribution(list(range(20)))["p95_ms"], 18)

    def test_bounded_complete_output_against_exhaustive_reference(self):
        rng = random.Random(181018)
        for _ in range(400):
            definite = [rng.randrange(20000)/10 for _ in range(rng.randrange(40))]
            optional = [rng.randrange(20000)/10 for _ in range(rng.randrange(25))]
            limits = {key: rng.randrange(2000) for key in ("p95_ms", "p99_ms", "max_ms", "mean_ms")}
            minimum = rng.randrange(20)
            self.assert_statistics(analyze.bounded_distribution(definite, optional, minimum, limits),
                                   reference.bounded_distribution(definite, optional, minimum, limits))

    def test_failure_and_uncertainty_priority(self):
        self.assertEqual(analyze.bounded_distribution([101], [], 100, {"max_ms":100})["status"], "failed")
        self.assertEqual(analyze.bounded_distribution([], [101], 1, {"max_ms":100})["status"], "failed")
        self.assertEqual(analyze.bounded_distribution([], [99], 1, {"max_ms":100})["status"], "insufficient_samples")
        self.assertEqual(analyze.bounded_distribution([1], [101], 1, {"max_ms":100})["status"], "boundary_uncertain")
        self.assertEqual(analyze.bounded_distribution([100], [100], 1, {"max_ms":100})["status"], "observed_within_limits")

    def test_index_boundaries_and_unsorted_original_order(self):
        records = [{"n":i,"point":point,"bounds":bounds} for i,(point,bounds) in enumerate(
            [(10,(10,10)), (5,(4,6)), (20,(19,21)), (5,None), (30,(-100,100)), (0,(0,1)), (9,(8,10))])]
        points = analyze.PointWindows(records, lambda row: row["point"])
        intervals = analyze.IntervalWindows(records,"bounds")
        for start,end in [(-200,-100), (5,10), (10,20), (0,1), (-100,100), (20,30)]:
            self.assertEqual(points.select(start,end), [row for row in records if start <= row["point"] < end])
            self.assertEqual(intervals.select(start,end), [row for row in records if analyze.membership(row["bounds"],start,end) in ("definite","optional")])
        self.assertEqual(intervals.unmapped,1)

    def test_speed_and_step_windows_preserve_pauses_matches_and_counts(self):
        rng = random.Random(411018)
        clock = Clock()
        limits = {"p95_ms":20,"p99_ms":25,"max_ms":40}
        for _ in range(50):
            steps = []
            for index in range(80):
                point = rng.randrange(1000)
                steps.append({"hospital_session":str(index%3),"started_engine_us":point,"elapsed_us":rng.randrange(80000),
                              "main_elapsed_us":10,"between_slices_wall_us":20,
                              "_start_bounds":clock.map(point if index%17 else -1),
                              "_completion_bounds":clock.map(point+10 if index%19 else -1)})
            telemetry = []
            for index in range(30):
                point = rng.randrange(1000)
                telemetry.append({"kind":"session_state","qpc_ticks":point,"engine_us":point if index%11 else -1,
                                  "actual_speed":rng.choice([0,1,2]),"requested_speed":rng.choice([0,1]),
                                  "pause_reasons":["focus"] if index%3 else ["save"],"step_in_progress":index%5==0,
                                  "hospital_session":str(index%3),"original_step_started_us":steps[index]["started_engine_us"]})
            indexed_steps = analyze.StepWindows(steps)
            indexed_speed = analyze.SpeedWindows(telemetry,indexed_steps,clock)
            for start,end in [(-1,0),(0,100),(200,400),(400,500),(500,1000),(1000,1200)]:
                self.assert_statistics(analyze.step_population(steps,start,end,2,limits,indexed_steps),
                                       reference.step_population(steps,start,end,2,limits))
                self.assert_statistics(analyze.speed_window(telemetry,steps,clock,start,end,100,1,indexed_speed),
                                       reference.speed_window(telemetry,steps,clock,start,end,100,1))

    def test_started_step_completion_is_charged_to_pause(self):
        steps = [{"hospital_session":"h","started_engine_us":0,"_start_bounds":(0,0),"_completion_bounds":(25,25)}]
        states = [{"kind":"session_state","qpc_ticks":0,"engine_us":0,"actual_speed":1},
                  {"kind":"session_state","qpc_ticks":10,"engine_us":10,"actual_speed":0,"requested_speed":0,
                   "step_in_progress":True,"hospital_session":"h","original_step_started_us":0},
                  {"kind":"session_state","qpc_ticks":40,"engine_us":40,"actual_speed":1}]
        result = analyze.speed_window(states,steps,Clock(),0,50,10,1)
        self.assertEqual(result["definite_pause_intervals_qpc"],[(25,38)])
        self.assertEqual(result["possible_pause_intervals_qpc"],[(25,43)])
        self.assertEqual(result["active_real_seconds_lower"],3.2)
        self.assertEqual(result["active_real_seconds_upper"],3.7)

    def test_large_absolute_qpc_preserves_single_tick_pauses(self):
        origin = 2**53
        intervals = [(origin,origin+1),(origin+3,origin+7)]
        indexed = analyze.IntervalUnion(intervals)
        self.assertEqual(indexed.covered(origin,origin+8),5)
        self.assertEqual(indexed.covered(origin,origin+1),1)
        self.assertEqual(indexed.covered(origin+1,origin+3),0)
        self.assertEqual(indexed.covered(origin+4,origin+6),2)
        self.assertEqual(indexed.covered(origin,origin+8),reference.union_length(intervals,origin,origin+8))


if __name__ == "__main__":
    unittest.main()
